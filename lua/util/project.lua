-- Projet du fichier courant : racine, système de build et commande de compilation.
-- On remonte depuis le fichier (ou le dossier courant) et le marqueur LE PLUS PROCHE gagne :
-- un TD avec son Makefile dans un dossier qui a aussi un Makefile → celui du TD.
-- Partagé par util.compile (Espace k), util.runner (F6) et util.debug (F5).
local M = {}

local uv = vim.uv

local function exe(name)
	return vim.fn.executable(name) == 1
end

local function exists(path)
	return uv.fs_stat(path) ~= nil
end

-- Argument shell lisible : pas de guillemets s'ils ne servent à rien
local function arg(s)
	return s:match("^[%w%._%-/+=:@,]+$") and s or vim.fn.shellescape(s)
end
M.arg = arg

-- Chemin relatif à `root` si possible (commandes plus courtes à lire)
local function rel(path, root)
	if path:sub(1, #root + 1) == root .. "/" then
		return path:sub(#root + 2)
	end
	return path
end

-- ---------------------------------------------------------------------------
-- Aides partagées avec F5 / F6
-- ---------------------------------------------------------------------------

M.MAKEFILES = { "GNUmakefile", "makefile", "Makefile" } -- ordre de recherche de make

-- Makefile du projet (en remontant depuis le fichier) ; renvoie son chemin ou nil
function M.makefile(file)
	local dir = vim.fs.root(file, M.MAKEFILES)
	if not dir then
		return nil
	end
	for _, n in ipairs(M.MAKEFILES) do
		if exists(dir .. "/" .. n) then
			return dir .. "/" .. n
		end
	end
end

-- Le Makefile définit-il la cible `name` (ex. run) ? Lecture simple des lignes « cible : »
function M.has_target(makefile, name)
	local ok, lines = pcall(vim.fn.readfile, makefile)
	if not ok then
		return false
	end
	for _, l in ipairs(lines) do
		local targets = l:match("^([^#\t=:][^=:]*):") -- exclut les affectations (:=, =)
		if targets and not l:match("^[^:]*::?=") then
			for t in targets:gmatch("%S+") do
				if t == name then
					return true
				end
			end
		end
	end
	return false
end

-- Dossier du venv Python du projet (.venv, venv, env en remontant, sinon $VIRTUAL_ENV)
function M.venv(file)
	for _, name in ipairs({ ".venv", "venv", "env" }) do
		local dir = vim.fs.root(file, name)
		if dir and exe(dir .. "/" .. name .. "/bin/python") then
			return dir .. "/" .. name
		end
	end
	if vim.env.VIRTUAL_ENV and exe(vim.env.VIRTUAL_ENV .. "/bin/python") then
		return vim.env.VIRTUAL_ENV
	end
end

-- Python : le venv du projet s'il existe, sinon python3
function M.python(file)
	local venv = M.venv(file)
	return venv and venv .. "/bin/python" or "python3"
end

-- Cargo : --bin / --example selon l'emplacement du fichier (F6 et F5)
function M.cargo_target(file, dir)
	local q = vim.fn.shellescape
	local r = file:sub(#dir + 2)
	local bin = r:match("^src/bin/([^/]+)%.rs$") or r:match("^src/bin/([^/]+)/main%.rs$")
	if bin then
		return " --bin " .. q(bin)
	end
	local ex = r:match("^examples/([^/]+)%.rs$") or r:match("^examples/([^/]+)/main%.rs$")
	if ex then
		return " --example " .. q(ex)
	end
	return ""
end

-- Dossier de build temporaire (supprimé quand Neovim se ferme)
function M.build_dir()
	local dir = vim.fs.dirname(vim.fn.tempname()) .. "/nide-run"
	vim.fn.mkdir(dir, "p")
	return dir
end

-- Outil : celui du venv (chemin relatif), sinon PATH, sinon installé par Mason
local function tool(name, root, venv)
	if venv and exe(venv .. "/bin/" .. name) then
		return arg(rel(venv .. "/bin/" .. name, root))
	end
	if exe(name) or exe(vim.fn.stdpath("data") .. "/mason/bin/" .. name) then
		return name
	end
end
M.tool = tool

-- ---------------------------------------------------------------------------
-- Détection
-- ---------------------------------------------------------------------------

-- Marqueurs, par priorité dans un même dossier (le dossier le plus proche passe avant tout)
local MARKERS = {
	{ kind = "make", files = M.MAKEFILES },
	{ kind = "just", files = { "justfile", "Justfile", ".justfile" } },
	{ kind = "cmake", files = { "CMakeLists.txt" } },
	{ kind = "meson", files = { "meson.build" } },
	{ kind = "cargo", files = { "Cargo.toml" } },
	{ kind = "go", files = { "go.mod" } },
	{ kind = "npm", files = { "package.json" } },
	{ kind = "python", files = { "pyproject.toml", "setup.py", "setup.cfg" } },
}
-- LaTeX : seuls make / just / latexmkrc priment sur latexmk
local TEX_MARKERS = {
	MARKERS[1],
	MARKERS[2],
	{ kind = "latex", files = { "latexmkrc", ".latexmkrc" } },
}

local function first(dir, names)
	for _, n in ipairs(names) do
		if exists(dir .. "/" .. n) then
			return n
		end
	end
end

local function read(path, max)
	local ok, lines
	if max then
		ok, lines = pcall(vim.fn.readfile, path, "", max)
	else
		ok, lines = pcall(vim.fn.readfile, path)
	end
	return ok and lines or {}
end

local function contains(path, pat, max)
	for _, l in ipairs(read(path, max)) do
		if l:find(pat) then
			return true
		end
	end
	return false
end

-- CMake / Meson : les sous-dossiers ont aussi leur CMakeLists.txt → on remonte jusqu'au
-- plus haut fichier contigu qui déclare project(…)
local function top_level(dir, name, pat)
	local best = contains(dir .. "/" .. name, pat) and dir or nil
	local d = dir
	while true do
		local parent = vim.fs.dirname(d)
		if parent == d or not exists(parent .. "/" .. name) then
			break
		end
		d = parent
		if contains(d .. "/" .. name, pat) then
			best = d
		end
	end
	return best or dir
end

-- Premier dossier (en remontant) qui contient un marqueur ; s'arrête à la racine git et à $HOME
local function walk(start, markers)
	local home = vim.fs.normalize("~")
	local dir = start
	while dir do
		if dir ~= home or start == home then
			for _, m in ipairs(markers) do
				local name = first(dir, m.files)
				if name then
					return dir, m.kind, name
				end
			end
		end
		local parent = vim.fs.dirname(dir)
		if parent == dir or dir == home or exists(dir .. "/.git") then
			break
		end
		dir = parent
	end
end

-- Fichier LaTeX principal : celui qui a \documentclass (fichier courant, % !TEX root,
-- vimtex, sinon un .tex du dossier ou du parent — main.tex de préférence)
function M.tex_main(file)
	if contains(file, "^%s*\\documentclass") then
		return file
	end
	for _, l in ipairs(read(file, 5)) do
		local r = l:match("^%%%s*!%s*[Tt][Ee][Xx]%s+root%s*=%s*(.-)%s*$")
		if r then
			local p = vim.fs.normalize(vim.fs.dirname(file) .. "/" .. r)
			if exists(p) then
				return p
			end
		end
	end
	local buf = vim.fn.bufnr(file)
	local vt = buf > 0 and vim.b[buf].vimtex
	if type(vt) == "table" and type(vt.tex) == "string" and exists(vt.tex) then
		return vt.tex
	end
	local dir = vim.fs.dirname(file)
	for _ = 1, 2 do
		local cands = {}
		for name, kind in vim.fs.dir(dir) do
			if kind == "file" and name:match("%.tex$") and contains(dir .. "/" .. name, "^%s*\\documentclass", 200) then
				table.insert(cands, name)
			end
		end
		table.sort(cands)
		if vim.tbl_contains(cands, "main.tex") then
			return dir .. "/main.tex"
		elseif cands[1] then
			return dir .. "/" .. cands[1]
		end
		dir = vim.fs.dirname(dir)
	end
	return file
end

-- Gestionnaire de paquets JS d'après le fichier de verrouillage
local function js_pm(root)
	for _, c in ipairs({
		{ "pnpm-lock.yaml", "pnpm" },
		{ "yarn.lock", "yarn" },
		{ "bun.lockb", "bun" },
		{ "bun.lock", "bun" },
		{ "package-lock.json", "npm" },
	}) do
		if exists(root .. "/" .. c[1]) then
			return c[2]
		end
	end
	return "npm"
end

local function json(path)
	local ok, data = pcall(vim.json.decode, table.concat(read(path), "\n"))
	return ok and type(data) == "table" and data or {}
end

-- Commandes de vérification Python : ruff + pyright (ou basedpyright) si présents
local function python_cmd(root, target, file)
	local venv = M.venv(file or (root .. "/x"))
	local parts, names = {}, {}
	local ruff = tool("ruff", root, venv)
	if ruff then
		table.insert(parts, ruff .. " check --output-format=concise " .. target)
		table.insert(names, "ruff")
	end
	local pyright = tool("pyright", root, venv) or tool("basedpyright", root, venv)
	if pyright then
		local py = venv and (" --pythonpath " .. arg(rel(venv .. "/bin/python", root))) or ""
		table.insert(parts, pyright .. py .. (target ~= "." and " " .. target or ""))
		table.insert(names, pyright:match("[^/]+$"))
	end
	if #parts == 0 then
		local py = venv and arg(rel(venv .. "/bin/python", root)) or "python3"
		return py .. (target == "." and " -m compileall -q ." or " -m py_compile " .. target), "compileall"
	end
	return table.concat(parts, " ; "), table.concat(names, " + ")
end

-- Projet « fichier seul » (pas de système de build) : commande selon le type de fichier
local function single(file, ft)
	local dir, name = vim.fs.dirname(file), vim.fs.basename(file)
	local base = vim.fn.fnamemodify(file, ":t:r")
	local p = { root = dir, kind = "file", file = file }
	if ft == "c" or ft == "cpp" then
		local cc = ft == "c" and "gcc" or "g++"
		p.cmd = ("%s -Wall -Wextra -g %s -o %s%s"):format(cc, arg(name), arg(M.build_dir() .. "/" .. base), ft == "c" and " -lm" or "")
		p.label = "fichier seul (" .. cc .. ")"
	elseif ft == "rust" then
		p.cmd = ("rustc -g %s -o %s"):format(arg(name), arg(M.build_dir() .. "/" .. base))
		p.label = "fichier seul (rustc)"
	elseif ft == "python" then
		local label
		p.cmd, label = python_cmd(dir, arg(name), file)
		p.kind, p.label = "python", "Python (" .. label .. ")"
	elseif ft == "go" then
		p.cmd, p.label = "go build -o /dev/null " .. arg(name), "fichier seul (go)"
	elseif ft == "sh" or ft == "bash" then
		if tool("shellcheck") then
			p.cmd, p.label = "shellcheck -f gcc " .. arg(name), "fichier seul (shellcheck)"
		end
	elseif ft == "typescript" or ft == "javascript" then
		if tool("tsc") then
			p.cmd, p.label = "tsc --noEmit " .. arg(name), "fichier seul (tsc)"
		end
	end
	if not p.cmd then
		p.kind, p.label = "none", "aucun système de build"
	end
	return p
end

-- Point d'entrée. path : fichier ou dossier (défaut : buffer courant, ou cwd pour un buffer
-- spécial). Renvoie { root, kind, cmd, label, file?, main?, targets() }. cmd peut être nil.
function M.detect(path, ft)
	if not path then
		local buf = vim.api.nvim_get_current_buf()
		local name = vim.api.nvim_buf_get_name(buf)
		if vim.bo[buf].buftype == "" and name ~= "" then
			path, ft = name, ft or vim.bo[buf].filetype
		else
			path = uv.cwd()
		end
	end
	path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("(.)/$", "%1")
	local isdir = vim.fn.isdirectory(path) == 1
	local file = not isdir and path or nil
	if file and not ft then
		ft = vim.filetype.match({ filename = file }) or ""
	end
	local start = isdir and path or vim.fs.dirname(path)
	local is_tex = ft == "tex" or ft == "plaintex" or (file and file:match("%.tex$"))

	local root, kind, marker = walk(start, is_tex and TEX_MARKERS or MARKERS)
	local p
	if is_tex and (not root or kind == "latex") then
		local main = M.tex_main(file)
		local dir = vim.fs.dirname(main)
		local rc = root and kind == "latex"
		p = {
			root = dir,
			kind = "latex",
			main = main,
			cmd = ("latexmk%s -interaction=nonstopmode -file-line-error -synctex=1 %s"):format(rc and "" or " -pdf", arg(rel(main, dir))),
			label = "LaTeX (" .. vim.fs.basename(main) .. ")",
		}
	elseif not root then
		p = file and single(file, ft) or { root = start, kind = "none", label = "aucun système de build" }
	elseif kind == "make" then
		p = { root = root, kind = kind, cmd = "make -k", label = marker }
	elseif kind == "just" then
		p = { root = root, kind = kind, cmd = "just", label = "just" }
	elseif kind == "cmake" then
		root = top_level(root, "CMakeLists.txt", "[Pp][Rr][Oo][Jj][Ee][Cc][Tt]%s*%(")
		p = {
			root = root,
			kind = kind,
			cmd = "cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_COLOR_DIAGNOSTICS=ON && cmake --build build",
			label = "CMake",
		}
	elseif kind == "meson" then
		root = top_level(root, "meson.build", "^%s*project%s*%(")
		p = {
			root = root,
			kind = kind,
			cmd = "(test -f build/build.ninja || meson setup build) && meson compile -C build",
			label = "Meson",
		}
	elseif kind == "cargo" then
		p = { root = root, kind = kind, cmd = "cargo build", label = "Cargo" }
	elseif kind == "go" then
		p = { root = root, kind = kind, cmd = "go build ./...", label = "Go" }
	elseif kind == "npm" then
		local pm = js_pm(root)
		local scripts = json(root .. "/package.json").scripts or {}
		local cmd
		if scripts.build then
			cmd = pm .. " run build"
		elseif exists(root .. "/tsconfig.json") then
			cmd = ({ npm = "npx", pnpm = "pnpm exec", yarn = "yarn", bun = "bunx" })[pm] .. " tsc --noEmit"
		else
			cmd = pm .. " run" -- liste les scripts
		end
		p = { root = root, kind = kind, cmd = cmd, label = "package.json (" .. pm .. ")", pm = pm }
	elseif kind == "python" then
		local cmd, label = python_cmd(root, ".", file)
		p = { root = root, kind = kind, cmd = cmd, label = "Python (" .. label .. ")" }
	end
	p.file = p.file or file
	p.targets = function()
		return M.targets(p)
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Cibles (Espace k t)
-- ---------------------------------------------------------------------------

local function sys(argv, cwd)
	local ok, res = pcall(function()
		return vim.system(argv, { cwd = cwd, text = true, env = { LC_ALL = "C" } }):wait(5000)
	end)
	return ok and res and res.stdout or ""
end

-- Cibles d'un Makefile, d'après la base de données de make (make -pRrq) : cible par défaut,
-- puis les .PHONY, puis les autres ; sans fichiers intermédiaires (.o, .d) ni règles à motif.
function M.make_targets(root)
	local out = sys({ "make", "-pRrq", "-C", root }, root)
	local default, phony, seen, list = nil, {}, {}, {}
	local in_files, skip = false, false
	for l in vim.gsplit(out, "\n", { plain = true }) do
		if l == "# Files" then
			in_files = true
		elseif l:match("^# Finished Make data base") or l:match("^# VPATH Search Paths") then
			in_files = false
		end
		default = default or l:match("^%.DEFAULT_GOAL :?= (%S+)")
		local ph = l:match("^%.PHONY:(.*)$")
		if ph then
			for t in ph:gmatch("%S+") do
				phony[t] = phony[t] or (vim.tbl_count(phony) + 1)
			end
		end
		if l == "# Not a target:" then
			skip = true
		elseif in_files and not l:match("^[#%s]") and l ~= "" then
			local t = l:match("^([^:=%s][^:=]*):") -- « cible: … » mais pas « VAR := … »
			if t and not l:match("^[^:]*::?=") and not skip then
				t = vim.trim(t)
				if not t:find("[%%%s]") and not t:match("^%.") and not vim.tbl_contains(M.MAKEFILES, t)
					and not t:match("%.[odhc]$") and not t:match("%.[ch]pp$") and not t:match("%.mk$") and not seen[t] then
					seen[t] = true
					table.insert(list, t)
				end
			end
			skip = false
		end
	end
	local function rank(t)
		return t == default and 0 or phony[t] and 1 or 2
	end
	local order = {}
	for i, t in ipairs(list) do
		order[t] = i
	end
	table.sort(list, function(a, b)
		if rank(a) ~= rank(b) then
			return rank(a) < rank(b)
		elseif rank(a) == 1 then
			return phony[a] < phony[b] -- ordre de la déclaration .PHONY
		end
		return order[a] < order[b]
	end)
	return list
end

function M.targets(p)
	local t = {}
	local function add(cmd, desc)
		table.insert(t, { cmd = cmd, desc = desc })
	end
	if p.kind == "make" then
		for _, name in ipairs(M.make_targets(p.root)) do
			add("make -k " .. arg(name))
		end
	elseif p.kind == "just" then
		for r in sys({ "just", "--summary", "--unsorted" }, p.root):gmatch("%S+") do
			add("just " .. r)
		end
	elseif p.kind == "npm" then
		local scripts = json(p.root .. "/package.json").scripts or {}
		local names = vim.tbl_keys(scripts)
		table.sort(names)
		for _, name in ipairs(names) do
			add(p.pm .. " run " .. arg(name), scripts[name])
		end
		add(p.pm .. " install")
	elseif p.kind == "cargo" then
		add("cargo build")
		add("cargo build --release")
		add("cargo check")
		add("cargo clippy")
		add("cargo test")
		local ok, meta = pcall(vim.json.decode, sys({ "cargo", "metadata", "--no-deps", "--format-version", "1" }, p.root))
		meta = ok and type(meta) == "table" and meta or {}
		for _, pkg in ipairs(meta.packages or {}) do
			for _, tg in ipairs(pkg.targets or {}) do
				local k = tg.kind and tg.kind[1]
				if k == "bin" then
					add("cargo build --bin " .. arg(tg.name))
					add("cargo run --bin " .. arg(tg.name))
				elseif k == "example" then
					add("cargo run --example " .. arg(tg.name))
				end
			end
		end
	elseif p.kind == "cmake" then
		add(p.cmd)
		add("cmake --build build --target clean")
		add("ctest --test-dir build --output-on-failure")
		for l in sys({ "cmake", "--build", "build", "--target", "help" }, p.root):gmatch("[^\n]+") do
			local name = l:match("^%.%.%. (%S+)") or l:match("^([%w_%-%.]+): %a")
			if name and name ~= "all" and name ~= "clean" then
				add("cmake --build build --target " .. arg(name))
			end
		end
	elseif p.kind == "meson" then
		add(p.cmd)
		add("meson test -C build")
	elseif p.kind == "go" then
		add("go build ./...")
		add("go vet ./...")
		add("go test ./...")
		add("go run .")
	elseif p.kind == "python" then
		add(p.cmd)
		local venv = M.venv(p.file or (p.root .. "/x"))
		local pytest = tool("pytest", p.root, venv)
		if pytest then
			add(pytest)
		end
		local ruff = tool("ruff", p.root, venv)
		if ruff then
			add(ruff .. " format --check .")
		end
	elseif p.kind == "latex" then
		add(p.cmd)
		add("latexmk -c", "nettoyer les fichiers auxiliaires")
		add("latexmk -C", "nettoyer tout, PDF compris")
	elseif p.cmd then
		add(p.cmd)
	end
	return t
end

return M
