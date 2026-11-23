-- « Lancer le fichier courant » façon IDE (F6 / Espace r).
-- Le programme tourne dans un terminal Snacks en bas, toujours le même (l'ancien est remplacé).
-- Langages compilés (C, C++, Rust sans Cargo) : compilation en arrière-plan d'abord ;
-- en cas d'erreur, la liste quickfix est remplie et le panneau Problèmes (Trouble) s'ouvre.
local M = {}

M.last_args = "" -- derniers arguments saisis avec Espace R

-- Aides partagées (détection de projet) : util.project
local project = require("util.project")
M.build_dir = project.build_dir
M.python = project.python
M.cargo_target = project.cargo_target
M.makefile = project.makefile
M.has_target = project.has_target

local function exe(name)
	return vim.fn.executable(name) == 1
end

local q = vim.fn.shellescape

-- Erreurs de gcc/g++/clang et de rustc/cargo (--error-format=short)
M.errorformat = table.concat({
	"%f:%l:%c: fatal %trror: %m",
	"%f:%l:%c: %trror: %m",
	"%f:%l:%c: %tarning: %m",
	"%f:%l:%c: %trror%m", -- rust : error[E0425]: …
	"%f:%l:%c: %tarning%m",
	"%f:%l:%c: %tote: %m",
	"%f:%l: %trror: %m",
	"%-G%.%#",
}, ",")

-- Remonte depuis le fichier jusqu'au premier dossier contenant un de ces noms
local function root(file, markers)
	return vim.fs.root(file, markers)
end

-- TypeScript : tsx du projet, puis tsx global, sinon node (≥ 22.18 exécute le TS directement)
local function ts_runner(file)
	local dir = root(file, "node_modules")
	if dir and exe(dir .. "/node_modules/.bin/tsx") then
		return q(dir .. "/node_modules/.bin/tsx")
	end
	return exe("tsx") and "tsx" or "node"
end

-- Construit le plan d'exécution pour un fichier.
-- Renvoie { cwd, run = "commande shell", build = { argv } (optionnel), label } ou nil, message
function M.plan(file, ft, args)
	args = (args and args ~= "") and (" " .. args) or ""
	local dir = vim.fs.dirname(file)
	local name = vim.fn.fnamemodify(file, ":t:r")
	local f = q(file)

	if ft == "python" then
		return { cwd = dir, run = q(M.python(file)) .. " " .. f .. args }
	elseif (ft == "c" or ft == "cpp") and M.makefile(file) and M.has_target(M.makefile(file), "run") then
		-- Projet avec Makefile et cible run (ex. :NideNew c) : make, puis make run ARGS="…"
		local mdir = vim.fs.dirname(M.makefile(file))
		local margs = vim.trim(args)
		return { cwd = mdir, build = { "make" }, run = "make run" .. (margs ~= "" and " ARGS=" .. q(margs) or "") }
	elseif ft == "c" or ft == "cpp" then
		local cc = ft == "c" and "gcc" or "g++"
		if not exe(cc) then
			return nil, cc .. " introuvable"
		end
		local out = M.build_dir() .. "/" .. name
		local build = { cc, "-Wall", "-Wextra", "-g", "-fdiagnostics-color=never", file, "-o", out }
		if ft == "c" then
			table.insert(build, "-lm")
		end
		return { cwd = dir, build = build, run = q(out) .. args }
	elseif ft == "rust" then
		local cargo = root(file, "Cargo.toml")
		if cargo then
			-- Projet cargo : on lance le projet (ou le binaire / l'exemple courant)
			return { cwd = cargo, run = "cargo run" .. M.cargo_target(file, cargo) .. (args ~= "" and " --" .. args or "") }
		end
		local out = M.build_dir() .. "/" .. name
		return { cwd = dir, build = { "rustc", "--error-format=short", "-g", file, "-o", out }, run = q(out) .. args }
	elseif ft == "lua" then
		return { cwd = dir, run = q(vim.v.progpath) .. " -l " .. f .. args }
	elseif ft == "javascript" then
		return { cwd = dir, run = "node " .. f .. args }
	elseif ft == "typescript" then
		return { cwd = dir, run = ts_runner(file) .. " " .. f .. args }
	elseif ft == "sh" or ft == "bash" or ft == "zsh" or ft == "fish" then
		local sh = ft == "sh" and (vim.b.is_bash and "bash" or "sh") or ft
		return { cwd = dir, run = sh .. " " .. f .. args }
	elseif ft == "go" then
		local mod = root(file, "go.mod")
		-- Avec go.mod : tout le paquet du dossier (plusieurs fichiers) ; sinon le fichier seul
		return { cwd = dir, run = (mod and "go run ." or "go run " .. f) .. args }
	end
	return nil, "Pas de lanceur pour le type « " .. (ft ~= "" and ft or "?") .. " »"
end

-- Terminal d'exécution : un seul, remplacé à chaque lancement
local term

function M.exec(cmd, cwd)
	if term and term:buf_valid() then
		pcall(vim.api.nvim_buf_delete, term.buf, { force = true })
	end
	-- sh -c : indépendant du shell de l'utilisateur ; affiche le code de sortie à la fin
	local script = cmd .. "\nc=$?\nprintf '\\n\\033[2m[Terminé, code %s — q pour fermer]\\033[0m\\n' \"$c\"\nexit $c"
	local t = Snacks.terminal.open({ "sh", "-c", script }, {
		cwd = cwd,
		count = 99, -- n'interfère pas avec les terminaux Espace t t
		interactive = false,
		start_insert = true, -- le programme peut lire au clavier (input, scanf…)
		auto_close = false,
		win = {
			position = "bottom",
			height = 0.3,
			wo = { winbar = " \u{f04b} " .. cmd:gsub("%%", "%%%%") },
			keys = { q = "hide" },
		},
	})
	-- À la fin du programme, retour en mode normal pour garder la sortie à l'écran
	t:on("TermClose", function()
		vim.schedule(function()
			if vim.api.nvim_get_current_buf() == t.buf then
				vim.cmd.stopinsert()
			end
		end)
	end, { buf = true })
	-- Neovim 0.12 se bloque si on ferme la fenêtre courante pendant ExitPre (:qa depuis le
	-- terminal) : on retire le ExitPre de Snacks, Neovim arrête le programme tout seul en quittant.
	if t.augroup then
		for _, au in ipairs(vim.api.nvim_get_autocmds({ group = t.augroup, event = "ExitPre" })) do
			vim.api.nvim_del_autocmd(au.id)
		end
	end
	term = t
	return t
end

-- Chemins relatifs des erreurs (make, cargo) : rendus absolus par rapport à cwd
-- (ou à un dossier parent, pour les espaces de travail cargo)
local function absolute(line, cwd)
	local f, rest = line:match("^([^/%s][^:]*)(:%d+:.*)$")
	if not f or not cwd then
		return line
	end
	local dir = cwd
	while dir do
		if vim.uv.fs_stat(dir .. "/" .. f) then
			return dir .. "/" .. f .. rest
		end
		local parent = vim.fs.dirname(dir)
		dir = parent ~= dir and parent or nil
	end
	return line
end

-- Compile en arrière-plan (partagé avec util.debug) ; erreurs → quickfix + Trouble.
-- opts : title (notifications), lines(res) (lignes à analyser, défaut stderr + stdout)
-- on_ok(res) n'est appelé qu'en cas de succès.
function M.compile(argv, cwd, opts, on_ok)
	opts = opts or {}
	local title = opts.title or "Exécuter"
	vim.notify("Compilation…", vim.log.levels.INFO, { title = title, id = "nide_run" })
	vim.system(argv, { cwd = cwd, text = true }, vim.schedule_wrap(function(res)
		local lines = opts.lines and opts.lines(res)
			or vim.split((res.stderr or "") .. (res.stdout or ""), "\n", { trimempty = true })
		lines = vim.tbl_map(function(l) return absolute(l, cwd) end, lines)
		local items = vim.fn.getqflist({ lines = lines, efm = M.errorformat }).items
		items = vim.tbl_filter(function(i) return i.valid == 1 end, items)
		vim.fn.setqflist({}, " ", { title = "Compilation : " .. table.concat(argv, " "), items = items })
		if res.code ~= 0 then
			vim.notify("Échec de la compilation\n" .. table.concat(vim.list_slice(lines, 1, 15), "\n"), vim.log.levels.ERROR, { title = title, id = "nide_run" })
			if #items > 0 then
				vim.cmd("Trouble qflist open")
			end
			return
		end
		local msg = #items > 0 and (#items .. " avertissement(s) — Espace x q pour les voir") or "Compilé"
		vim.notify(msg, #items > 0 and vim.log.levels.WARN or vim.log.levels.INFO, { title = title, id = "nide_run" })
		on_ok(res)
	end))
end

-- Compile puis lance dans le terminal
local function build_then_run(p)
	M.compile(p.build, p.cwd, nil, function()
		M.exec(p.run, p.cwd)
	end)
end

-- Point d'entrée : sauvegarde puis lance le fichier courant
function M.run(args)
	local file = vim.api.nvim_buf_get_name(0)
	-- Depuis le terminal d'exécution (ou un panneau) : relance le dernier fichier
	if vim.bo.buftype ~= "" and M.last_file and vim.fn.bufexists(M.last_file) == 1 then
		return vim.api.nvim_buf_call(vim.fn.bufnr(M.last_file), function()
			M.run(args)
		end)
	end
	if file == "" or vim.bo.buftype ~= "" then
		return vim.notify("Ouvre d'abord un fichier à exécuter", vim.log.levels.WARN, { title = "Exécuter" })
	end
	if vim.bo.modified then
		vim.cmd("silent write")
	end
	local p, err = M.plan(file, vim.bo.filetype, args)
	if p then
		-- vérifie que l'outil principal est installé (python3, node, cargo, go…)
		local tool = p.build and p.build[1] or p.run:match("^'?([^'%s]+)")
		if not exe(tool) then
			p, err = nil, tool .. " introuvable : installe-le pour lancer ce fichier"
		end
	end
	if not p then
		return vim.notify(err, vim.log.levels.WARN, { title = "Exécuter" })
	end
	M.last_file = file
	if p.build then
		build_then_run(p)
	else
		M.exec(p.run, p.cwd)
	end
end

-- Même chose en demandant les arguments du programme
function M.run_with_args()
	vim.ui.input({ prompt = "Arguments : ", default = M.last_args }, function(input)
		if input == nil then
			return
		end
		M.last_args = input
		M.run(input)
	end)
end

-- Affiche / masque le terminal d'exécution
function M.toggle()
	if term and term:buf_valid() then
		term:toggle()
	else
		vim.notify("Rien n'a encore été lancé", vim.log.levels.INFO, { title = "Exécuter" })
	end
end

return M
