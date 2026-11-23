-- Compiler le projet (Espace k), façon « M-x compile » d'Emacs, en mieux :
--   • système de build le plus proche détecté (util.project), commande pré-remplie et modifiable,
--     retenue par projet d'une session à l'autre, historique avec ↑ / ↓ ;
--   • sortie en couleurs (terminal, panneau du bas) ; les erreurs sont lues sur une copie
--     sans codes ANSI ni retours à la ligne du terminal ;
--   • erreurs → quickfix ET diagnostics dans les fichiers (même non ouverts) : ]e / [e ;
--   • indicateur dans lualine, notification de fin, mode surveillance, choix d'une cible.
local M = {}

local uv = vim.uv
local project = require("util.project")

M.ns = vim.api.nvim_create_namespace("compilation")
M.db_path = vim.env.NIDE_COMPILE_DB or (vim.fn.stdpath("data") .. "/nide-compile.json")
M.last = nil -- dernière compilation lancée : { cmd, root, opts }
M.state = nil -- compilation en cours : { cmd, root, start, lines, partial, silent, main }
M.result = nil -- dernier résultat : { ok, errors, warnings, duration, code }
M.watch = nil -- surveillance : { root, cmd, group, timer }

local TITLE = "Compilation"
local task -- tâche overseer « Compiler », réutilisée à chaque lancement

local function notify(msg, level, opts)
	vim.notify(msg, level or vim.log.levels.INFO, vim.tbl_extend("force", { title = TITLE, id = "nide_compile" }, opts or {}))
end

-- ---------------------------------------------------------------------------
-- Mémoire : commande retenue par projet + historique (fichier JSON)
-- ---------------------------------------------------------------------------
local db
local function load()
	if db then
		return db
	end
	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(M.db_path), "\n"))
	end)
	db = ok and type(data) == "table" and data or {}
	db.commands = type(db.commands) == "table" and db.commands or {}
	db.history = type(db.history) == "table" and db.history or {}
	return db
end

local function save()
	vim.fn.mkdir(vim.fs.dirname(M.db_path), "p")
	pcall(vim.fn.writefile, { vim.json.encode(db) }, M.db_path)
end

function M.remember(root, cmd)
	local d = load()
	d.commands[root] = cmd
	local hist = { cmd }
	for _, h in ipairs(d.history) do
		if h ~= cmd and #hist < 50 then
			table.insert(hist, h)
		end
	end
	d.history = hist
	save()
end

function M.history_list()
	return vim.list_extend({}, load().history)
end

-- Commande pour ce projet : celle retenue, sinon celle détectée
function M.command_for(p)
	return load().commands[p.root] or p.cmd
end

-- ---------------------------------------------------------------------------
-- Analyse de la sortie
-- ---------------------------------------------------------------------------

-- Retire les codes ANSI (couleurs, liens OSC 8) et les retours chariot (barres de progression)
local function strip(s)
	s = s:gsub("\27%][^\7\27]*\7", "")
		:gsub("\27%][^\27]*\27\\", "")
		:gsub("\27%[[%d;:?<=>]*[ -/]*[@-~]", "")
		:gsub("\27[@-Z\\-_]", "")
		:gsub("\r+$", "")
		:gsub("^.*\r", "")
	return s
end
M.strip = strip

local SEV = {
	error = "E", ["fatal error"] = "E", erreur = "E", ["erreur fatale"] = "E", Error = "E",
	warning = "W", attention = "W", avertissement = "W", Warning = "W",
	note = "N", remark = "N", remarque = "N", info = "N", information = "N", hint = "N", help = "N",
}
local C_EXT = { c = true, h = true, cc = true, cpp = true, cxx = true, hpp = true, hh = true, hxx = true }
local TEX_EXT = { tex = true, sty = true, cls = true, bib = true, ltx = true, dtx = true }

local function severity(word)
	if not word then
		return nil
	end
	return SEV[word] or SEV[word:lower()] or (word:match("Error$") and "E") or (word:match("Warning$") and "W") or nil
end

-- gcc compte les colonnes « à l'écran » (tabulation = 8) ; Neovim veut des octets
local function byte_col(lines, lnum, col)
	local line = lines and lines[lnum]
	if not line or not line:find("[\t\128-\255]") then
		return col
	end
	local d, i = 1, 1
	while i <= #line do
		if d >= col then
			return i
		end
		local c = line:byte(i)
		local len = c < 0x80 and 1 or c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC0 and 2 or 1
		if c == 9 then
			d = d + 8 - ((d - 1) % 8)
		elseif len == 1 then
			d = d + 1
		else
			d = d + vim.fn.strdisplaywidth(line:sub(i, i + len - 1))
		end
		i = i + len
	end
	return i
end

-- Analyse les lignes (sans ANSI) d'une compilation lancée dans `cwd`.
-- Formats : gcc/clang (erreur, avertissement, note ; make -C / « Entering directory »), éditeur
-- de liens, rustc/cargo, go, tsc, eslint, pyright, ruff, Python (traceback, SyntaxError),
-- latexmk -file-line-error, CMake, shellcheck -f gcc.
-- Renvoie des éléments quickfix : { filename, lnum, col (octet, 1 = début), type E/W/N, text }.
function M.parse(lines, cwd, opts)
	opts = opts or {}
	local items, seen = {}, {}
	local dirs = { cwd }
	local stat, contents = {}, {}
	local clang = false
	for _, l in ipairs(lines) do
		if l:find("clang", 1, true) then
			clang = true
			break
		end
	end

	local function isfile(p)
		if stat[p] == nil then
			local st = uv.fs_stat(p)
			stat[p] = st ~= nil and st.type == "file"
		end
		return stat[p]
	end

	-- chemin absolu : dossier make courant, dossier de la commande, puis ses parents
	-- (espaces de travail cargo, chemins relatifs à la racine du dépôt)
	local function resolve(f)
		f = vim.trim(f)
		if f == "" or #f > 4096 then
			return nil
		end
		local cands = {}
		if f:sub(1, 1) == "/" then
			cands = { f }
		else
			for i = #dirs, 1, -1 do
				table.insert(cands, dirs[i] .. "/" .. f)
			end
			local d = vim.fs.dirname(cwd)
			for _ = 1, 4 do
				if not d or d == "/" then
					break
				end
				table.insert(cands, d .. "/" .. f)
				d = vim.fs.dirname(d)
			end
		end
		for _, c in ipairs(cands) do
			if isfile(c) then
				return vim.fs.normalize(vim.fn.fnamemodify(c, ":p"))
			end
		end
	end

	local last
	local function add(f, lnum, col, typ, text, gcc)
		local path = resolve(f)
		if not path then
			return false
		end
		lnum, col = tonumber(lnum) or 1, tonumber(col) or 0
		if gcc and not clang and col > 0 and C_EXT[(path:match("%.(%w+)$") or ""):lower()] then
			if contents[path] == nil then
				local ok, l = pcall(vim.fn.readfile, path)
				contents[path] = ok and l or false
			end
			col = byte_col(contents[path] or nil, lnum, col)
		end
		text = vim.trim(text or "")
		local key = table.concat({ path, lnum, col, typ, text }, "\0")
		if seen[key] then
			return true
		end
		seen[key] = true
		last = { filename = path, lnum = lnum, col = col, type = typ, text = text, valid = 1 }
		table.insert(items, last)
		return true
	end

	local header -- en-tête rustc / ruff en attente de « --> fichier:l:c »
	local pyloc -- dernier « File "x.py", line n » (traceback Python)
	local eslint -- fichier courant du format « stylish » d'eslint
	local want_text -- élément CMake dont le message est sur la ligne suivante

	for _, l in ipairs(lines) do
		local hdr = header
		header = nil
		local f, ln, c, rest, w, m

		-- make -C / make récursif / ninja : dossier courant
		local dir = l:match("[Ee]ntering directory%s+[`'‘](.-)['’]%s*$") or l:match("entre dans le répertoire%s+«%s*(.-)%s*»")
		if dir then
			if dir:sub(1, 1) ~= "/" then
				dir = dirs[#dirs] .. "/" .. dir
			end
			table.insert(dirs, dir)
			goto continue
		end
		if l:match("[Ll]eaving directory") or l:match("quitte le répertoire") then
			if #dirs > 1 then
				table.remove(dirs)
			end
			goto continue
		end

		if want_text then
			if l:match("^%s+%S") then
				want_text.text = vim.trim(l)
				want_text = nil
				goto continue
			elseif l ~= "" then
				want_text = nil
			end
		end

		-- rustc / clippy / ruff récent : « error[E0425]: … » puis « --> src/main.rs:2:13 »
		f, ln, c = l:match("^%s*%-%->%s*(.-):(%d+):(%d+)%s*$")
		if f then
			if hdr then
				add(f, ln, c, hdr.type, hdr.text)
			end
			goto continue
		end
		w, m = l:match("^(%a+)%[[^%]]*%]: (.*)$")
		if not w then
			w, m = l:match("^(error): (.*)$")
		end
		if not w then
			w, m = l:match("^(warning): (.*)$")
		end
		if w and (w == "error" or w == "warning") then
			header = { type = w == "error" and "E" or "W", text = m }
			goto continue
		end
		w, m = l:match("^(%u+%d+) (.*)$") -- ruff : « F401 [*] `os` imported but unused »
		if w then
			header = { type = "W", text = w .. " " .. m }
			goto continue
		end

		-- pyright, tsc --pretty : « fichier:3:5 - error: … » / « fichier:3:5 - error TS2322: … »
		f, ln, c, w, m = l:match("^%s*(.-):(%d+):(%d+) %- (%a+):? (.*)$")
		if f and severity(w) then
			add(f, ln, c, severity(w), m)
			goto continue
		end
		-- tsc sans --pretty : « fichier(3,5): error TS2322: … »
		f, ln, c, w, m = l:match("^(.-)%((%d+),(%d+)%): (%a+) (.*)$")
		if f and severity(w) then
			add(f, ln, c, severity(w), m)
			goto continue
		end

		-- gcc, clang, go, ruff (concise), shellcheck -f gcc : « fichier:l:c: … »
		f, ln, c, rest = l:match("^(.-):(%d+):(%d+):%s*(.*)$")
		if f then
			w, m = rest:match("^(%a[%a ]-)%s?:%s+(.*)$")
			if not w then
				w, m = rest:match("^(%a+)%[[^%]]*%]:%s+(.*)$") -- rustc --error-format=short
			end
			local t = severity(w)
			if t then
				add(f, ln, c, t, m, true)
			elseif rest:match("^%u+%d+ ") then
				add(f, ln, c, "W", rest) -- code de lint (ruff, flake8)
			else
				add(f, ln, c, "E", rest) -- go et autres
			end
			goto continue
		end

		-- éditeur de liens : « src/main.c:5:(.text+0x9): undefined reference to `foo' »
		f, ln, rest = l:match("^(.-):(%d+):%(.-%):%s*(.*)$")
		if f and add(f, ln, 0, "E", rest) then
			goto continue
		end

		-- « fichier:l: … » : LaTeX (-file-line-error), make (« Makefile:5: *** … »), gcc sans colonne
		f, ln, rest = l:match("^(.-):(%d+):%s+(.*)$")
		if f then
			local ext = (f:match("%.(%w+)$") or ""):lower()
			w, m = rest:match("^(%a[%a ]-)%s?:%s+(.*)$")
			if severity(w) then
				add(f, ln, 0, severity(w), m)
			elseif TEX_EXT[ext] then
				add(f, ln, 0, "E", rest)
			elseif (vim.tbl_contains(project.MAKEFILES, vim.fs.basename(f)) or ext == "mk") and rest:match("%*%*%*") then
				add(f, ln, 0, "E", (rest:gsub("^%*%*%*%s*", "")))
			end
			goto continue
		end

		-- avertissements LaTeX : « LaTeX Warning: … on input line 12. »
		m, ln = l:match("Warning: (.-) on input line (%d+)%.")
		if m and opts.main then
			add(opts.main, ln, 0, "W", m)
			goto continue
		end

		-- CMake : « CMake Error at CMakeLists.txt:5 (add_executable): » puis message indenté
		w, f, ln = l:match("^CMake (%a+).- at (.-):(%d+)")
		if w and add(f, ln, 0, severity(w) or "E", "CMake " .. w) then
			want_text = last
			goto continue
		end

		-- Python : traceback / SyntaxError (python -m py_compile, compileall)
		f, ln = l:match('^%s*File "(.-)", line (%d+)')
		if f then
			pyloc = { f, ln }
			goto continue
		end
		if pyloc then
			w, m = l:match("^([%a_][%w_.]*): (.*)$")
			if not w then
				w = l:match("^([%a_][%w_.]*Error)$")
			end
			if w and (w:match("Error$") or w:match("Exception$") or w:match("Exit$")) then
				add(pyloc[1], pyloc[2], 0, "E", w .. (m and (": " .. m) or ""))
				pyloc = nil
				goto continue
			end
		end

		-- eslint (format stylish) : chemin seul sur une ligne, puis « 3:5  error  message  règle »
		if l:match("^/%S") and isfile(vim.trim(l)) then
			eslint = vim.trim(l)
			goto continue
		end
		if eslint then
			ln, c, w, m = l:match("^%s+(%d+):(%d+)%s+(%a+)%s+(.-)%s*$")
			if ln and severity(w) then
				add(eslint, ln, c, severity(w), m)
			elseif l == "" then
				eslint = nil
			end
		end
		::continue::
	end
	return items
end

-- ---------------------------------------------------------------------------
-- Résultats : quickfix, diagnostics, notification
-- ---------------------------------------------------------------------------
local DIAG = {
	E = vim.diagnostic.severity.ERROR,
	W = vim.diagnostic.severity.WARN,
	N = vim.diagnostic.severity.INFO,
}

function M.clear_diagnostics()
	vim.diagnostic.reset(M.ns)
end

local function set_diagnostics(items)
	M.clear_diagnostics()
	local by = {}
	for _, it in ipairs(items) do
		local buf = vim.fn.bufnr(it.filename)
		if buf == -1 then
			-- fichier non ouvert : buffer non chargé et hors de la liste des onglets
			buf = vim.fn.bufadd(it.filename)
			vim.bo[buf].buflisted = false
		end
		by[buf] = by[buf] or {}
		table.insert(by[buf], {
			lnum = math.max(it.lnum - 1, 0),
			col = math.max(it.col - 1, 0),
			severity = DIAG[it.type] or vim.diagnostic.severity.ERROR,
			message = it.text,
			source = "compilation",
		})
	end
	for buf, diags in pairs(by) do
		vim.diagnostic.set(M.ns, buf, diags)
	end
end

local function set_qflist(items, cmd)
	local cur = vim.fn.getqflist({ context = 0 }).context
	local action = (type(cur) == "table" and cur.nide_compile) and "r" or " "
	vim.fn.setqflist({}, action, { title = "Compilation : " .. cmd, items = items, context = { nide_compile = true } })
end

local function plural(n, word)
	return n .. " " .. word .. (n > 1 and "s" or "")
end

local function seconds(ns)
	return (("%.1f"):format(ns / 1e9):gsub("%.", ",")) .. " s"
end

-- Ouvre Trouble (quickfix) sans prendre le focus ; le referme après une compilation réussie
local trouble_opened = false
local function trouble(open)
	local ok, t = pcall(require, "trouble")
	if not ok then
		return
	end
	local win = vim.api.nvim_get_current_win()
	if open then
		pcall(t.open, { mode = "qflist", focus = false })
		trouble_opened = true
	elseif trouble_opened then
		pcall(t.close, { mode = "qflist" })
		trouble_opened = false
	end
	if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() ~= win then
		vim.api.nvim_set_current_win(win)
	end
end

-- ---------------------------------------------------------------------------
-- Indicateur (lualine)
-- ---------------------------------------------------------------------------
local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner

local function spin(on)
	if on and not spinner then
		spinner = uv.new_timer()
		spinner:start(0, 100, vim.schedule_wrap(function()
			pcall(vim.cmd.redrawstatus)
		end))
	elseif not on and spinner then
		spinner:stop()
		spinner:close()
		spinner = nil
		vim.schedule(function()
			pcall(vim.cmd.redrawstatus)
		end)
	end
end

local function short(cmd, n)
	n = n or 28
	return vim.fn.strchars(cmd) > n and (vim.fn.strcharpart(cmd, 0, n - 1) .. "…") or cmd
end

-- Texte de lualine : « ⠹ make -k » pendant la compilation, « 󰈈 ✓ » en surveillance
function M.status()
	local parts = {}
	if M.state then
		table.insert(parts, SPIN[math.floor(uv.hrtime() / 1e8) % #SPIN + 1] .. " " .. short(M.state.cmd))
	end
	if M.watch then
		local r = M.result and (M.result.ok and " ✓" or " ✗") or ""
		table.insert(parts, "\u{f0208}" .. r)
	end
	return table.concat(parts, "  ")
end

function M.status_color()
	if M.state then
		return "DiagnosticWarn"
	end
	return M.result and (M.result.ok and "DiagnosticOk" or "DiagnosticError") or nil
end

-- ---------------------------------------------------------------------------
-- Panneau de sortie (terminal en couleurs, en bas — edgy le range sous « Compilation »)
-- ---------------------------------------------------------------------------
function M.output_buf()
	return task and not task:is_disposed() and task:get_bufnr() or nil
end

function M.output_win()
	local buf = M.output_buf()
	if not buf then
		return nil
	end
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(w) == buf then
			return w
		end
	end
end

-- Fenêtre de code où ouvrir un fichier depuis la sortie
local function code_win()
	local function ok(w)
		return vim.api.nvim_win_is_valid(w)
			and vim.api.nvim_win_get_config(w).relative == ""
			and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == ""
			and not vim.w[w].edgy
	end
	local prev = vim.fn.win_getid(vim.fn.winnr("#"))
	if prev ~= 0 and ok(prev) then
		return prev
	end
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if ok(w) then
			return w
		end
	end
end

-- Entrée dans la sortie : aller à l'erreur de la ligne (lignes repliées par le terminal recollées)
function M.jump_from_output()
	local buf = vim.api.nvim_get_current_buf()
	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local root = (M.last and M.last.root) or uv.cwd()
	local text = ""
	for i = 0, 3 do
		local l = vim.api.nvim_buf_get_lines(buf, lnum - 1 + i, lnum + i, false)[1]
		if not l then
			break
		end
		text = text .. strip(l)
		local it = M.parse({ text }, root, { main = M.last and M.last.opts and M.last.opts.main })[1]
		if it then
			local w = code_win()
			if w then
				vim.api.nvim_set_current_win(w)
			else
				vim.cmd("aboveleft split")
			end
			vim.cmd.edit(vim.fn.fnameescape(it.filename))
			pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(it.col - 1, 0) })
			vim.cmd("normal! zz")
			return
		end
	end
	vim.notify("Pas d'erreur sur cette ligne", vim.log.levels.INFO, { title = TITLE })
end

-- Prépare le buffer de sortie (nouveau à chaque compilation)
local function setup_output_buf(buf)
	vim.bo[buf].filetype = "nide_compile"
	local function map(lhs, fn, desc)
		vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, nowait = true })
	end
	map("q", function() vim.api.nvim_win_close(0, false) end, "Fermer la sortie")
	map("<CR>", M.jump_from_output, "Aller à l'erreur de cette ligne")
	map("]e", function()
		local w = code_win()
		if w then
			vim.api.nvim_set_current_win(w)
		end
		pcall(vim.cmd.cnext)
	end, "Erreur suivante")
	map("[e", function()
		local w = code_win()
		if w then
			vim.api.nvim_set_current_win(w)
		end
		pcall(vim.cmd.cprevious)
	end, "Erreur précédente")
end

function M.show(focus)
	local buf = M.output_buf()
	if not buf then
		return notify("Rien n'a encore été compilé")
	end
	local win = M.output_win()
	if not win then
		local cur = vim.api.nvim_get_current_win()
		win = vim.api.nvim_open_win(buf, true, { split = "below", win = -1, height = math.max(8, math.floor(vim.o.lines * 0.3)) })
		for k, v in pairs({ number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0", winfixheight = true, spell = false }) do
			vim.wo[win][k] = v
		end
		if not focus and vim.api.nvim_win_is_valid(cur) then
			vim.api.nvim_set_current_win(cur)
		end
	elseif focus then
		vim.api.nvim_set_current_win(win)
	end
	return win
end

function M.toggle_output()
	local win = M.output_win()
	if win then
		vim.api.nvim_win_close(win, false)
	else
		M.show(false)
	end
end

-- ---------------------------------------------------------------------------
-- Exécution (overseer)
-- ---------------------------------------------------------------------------

-- Composant overseer : lit la sortie brute et traite la fin de la compilation
package.preload["overseer.component.nide_compile"] = function()
	return {
		desc = "Compilation nide : erreurs → quickfix + diagnostics, notification",
		constructor = function()
			return {
				on_output = function(_, t, data)
					M._output(t, data)
				end,
				on_complete = function(_, t, status)
					M._complete(t, status)
				end,
			}
		end,
	}
end

function M._output(t, data)
	local st = M.state
	if t ~= task or not st then
		return
	end
	st.partial = st.partial .. (data[1] or "")
	for i = 2, #data do
		table.insert(st.lines, strip(st.partial))
		st.partial = data[i]
	end
end

function M._complete(t, status)
	local st = M.state
	if t ~= task or not st or st.replaced then
		return
	end
	M.state = nil
	spin(false)
	if status == "CANCELED" then
		return notify("Compilation arrêtée", vim.log.levels.WARN)
	end
	if st.partial ~= "" then
		table.insert(st.lines, strip(st.partial))
	end
	local items = M.parse(st.lines, st.root, { main = st.main })
	local errors, warnings = 0, 0
	for _, it in ipairs(items) do
		if it.type == "E" then
			errors = errors + 1
		elseif it.type == "W" then
			warnings = warnings + 1
		end
	end
	set_qflist(items, st.cmd)
	set_diagnostics(items)
	local code = t.exit_code or (status == "SUCCESS" and 0 or 1)
	local dur = uv.hrtime() - st.start
	local ok = code == 0 and errors == 0
	M.result = { ok = ok, errors = errors, warnings = warnings, duration = dur, code = code, items = #items }
	local where = st.silent and " (surveillance)" or ""
	if ok then
		local msg = "✓ Compilé en " .. seconds(dur) .. where
		if warnings > 0 then
			msg = msg .. "\n" .. plural(warnings, "avertissement") .. " — ]e / Espace x q pour les voir"
		end
		notify(msg, warnings > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
		trouble(false)
	else
		local parts = {}
		if errors > 0 then
			table.insert(parts, plural(errors, "erreur"))
		end
		if warnings > 0 then
			table.insert(parts, plural(warnings, "avertissement"))
		end
		if #parts == 0 then
			table.insert(parts, "échec (code " .. code .. ")")
		end
		local msg = "✗ " .. table.concat(parts, ", ") .. where
		if errors > 0 then
			msg = msg .. "\n]e / [e : erreur suivante / précédente"
		end
		notify(msg, vim.log.levels.ERROR)
		if not st.silent then
			if #items > 0 then
				trouble(true)
			end
			M.show(false)
		end
	end
	vim.api.nvim_exec_autocmds("User", { pattern = "NideCompileDone", modeline = false, data = M.result })
end

-- Variables d'environnement : couleurs, et outils de Mason (ruff, pyright…) accessibles
local function env()
	local mason = vim.fn.stdpath("data") .. "/mason/bin"
	local path = vim.env.PATH or ""
	if uv.fs_stat(mason) and not (":" .. path .. ":"):find(":" .. mason .. ":", 1, true) then
		path = path .. ":" .. mason
	end
	return { TERM = "xterm-256color", PATH = path }
end

local function save_all()
	M.saving = true -- la surveillance ignore ces enregistrements
	pcall(vim.cmd, "silent! wall")
	M.saving = false
end

-- Lance `cmd` dans `root`. opts : silent (surveillance : pas de panneau), nosave, main (LaTeX)
function M.run(cmd, root, opts)
	opts = opts or {}
	if not opts.nosave then
		save_all()
	end
	local overseer = require("overseer")
	M.last = { cmd = cmd, root = root, opts = opts }
	if task and not task:is_disposed() and task:is_running() then
		if M.state then
			M.state.replaced = true -- l'arrêt de l'ancienne compilation reste silencieux
		end
		task:stop()
	end
	M.state = { cmd = cmd, root = root, start = uv.hrtime(), lines = {}, partial = "", silent = opts.silent, main = opts.main }
	M.clear_diagnostics()
	local name = "Compiler : " .. cmd
	local argv = { "sh", "-c", cmd }
	if task and not task:is_disposed() then
		task.name, task.cmd, task.cwd, task.env = name, argv, root, env()
		task:reset()
	else
		task = overseer.new_task({
			name = name,
			cmd = argv,
			cwd = root,
			env = env(),
			-- terminal : couleurs de gcc, cargo… ; l'analyse se fait sur la sortie brute (_output)
			strategy = { "jobstart", use_terminal = true },
			components = { "nide_compile", "on_exit_set_status" },
		})
	end
	task:start()
	local buf = task:get_bufnr()
	if buf then
		setup_output_buf(buf)
	end
	spin(true)
	if not opts.silent then
		M.show(false)
	end
end

-- Arrête la compilation en cours
function M.stop()
	if task and not task:is_disposed() and task:is_running() then
		task:stop()
	else
		notify("Aucune compilation en cours")
	end
end

-- ---------------------------------------------------------------------------
-- Commandes (Espace k …)
-- ---------------------------------------------------------------------------

-- Projet à compiler : celui du fichier courant ; depuis la sortie de compilation, le dernier
local function here()
	if M.last and vim.api.nvim_get_current_buf() == M.output_buf() then
		return project.detect(M.last.root)
	end
	return project.detect()
end

-- Espace k : demande la commande (pré-remplie, ↑ / ↓ = historique) puis compile
function M.prompt()
	local p = here()
	local default = M.command_for(p) or "make -k "
	local hist, idx = M.history_list(), 0
	local function set(self, text)
		vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { text })
		vim.api.nvim_win_set_cursor(self.win, { 1, #text })
	end
	local function move(self, delta)
		local n = math.min(math.max(idx + delta, 0), #hist)
		if n ~= idx then
			idx = n
			set(self, idx == 0 and default or hist[idx])
		end
	end
	vim.ui.input({
		prompt = ("Compiler dans %s — %s"):format(vim.fn.fnamemodify(p.root, ":~"), p.label),
		default = default,
		icon = "\u{f0ad} ",
		completion = "shellcmdline",
		win = {
			keys = {
				i_up = { "<Up>", { "nide_hist_prev" }, mode = { "i", "n" } },
				i_down = { "<Down>", { "nide_hist_next" }, mode = { "i", "n" } },
			},
			actions = {
				nide_hist_prev = function(self)
					move(self, 1)
				end,
				nide_hist_next = function(self)
					move(self, -1)
				end,
			},
		},
	}, function(input)
		input = input and vim.trim(input)
		if not input or input == "" then
			return
		end
		M.remember(p.root, input)
		M.run(input, p.root, { main = p.main })
	end)
end

-- Espace K : recompile sans rien demander (dernière commande, même dossier)
function M.recompile()
	if M.last then
		local o = vim.tbl_extend("force", M.last.opts or {}, { silent = false })
		return M.run(M.last.cmd, M.last.root, o)
	end
	local p = here()
	local cmd = M.command_for(p)
	if not cmd then
		return M.prompt()
	end
	M.run(cmd, p.root, { main = p.main })
end

-- Espace k h : relancer une commande de l'historique (dans le projet courant)
function M.history()
	local hist = M.history_list()
	if #hist == 0 then
		return notify("Historique vide : Espace k pour compiler")
	end
	local p = here()
	vim.ui.select(hist, { prompt = "Historique — " .. vim.fn.fnamemodify(p.root, ":~") }, function(cmd)
		if cmd then
			M.remember(p.root, cmd)
			M.run(cmd, p.root, { main = p.main })
		end
	end)
end

-- Espace k t : choisir une cible (Makefile, just, scripts npm, binaires cargo…) et la lancer
function M.pick_target()
	local p = here()
	local targets = p.targets()
	if #targets == 0 then
		return notify("Aucune cible trouvée (" .. p.label .. ")", vim.log.levels.WARN)
	end
	vim.ui.select(targets, {
		prompt = "Cible — " .. p.label,
		format_item = function(t)
			return t.cmd .. (t.desc and ("  — " .. t.desc) or "")
		end,
	}, function(t)
		if t then
			M.run(t.cmd, p.root, { main = p.main })
		end
	end)
end

-- Espace k w : surveillance (recompile à chaque enregistrement d'un fichier du projet)
function M.toggle_watch()
	if M.watch then
		pcall(vim.api.nvim_del_augroup_by_id, M.watch.group)
		M.watch.timer:stop()
		M.watch.timer:close()
		M.watch = nil
		pcall(vim.cmd.redrawstatus)
		return notify("Surveillance désactivée")
	end
	local p = here()
	local cmd = M.command_for(p)
	if not cmd then
		return notify("Pas de commande de compilation pour ce projet : Espace k d'abord", vim.log.levels.WARN)
	end
	local root = p.root
	local timer = uv.new_timer()
	local group = vim.api.nvim_create_augroup("nide_compile_watch", { clear = true })
	M.watch = { root = root, cmd = cmd, group = group, timer = timer, main = p.main }
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(ev)
			if M.saving or vim.bo[ev.buf].buftype ~= "" then
				return
			end
			local f = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
			if f:sub(1, #root + 1) ~= root .. "/" then
				return
			end
			-- anti-rebond : un « :wa » sur 10 fichiers ne lance qu'une compilation
			timer:stop()
			timer:start(M.debounce or 300, 0, vim.schedule_wrap(function()
				if M.watch then
					M.run(load().commands[root] or M.watch.cmd, root, { silent = true, nosave = true, main = M.watch.main })
				end
			end))
		end,
	})
	notify(("Surveillance activée : « %s » à chaque enregistrement dans %s"):format(cmd, vim.fn.fnamemodify(root, ":~")))
	M.run(cmd, root, { silent = true, main = p.main })
end

return M
