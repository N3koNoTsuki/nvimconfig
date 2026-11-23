-- Débogage « zéro configuration » (F5), pendant de F6 (util.runner) :
--   C/C++  : compile le fichier (-g -O0) ou make + choix de l'exécutable, puis codelldb
--   Rust   : cargo build (ou rustc -g), puis codelldb
--   Python : debugpy avec l'interpréteur du .venv du projet
--   Go     : nvim-dap-go (paquet courant, ou test sous le curseur dans un *_test.go)
--   Autres : dap.continue() (configurations existantes, .vscode/launch.json)
-- Makefile : avec une cible run → make puis le binaire produit (build/<nom>) ; sinon on demande
-- « fichier seul » ou « make », choix retenu par projet pour la session.
-- Le programme tourne dans la console de dap-ui (onglet « console ») : on peut y taper
-- l'entrée standard (scanf, input…) — Espace d T pour y aller.
-- À la fin du programme, dap-ui reste ouvert (sortie lisible) : q ou Espace d u pour le fermer.
local M = {}

local runner = require("util.runner")
local project = require("util.project")
local TITLE = "Débogueur"

M.last_args = "" -- derniers arguments saisis (Espace d A)
M.make_choice = {} -- dossier du Makefile → "file" | "make" (pour la session)

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
end

-- "a b 'c d'" → { "a", "b", "c d" } (guillemets simples ou doubles, façon shell)
local function split_args(s)
	local out, cur, quote = {}, nil, nil
	for c in (s or ""):gmatch(".") do
		if quote then
			if c == quote then
				quote = nil
			else
				cur = cur .. c
			end
		elseif c == "'" or c == '"' then
			quote, cur = c, cur or ""
		elseif c:match("%s") then
			if cur then
				table.insert(out, cur)
				cur = nil
			end
		else
			cur = (cur or "") .. c
		end
	end
	if cur then
		table.insert(out, cur)
	end
	return out
end
M.split_args = split_args

-- Lance codelldb sur un exécutable
local function codelldb(name, program, cwd, args, lang)
	return {
		name = name,
		type = "codelldb",
		request = "launch",
		program = program,
		cwd = cwd,
		args = args,
		stopOnEntry = false,
		-- terminal intégré (requête runInTerminal) : la console de dap-ui, où l'on peut taper
		-- l'entrée standard. « console » mélangerait la sortie au REPL, sans saisie possible.
		terminal = "integrated",
		sourceLanguages = lang and { lang } or nil,
	}
end

-- Exécutables ELF du projet (hors .git, target, node_modules…), les plus récents d'abord
local SKIP = { [".git"] = true, ["node_modules"] = true, [".venv"] = true, ["target"] = true, [".cache"] = true }
function M.find_executables(dir)
	local found = {}
	local function scan(d, depth)
		for name, kind in vim.fs.dir(d) do
			local path = d .. "/" .. name
			if kind == "directory" and depth < 3 and not SKIP[name] and name:sub(1, 1) ~= "." then
				scan(path, depth + 1)
			elseif kind == "file" and not name:match("%.so[%.%d]*$") and vim.fn.executable(path) == 1 then
				local fd = io.open(path, "rb")
				local magic = fd and fd:read(4)
				if fd then
					fd:close()
				end
				if magic == "\127ELF" then
					table.insert(found, { path = path, mtime = vim.uv.fs_stat(path).mtime.sec })
				end
			end
		end
	end
	scan(dir, 0)
	table.sort(found, function(a, b)
		return a.mtime > b.mtime
	end)
	return vim.tbl_map(function(f) return f.path end, found)
end

-- C/C++ : fichier seul, compilé avec la commande de F6 (+ -O0)
local function c_file(file, ft, args, launch)
	local p, err = runner.plan(file, ft, "")
	if not p then
		return notify(err, vim.log.levels.WARN)
	end
	table.insert(p.build, 2, "-O0")
	local out = p.build[vim.fn.index(p.build, "-o") + 2]
	runner.compile(p.build, p.cwd, { title = TITLE }, function()
		launch(codelldb("nide : " .. vim.fs.basename(file), out, p.cwd, args))
	end)
end

-- C/C++ avec Makefile : make, puis choix de l'exécutable
local function c_make(dir, args, launch)
	runner.compile({ "make" }, dir, { title = TITLE }, function()
		local exes = M.find_executables(dir)
		local function go(exe)
			if exe then
				launch(codelldb("nide : make " .. vim.fs.basename(exe), exe, dir, args))
			end
		end
		if #exes == 0 then
			return notify("Aucun exécutable trouvé dans " .. dir, vim.log.levels.WARN)
		elseif #exes == 1 then
			return go(exes[1])
		end
		vim.ui.select(exes, {
			prompt = "Exécutable à déboguer",
			format_item = function(p) return p:sub(#dir + 2) end,
		}, go)
	end)
end

local function c_cpp(file, ft, args, launch)
	local mk = project.makefile(file)
	if not mk or vim.fn.executable("make") == 0 then
		return c_file(file, ft, args, launch)
	end
	local dir = vim.fs.dirname(mk)
	-- Makefile avec cible run (projet multi-fichiers, ex. :NideNew c) : make directement, comme F6
	if project.has_target(mk, "run") then
		return c_make(dir, args, launch)
	end
	local function go(choice)
		if not choice then
			return
		end
		M.make_choice[dir] = choice
		if choice == "make" then
			c_make(dir, args, launch)
		else
			c_file(file, ft, args, launch)
		end
	end
	if M.make_choice[dir] then
		return go(M.make_choice[dir])
	end
	vim.ui.select({ "file", "make" }, {
		prompt = "Makefile trouvé (choix retenu pour la session — Espace d M pour l'oublier)",
		format_item = function(c)
			return c == "file" and "Fichier seul (" .. vim.fs.basename(file) .. ")" or "make puis choisir l'exécutable"
		end,
	}, go)
end

-- Rust : cargo build (sortie JSON → chemin exact du binaire) ou rustc -g
local function rust(file, args, launch)
	local root = vim.fs.root(file, "Cargo.toml")
	if not root then
		local p, err = runner.plan(file, "rust", "")
		if not p then
			return notify(err, vim.log.levels.WARN)
		end
		table.insert(p.build, "-Copt-level=0")
		local out = p.build[vim.fn.index(p.build, "-o") + 2]
		return runner.compile(p.build, p.cwd, { title = TITLE }, function()
			launch(codelldb("nide : " .. vim.fs.basename(file), out, p.cwd, args, "rust"))
		end)
	end
	local argv = { "cargo", "build", "--message-format=json-diagnostic-short" }
	vim.list_extend(argv, split_args(project.cargo_target(file, root))) -- --bin / --example
	local artifacts = {}
	runner.compile(argv, root, {
		title = TITLE,
		lines = function(res)
			local lines = vim.split(res.stderr or "", "\n", { trimempty = true })
			artifacts = {}
			for l in vim.gsplit(res.stdout or "", "\n", { trimempty = true }) do
				local ok, msg = pcall(vim.json.decode, l)
				if ok and type(msg) == "table" then
					if msg.reason == "compiler-message" and msg.message and msg.message.rendered then
						vim.list_extend(lines, vim.split(msg.message.rendered, "\n", { trimempty = true }))
					elseif msg.reason == "compiler-artifact" and type(msg.executable) == "string" then
						table.insert(artifacts, { exe = msg.executable, src = msg.target and msg.target.src_path })
					end
				end
			end
			return lines
		end,
	}, function()
		local function go(exe)
			if exe then
				launch(codelldb("nide : " .. vim.fs.basename(exe), exe, root, args, "rust"))
			end
		end
		for _, a in ipairs(artifacts) do
			if a.src == file then
				return go(a.exe)
			end
		end
		if #artifacts == 1 then
			return go(artifacts[1].exe)
		elseif #artifacts == 0 then
			return notify("cargo n'a produit aucun exécutable (bibliothèque ?)", vim.log.levels.WARN)
		end
		vim.ui.select(vim.tbl_map(function(a) return a.exe end, artifacts), {
			prompt = "Exécutable à déboguer",
			format_item = vim.fs.basename,
		}, go)
	end)
end

local function python(file, args, launch)
	local py = project.python(file)
	launch({
		name = "nide : " .. vim.fs.basename(file),
		type = "python",
		request = "launch",
		program = file,
		cwd = vim.fs.dirname(file),
		args = args,
		python = vim.fn.exepath(py) ~= "" and vim.fn.exepath(py) or py,
		console = "integratedTerminal", -- console de dap-ui : input() fonctionne
		justMyCode = true,
	})
end

local function go(file, args, launch)
	local ok, dapgo = pcall(require, "dap-go")
	if not ok then
		return notify("nvim-dap-go indisponible", vim.log.levels.WARN)
	end
	if file:match("_test%.go$") and #args == 0 then
		M.last = nil -- relance : dap-go s'en charge (dap.run_last)
		if dapgo.debug_test() then
			return
		end
	end
	launch({
		name = "nide : go " .. vim.fs.basename(vim.fs.dirname(file)),
		type = "go",
		request = "launch",
		mode = file:match("_test%.go$") and "test" or "debug",
		program = vim.fs.root(file, "go.mod") and vim.fs.dirname(file) or file,
		args = args,
		outputMode = "remote",
	})
end

-- Prépare puis lance le fichier courant ; args : chaîne (nil = aucun)
function M.start(args)
	local dap = require("dap")
	-- depuis une fenêtre de dap-ui (restée ouverte) : revient à une fenêtre de code
	if vim.bo.buftype ~= "" then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local b = vim.api.nvim_win_get_buf(win)
			if vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= "" then
				vim.api.nvim_set_current_win(win)
				break
			end
		end
	end
	local file = vim.api.nvim_buf_get_name(0)
	local ft = vim.bo.filetype
	if file == "" or vim.bo.buftype ~= "" then
		return dap.continue()
	end
	if vim.bo.modified then
		vim.cmd("silent write")
	end
	-- débogueur fourni par un module désactivé (lua/nide/modules.lua) : on explique comment l'activer
	local mod = ({ c = "c", cpp = "c", rust = "rust", python = "python", go = "go" })[ft]
	local adapter = ({ c = "codelldb", cpp = "codelldb", rust = "codelldb", python = "python", go = "go" })[ft]
	local modules = require("nide.modules")
	if mod and not modules.enabled(mod) and not dap.adapters[adapter] then
		local m = modules.by_id[mod]
		local install = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":~") .. "/install.sh"
		return notify(
			modules.chosen(mod)
					and ("Module %s inactif : « %s » introuvable (installe-le puis relance %s)"):format(m.label, m.requires, install)
				or ("Module %s désactivé : relance %s pour l'activer"):format(m.label, install),
			vim.log.levels.WARN
		)
	end
	local argv = split_args(args)
	local function launch(config)
		M.last = { file = file, ft = ft, args = args, name = config.name }
		dap.run(config, { filetype = ft })
	end
	if ft == "c" or ft == "cpp" then
		c_cpp(file, ft, argv, launch)
	elseif ft == "rust" then
		rust(file, argv, launch)
	elseif ft == "python" then
		python(file, argv, launch)
	elseif ft == "go" then
		go(file, argv, launch)
	else
		dap.continue()
	end
end

-- F5 : continuer si une session est en cours, sinon déboguer le fichier courant
function M.continue()
	if require("dap").session() then
		return require("dap").continue()
	end
	M.start()
end

-- Espace d A : déboguer avec des arguments
function M.start_with_args()
	vim.ui.input({ prompt = "Arguments : ", default = M.last_args }, function(input)
		if input == nil then
			return
		end
		M.last_args = input
		M.start(input)
	end)
end

-- Espace d l : relance la dernière session ; si c'est un lancement F5, recompile d'abord
function M.run_last()
	local dap = require("dap")
	if M.last and M.last_name == M.last.name and vim.fn.bufexists(M.last.file) == 1 then
		local last = M.last
		-- session en cours : dap.run la redémarre (même nom de configuration)
		return vim.api.nvim_buf_call(vim.fn.bufnr(last.file), function()
			M.start(last.args)
		end)
	end
	dap.run_last()
end

-- Terminal d'un buffer : job encore en cours ?
local function job_running(buf)
	local id = vim.b[buf].terminal_job_id
	return id and vim.fn.jobwait({ id }, 0)[1] == -1
end

-- Avant une nouvelle session : nvim-dap réutilise la console de dap-ui (terminal terminé).
-- On arrête un programme resté en vie dans la console, et on supprime les autres
-- terminaux [dap-terminal] terminés (fenêtres créées hors dap-ui).
local function clean_terminals()
	if require("dap").session() then
		return -- session en cours (ex. sous-processus) : on ne touche à rien
	end
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[b].buftype == "terminal" and vim.api.nvim_buf_get_name(b):find("[dap-terminal]", 1, true) then
			if job_running(b) then
				local id = vim.b[b].terminal_job_id
				vim.fn.jobstop(id)
				vim.fn.jobwait({ id }, 1000)
			end
			if vim.bo[b].filetype ~= "dapui_console" then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end
	end
end

-- Ferme toute l'interface (q dans dap-ui, sans session)
function M.close_ui()
	if require("dap").session() then
		return notify("Session en cours : Espace d t pour l'arrêter, Espace d u pour masquer l'interface")
	end
	require("dapui").close()
end

local UI_FT = { "dapui_scopes", "dapui_breakpoints", "dapui_stacks", "dapui_watches", "dapui_console", "dap-repl" }

function M.setup()
	local dap = require("dap")
	-- mémorise le nom de la dernière configuration lancée (F5 ou autre)
	dap.listeners.on_config.nide_last = function(config)
		M.last_name = config.name
		clean_terminals()
		return config
	end

	-- fin du programme : dap-ui reste ouvert, on prévient (avec le code de sortie si connu)
	local codes = {} -- session.id → code de sortie
	dap.listeners.after.event_exited.nide = function(session, body)
		codes[session.id] = body and body.exitCode or false
	end
	dap.listeners.after.event_terminated.nide = function(session)
		local code = codes[session.id]
		codes[session.id] = nil
		local msg = code and ("Programme terminé (code " .. code .. ")") or "Programme terminé"
		notify(
			msg .. " — Espace d u (ou q dans le débogueur) pour fermer le débogueur",
			code and code ~= 0 and vim.log.levels.WARN or vim.log.levels.INFO
		)
	end

	-- codelldb (terminal intégré) écrit « Error: Error("EOF while parsing a value"…) » à la
	-- fin du programme : bruit sans intérêt, on l'efface de la console
	vim.api.nvim_create_autocmd("TermClose", {
		group = vim.api.nvim_create_augroup("nide_dap_term", { clear = true }),
		callback = function(ev)
			if not vim.api.nvim_buf_get_name(ev.buf):find("[dap-terminal]", 1, true) then
				return
			end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(ev.buf) then
					return
				end
				local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
				local last = #lines
				while last > 0 and lines[last] == "" do
					last = last - 1
				end
				-- le message peut être coupé sur plusieurs lignes (console étroite)
				for i = last, math.max(1, last - 10), -1 do
					if table.concat(lines, "", i, last):find('^Error: Error%("EOF while parsing') then
						local mod = vim.bo[ev.buf].modifiable
						if pcall(function() vim.bo[ev.buf].modifiable = true end) then
							pcall(vim.api.nvim_buf_set_lines, ev.buf, i - 1, last, false, {})
							vim.bo[ev.buf].modifiable = mod
							vim.bo[ev.buf].modified = false
						end
						break
					end
				end
			end)
		end,
	})

	-- q dans les fenêtres de dap-ui : ferme l'interface quand le programme est fini
	local function map_q(buf)
		vim.keymap.set("n", "q", M.close_ui, { buffer = buf, nowait = true, desc = "Fermer le débogueur" })
	end
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("nide_dapui_q", { clear = true }),
		pattern = UI_FT,
		callback = function(ev) map_q(ev.buf) end,
	})
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.tbl_contains(UI_FT, vim.bo[b].filetype) then
			map_q(b)
		end
	end
end

return M
