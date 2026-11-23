-- Modèles de nide : assistant « nouveau projet » (:NideNew) et squelettes de nouveaux fichiers.
-- Les fichiers modèles sont dans templates/ (à côté de init.lua). Variables : {{NAME}}, {{GUARD}}…
-- {{CURSOR}} marque la position du curseur (supprimé à l'insertion).
local M = {}

M.dir = vim.fn.stdpath("config") .. "/templates"

local function exe(name)
	return vim.fn.executable(name) == 1
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "Nouveau projet" })
end

local function read(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	return ok and lines or nil
end

-- remplace les {{VARIABLES}} ; les inconnues restent telles quelles
local function fill(lines, vars)
	return vim.tbl_map(function(l)
		return (l:gsub("{{(%u+)}}", function(k)
			return k ~= "CURSOR" and vars[k] or nil
		end))
	end, lines)
end

-- retire {{CURSOR}} ; renvoie les lignes et la position (1-indexée, colonne 0-indexée) ou nil
local function take_cursor(lines)
	for i, l in ipairs(lines) do
		local s = l:find("{{CURSOR}}", 1, true)
		if s then
			lines[i] = l:sub(1, s - 1) .. l:sub(s + #"{{CURSOR}}")
			return lines, { i, s - 1 }
		end
	end
	return lines, nil
end

-- lance une commande et attend ; renvoie ok, sortie
local function run(cmd, cwd)
	local ok, res = pcall(function()
		return vim.system(cmd, { cwd = cwd, text = true }):wait(120000)
	end)
	if not ok then
		return false, tostring(res)
	end
	return res.code == 0, vim.trim((res.stderr or "") .. "\n" .. (res.stdout or ""))
end

-- copie récursive de templates/<kind> vers dest, avec substitution des variables
local function copy_tree(kind, dest, vars)
	local src = M.dir .. "/" .. kind
	if not vim.uv.fs_stat(src) then
		error("modèle introuvable : " .. src)
	end
	for name, t in vim.fs.dir(src, { depth = 10 }) do
		local from, to = src .. "/" .. name, dest .. "/" .. name
		if t == "directory" then
			vim.fn.mkdir(to, "p")
		elseif name:match("%.gitkeep$") then
			vim.fn.mkdir(vim.fs.dirname(to), "p")
		else
			vim.fn.mkdir(vim.fs.dirname(to), "p")
			local lines = take_cursor(fill(read(from) or {}, vars))
			vim.fn.writefile(lines, to)
		end
	end
end

local function git_author()
	if exe("git") then
		local ok, out = run({ "git", "config", "user.name" })
		if ok and out ~= "" then
			return out
		end
	end
	return vim.env.USER or "Auteur"
end

local function latex_escape(s)
	return (s:gsub("[\\{}&%%%$#_%^~]", function(c)
		local map = { ["\\"] = "\\textbackslash{}", ["^"] = "\\^{}", ["~"] = "\\~{}" }
		return map[c] or ("\\" .. c)
	end))
end

-- dossier déjà dans un dépôt git ?
local function in_git(dir)
	return exe("git") and (run({ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" }))
end

-- git init (sauf si déjà dans un dépôt) ; .gitignore déjà écrit par le modèle
local function git_init(dir, warnings)
	if not exe("git") then
		table.insert(warnings, "git introuvable : dépôt non initialisé")
		return
	end
	if in_git(dir) then
		return
	end
	local ok, out = run({ "git", "init", "-q" }, dir)
	if not ok then
		table.insert(warnings, "git init a échoué : " .. out)
	end
end

-- crée .venv (uv, sinon python3 -m venv) ; renvoie le chemin du python ou nil
local function make_venv(dir, warnings)
	local ok, out
	if exe("uv") then
		ok, out = run({ "uv", "venv", "-q", ".venv" }, dir)
	elseif exe("python3") then
		ok, out = run({ "python3", "-m", "venv", ".venv" }, dir)
	else
		table.insert(warnings, "ni uv ni python3 : pas de .venv")
		return nil
	end
	if not ok then
		table.insert(warnings, "création du .venv impossible : " .. out)
		return nil
	end
	return dir .. "/.venv/bin/python"
end

-- installe des paquets dans le .venv, en arrière-plan
local function pip_install(dir, py, pkgs, done)
	local cmd = exe("uv") and vim.list_extend({ "uv", "pip", "install", "-q", "--python", py }, pkgs)
		or vim.list_extend({ py, "-m", "pip", "install", "-q" }, pkgs)
	notify("Installation dans .venv : " .. table.concat(pkgs, ", ") .. "…")
	vim.system(cmd, { cwd = dir, text = true }, vim.schedule_wrap(function(res)
		if res.code == 0 then
			notify(".venv prêt (" .. table.concat(pkgs, ", ") .. ")")
		else
			notify("Installation échouée (réseau ?) :\n" .. vim.trim(res.stderr or "")
				.. "\nÀ refaire : uv pip install --python .venv/bin/python " .. table.concat(pkgs, " "), vim.log.levels.WARN)
		end
		if done then
			done(res.code == 0)
		end
	end))
end

-- ---------------------------------------------------------------------------
-- Types de projets : create(dir, name, vars, warnings) → fichier principal (relatif à dir)
-- ---------------------------------------------------------------------------
M.kinds = {
	{
		id = "c",
		label = "C (Makefile, src/, include/)",
		create = function(dir, _, vars, w)
			copy_tree("c", dir, vars)
			git_init(dir, w)
			if not exe("gcc") then
				table.insert(w, "gcc introuvable : make ne pourra pas compiler")
			end
			return "src/main.c"
		end,
	},
	{
		id = "cpp",
		label = "C++ (Makefile, src/, include/)",
		create = function(dir, _, vars, w)
			copy_tree("cpp", dir, vars)
			git_init(dir, w)
			if not exe("g++") then
				table.insert(w, "g++ introuvable : make ne pourra pas compiler")
			end
			return "src/main.cpp"
		end,
	},
	{
		id = "python",
		label = "Python (uv, .venv)",
		create = function(dir, name, vars, w)
			local done = false
			if exe("uv") then
				-- uv init : pyproject.toml, main.py, README.md, .python-version, .gitignore et git init
				local ok, out = run({ "uv", "init", "-q", "--app", "--no-package", "--name", name, "--vcs", exe("git") and "git" or "none", "." }, dir)
				if ok then
					done = true
					if not vim.uv.fs_stat(dir .. "/main.py") then
						vim.fn.writefile(fill(read(M.dir .. "/python/main.py"), vars), dir .. "/main.py")
					end
				else
					table.insert(w, "uv init a échoué, structure créée à la main : " .. out)
				end
			else
				table.insert(w, "uv introuvable : structure créée à la main (python3 -m venv)")
			end
			if not done then
				local _, v = run({ "python3", "-c", "import sys; print('%d.%d' % sys.version_info[:2])" })
				vars.PYVER = v:match("^%d+%.%d+") or "3.10"
				copy_tree("python", dir, vars)
				git_init(dir, w)
			end
			make_venv(dir, w)
			return "main.py"
		end,
	},
	{
		id = "rust",
		label = "Rust (cargo)",
		create = function(dir, name, vars, w)
			if exe("cargo") then
				local vcs = (exe("git") and not in_git(vim.fs.dirname(dir))) and "git" or "none"
				local ok, out = run({ "cargo", "init", "-q", "--vcs", vcs, "--name", (name:gsub("[^%w_]", "_")) }, dir)
				if ok then
					return "src/main.rs"
				end
				table.insert(w, "cargo init a échoué : " .. out)
			else
				table.insert(w, "cargo introuvable (installe rustup) : structure créée à la main")
			end
			vim.fn.mkdir(dir .. "/src", "p")
			vim.fn.writefile({
				"[package]", ('name = "%s"'):format(name:gsub("[^%w_]", "_")), 'version = "0.1.0"', 'edition = "2021"', "", "[dependencies]",
			}, dir .. "/Cargo.toml")
			vim.fn.writefile({ "fn main() {", '    println!("Hello, world!");', "}" }, dir .. "/src/main.rs")
			vim.fn.writefile({ "/target" }, dir .. "/.gitignore")
			git_init(dir, w)
			return "src/main.rs"
		end,
	},
	{
		id = "latex",
		label = "LaTeX (rapport)",
		create = function(dir, name, vars, w)
			vars.TITLE = latex_escape(name:gsub("[_-]", " "))
			vars.AUTHOR = latex_escape(git_author())
			copy_tree("latex", dir, vars)
			git_init(dir, w)
			if not exe("latexmk") and not exe("tectonic") then
				table.insert(w, "latexmk introuvable : installe TeX Live (texlive-meta) pour compiler")
			end
			return "main.tex"
		end,
	},
	{
		id = "notebook",
		label = "Notebook Jupyter (.venv + ipykernel)",
		create = function(dir, _, vars, w)
			copy_tree("notebook", dir, vars)
			git_init(dir, w)
			local py = make_venv(dir, w)
			if py then
				-- le kernel du .venv est utilisé par util.notebook s'il a ipykernel
				pip_install(dir, py, { "ipykernel", "numpy", "matplotlib" })
			end
			return "notebook.ipynb", function()
				require("util.notebook").new("notebook.ipynb")
			end
		end,
	},
}

local function kind_by_id(id)
	for _, k in ipairs(M.kinds) do
		if k.id == id then
			return k
		end
	end
end

-- nom valide pour un dossier, un binaire, un paquet
local function valid_name(name)
	return name and name:match("^[%w][%w._-]*$") ~= nil
end

-- Crée le projet ; renvoie le dossier ou nil, erreur. opts.open = false : ni cd ni ouverture.
function M.create(id, name, parent, opts)
	opts = opts or {}
	local kind = kind_by_id(id)
	if not kind then
		return nil, "type inconnu : " .. tostring(id)
	end
	if not valid_name(name) then
		return nil, "nom invalide (lettres, chiffres, . _ - ; pas d'espace) : " .. tostring(name)
	end
	parent = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(parent ~= "" and parent or vim.uv.cwd()), ":p"))
	parent = parent:gsub("/$", "")
	local dir = parent .. "/" .. name
	if vim.uv.fs_stat(dir) and next(vim.fn.readdir(dir)) then
		return nil, "le dossier existe déjà et n'est pas vide : " .. dir
	end
	if vim.fn.mkdir(dir, "p") == 0 and not vim.uv.fs_stat(dir) then
		return nil, "impossible de créer " .. dir
	end
	local warnings, vars = {}, { NAME = name }
	local ok, main, opener = pcall(kind.create, dir, name, vars, warnings)
	if not ok then
		return nil, tostring(main)
	end
	if opts.open ~= false then
		vim.cmd.cd(vim.fn.fnameescape(dir))
		if opener then
			opener()
		else
			vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. main))
		end
	end
	local msg = ("Projet %s créé : %s"):format(kind.label:match("^[^(]+"):gsub("%s+$", ""), dir)
	if #warnings > 0 then
		notify(msg .. "\n• " .. table.concat(warnings, "\n• "), vim.log.levels.WARN)
	else
		notify(msg)
	end
	return dir, main, warnings
end

-- Assistant interactif : type → nom → dossier parent
function M.wizard()
	vim.ui.select(M.kinds, {
		prompt = "Nouveau projet",
		format_item = function(k)
			return k.label
		end,
	}, function(kind)
		if not kind then
			return
		end
		vim.ui.input({ prompt = "Nom du projet : " }, function(name)
			if not name or vim.trim(name) == "" then
				return
			end
			name = vim.trim(name)
			if not valid_name(name) then
				return notify("Nom invalide : lettres, chiffres, . _ - (sans espace)", vim.log.levels.WARN)
			end
			vim.ui.input({ prompt = "Dans le dossier : ", default = vim.fn.fnamemodify(vim.uv.cwd(), ":~"), completion = "dir" }, function(parent)
				if not parent then
					return
				end
				local dir, err = M.create(kind.id, name, vim.trim(parent))
				if not dir then
					notify(err, vim.log.levels.ERROR)
				end
			end)
		end)
	end)
end

-- :NideNew [type nom [dossier]]
function M.command(o)
	local a = o.fargs
	if #a == 0 then
		return M.wizard()
	end
	if #a < 2 then
		return notify("Usage : NideNew [type nom [dossier]]", vim.log.levels.WARN)
	end
	local dir, err = M.create(a[1], a[2], a[3] or "")
	if not dir then
		notify(err, vim.log.levels.ERROR)
	end
end

function M.complete(arg, line)
	if #vim.split(line, "%s+") <= 2 then
		return vim.tbl_filter(function(id)
			return vim.startswith(id, arg)
		end, vim.tbl_map(function(k) return k.id end, M.kinds))
	end
	return {}
end

-- ---------------------------------------------------------------------------
-- Squelettes de fichiers
-- ---------------------------------------------------------------------------
local function guard(name)
	return (name:upper():gsub("[^%w]", "_"))
end

-- choisit le squelette pour un chemin ; renvoie nom du modèle, variables (ou nil)
function M.skeleton_for(path)
	local tail = vim.fs.basename(path)
	local stem, ext = tail:match("^(.*)%.([^.]+)$")
	ext = ext and ext:lower()
	if tail == "Makefile" or tail == "makefile" or tail == "GNUmakefile" then
		local dir = vim.fs.basename(vim.fs.dirname(vim.fn.fnamemodify(path, ":p")))
		return "Makefile", { NAME = (dir ~= "" and dir:gsub("[^%w._-]", "_")) or "prog" }
	end
	if ext == "c" or ext == "cpp" or ext == "cc" or ext == "cxx" then
		local cpp = ext ~= "c"
		if stem == "main" then
			return cpp and "main.cpp" or "main.c", {}
		end
		-- en-tête correspondant : à côté, ou dans ../include
		local dir = vim.fs.dirname(vim.fn.fnamemodify(path, ":p"))
		for _, h in ipairs(cpp and { ".hpp", ".hh", ".h" } or { ".h" }) do
			for _, d in ipairs({ dir, dir .. "/../include", dir .. "/include" }) do
				if vim.uv.fs_stat(d .. "/" .. stem .. h) then
					return cpp and "source.cpp" or "source.c", { HEADER = stem .. h }
				end
			end
		end
		return nil
	end
	if ext == "h" or ext == "hpp" or ext == "hh" or ext == "hxx" then
		return ext == "h" and "header.h" or "header.hpp", { GUARD = guard(tail) }
	end
	if ext == "py" then
		return "script.py", {}
	end
	if ext == "sh" or ext == "bash" then
		return "script.sh", {}
	end
end

local function buf_empty(buf)
	local l = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return #l == 0 or (#l == 1 and l[1] == "")
end

-- .sh : rendu exécutable à la première sauvegarde
local function chmod_on_save(buf)
	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = buf,
		once = true,
		callback = function(a)
			local f = vim.api.nvim_buf_get_name(a.buf)
			local perm = vim.fn.getfperm(f)
			if perm ~= "" and perm:sub(3, 3) ~= "x" then
				local p = vim.split(perm, "")
				for _, i in ipairs({ 3, 6, 9 }) do
					if p[i - 2] == "r" then
						p[i] = "x"
					end
				end
				vim.fn.setfperm(f, table.concat(p))
			end
		end,
	})
end

-- insère le squelette dans le buffer (vide) ; renvoie true si inséré
function M.skeleton(buf, opts)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	opts = opts or {}
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" or vim.bo[buf].buftype ~= "" then
		return false, "pas de fichier"
	end
	if not buf_empty(buf) then
		return false, "le fichier n'est pas vide"
	end
	local name, vars = M.skeleton_for(path)
	if not name then
		return false, "pas de squelette pour ce fichier"
	end
	local lines = read(M.dir .. "/skeletons/" .. name)
	if not lines then
		return false, "modèle introuvable : " .. name
	end
	local cursor
	lines, cursor = take_cursor(fill(lines, vars))
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if name == "script.sh" then
		chmod_on_save(buf)
	end
	if cursor then
		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			pcall(vim.api.nvim_win_set_cursor, win, cursor)
		end
	end
	return true
end

-- :NideSkeleton
function M.skeleton_command()
	local ok, why = M.skeleton(0)
	if not ok then
		vim.notify("Squelette : " .. why, vim.log.levels.WARN)
	end
end

-- BufNewFile : nouveau fichier qui n'existe pas encore sur le disque
function M.on_new_file(a)
	if vim.g.nide_skeletons == false then
		return
	end
	M.skeleton(a.buf)
end

return M
