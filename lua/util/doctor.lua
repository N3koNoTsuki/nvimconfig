-- :NideDoctor : bilan de l'installation (modules, outils, LSP, notebooks, plugins…)
-- Les modules désactivés (lua/nide/modules.lua) ne sont pas signalés comme manquants.
-- Vérifications rapides (vim.fn.executable, fs_stat) ; versions, polices et taille du cache
-- en asynchrone (vim.system), affichées dès qu'elles arrivent.
-- Le même bilan sert à :checkhealth nide (lua/nide/health.lua).
local M = {}

local uv = vim.uv
local data = vim.fn.stdpath("data")
local cache = vim.fn.stdpath("cache")
local mason_root = data .. "/mason/packages/"
local venv = data .. "/molten-venv"
local spell_dir = data .. "/site/spell"
local spell_url = "https://ftp.nluug.nl/pub/vim/runtime/spell/"
local config_dir = vim.fn.stdpath("config")
local modules = require("nide.modules")
local INSTALL = vim.fn.fnamemodify(config_dir, ":~") .. "/install.sh" -- correctif : le relancer

local function exe(cmd)
	return vim.fn.executable(cmd) == 1
end

local function exists(path)
	return uv.fs_stat(path) ~= nil
end

local function mason_ok(pkg)
	return exists(mason_root .. pkg)
end

local function pacman(pkgs)
	return "sudo pacman -S --needed " .. pkgs
end

local function home(path)
	return (path:gsub("^" .. vim.pesc(vim.env.HOME or "~"), "~"))
end

-- ---------------------------------------------------------------------------
-- Résultats asynchrones (versions, polices, cache, modules Python du venv)
-- ---------------------------------------------------------------------------
M.async = {} ---@type table<string, any>
M.async_done = false

local version_cmds = {
	git = { "git", "--version" },
	node = { "node", "--version" },
	python3 = { "python3", "--version" },
	gcc = { "gcc", "-dumpfullversion" },
	["tree-sitter"] = { "tree-sitter", "--version" },
	rustc = { "rustc", "--version" },
	go = { "go", "version" },
	kitty = { "kitty", "--version" },
}

--- Lance les sondes asynchrones ; cb() quand toutes sont finies
function M.probe(cb)
	local jobs, pending = {}, 0
	local res = {}
	local function add(key, cmd, parse)
		if not exe(cmd[1]) then
			return
		end
		table.insert(jobs, { key = key, cmd = cmd, parse = parse })
	end
	local function version(out)
		return out.code == 0 and (out.stdout or ""):match("%d+%.%d+[%.%d]*") or nil
	end
	for name, cmd in pairs(version_cmds) do
		add("v:" .. name, cmd, version)
	end
	add("nerdfont", { "fc-list", ":", "family" }, function(out)
		return out.code == 0 and (out.stdout or ""):lower():find("nerd font", 1, true) ~= nil
	end)
	add("cache", { "du", "-sk", cache }, function(out)
		return tonumber((out.stdout or ""):match("^(%d+)"))
	end)
	add("pymods", { venv .. "/bin/python", "-c", "import pynvim, jupyter_client, ipykernel, nbformat" }, function(out)
		return out.code == 0
	end)
	pending = #jobs
	local function done()
		pending = pending - 1
		if pending == 0 then
			M.async, M.async_done = res, true
			if cb then
				vim.schedule(cb)
			end
		end
	end
	if pending == 0 then
		M.async, M.async_done = res, true
		if cb then
			vim.schedule(cb)
		end
		return
	end
	for _, job in ipairs(jobs) do
		local ok = pcall(vim.system, job.cmd, { text = true, timeout = 3000 }, function(out)
			res[job.key] = job.parse(out)
			done()
		end)
		if not ok then
			done()
		end
	end
end

--- Version synchrone (pour :checkhealth) : attend la fin des sondes
function M.probe_sync(timeout)
	local finished = false
	M.probe(function()
		finished = true
	end)
	vim.wait(timeout or 3000, function()
		return finished
	end, 10)
end

local function ver(name)
	return M.async["v:" .. name]
end

-- ---------------------------------------------------------------------------
-- Construction du bilan
-- Élément : { label, status = "ok"|"err"|"opt"|"info"|"off"|"wait", text?, fix?, mason?, parts? }
--   err  : problème (compte dans le résumé) ; opt : facultatif absent ; off : module désactivé
-- ---------------------------------------------------------------------------

local function tool(cmd, fix, opts)
	opts = opts or {}
	local ok = exe(cmd)
	return {
		label = cmd,
		status = ok and "ok" or (opts.optional and "opt" or "err"),
		text = ok and (ver(cmd) or opts.why) or opts.why,
		fix = not ok and fix or nil,
	}
end

local function section_nvim()
	local v = vim.version()
	local ok = vim.version.ge(v, { 0, 12, 0 })
	return {
		title = "Neovim",
		items = {
			{
				label = "version",
				status = ok and "ok" or "err",
				text = tostring(v) .. (ok and "" or " (0.12 minimum)"),
				fix = not ok and pacman("neovim") or nil,
			},
			{ label = "config", status = "info", text = home(config_dir) .. " (NVIM_APPNAME=" .. (vim.env.NVIM_APPNAME or "nvim") .. ")" },
		},
	}
end

local function section_terminal()
	local items = {}
	local kitty = vim.env.KITTY_WINDOW_ID ~= nil or (vim.env.TERM or ""):find("kitty") ~= nil
	local graphics = kitty or vim.env.TERM_PROGRAM == "ghostty" or vim.env.TERM_PROGRAM == "WezTerm"
	local name = kitty and "kitty" or vim.env.TERM_PROGRAM or vim.env.TERM or "?"
	table.insert(items, {
		label = "terminal",
		status = graphics and "ok" or "opt",
		text = name
			.. (kitty and ver("kitty") and (" " .. ver("kitty")) or "")
			.. (graphics and " (images : protocole kitty)" or " (pas d'images dans les notebooks)"),
		fix = not graphics and "utiliser kitty, ghostty ou WezTerm pour les graphiques" or nil,
	})
	-- moteur de l'intro animée (lua/nide/intro.lua)
	local iok, intro = pcall(require, "nide.intro")
	if iok then
		local mode, why = intro.engine()
		local off = vim.g.nide_intro == false
		table.insert(items, {
			label = "intro",
			status = off and "info" or mode == "kitty" and "ok" or "opt",
			text = (off and "désactivée (vim.g.nide_intro = false), moteur : " or "moteur : ")
				.. (mode == "kitty" and "kitty natif" or "demi-blocs")
				.. " (" .. why .. ")",
		})
	end
	local nerd = M.async.nerdfont
	table.insert(items, {
		label = "Nerd Font",
		status = not exe("fc-list") and "info" or (nerd == nil and not M.async_done) and "wait" or nerd and "ok" or "err",
		text = nerd and "police installée (kitty s'en sert pour les icônes)"
			or not exe("fc-list") and "fc-list absent, non vérifiable"
			or (nerd == nil and not M.async_done) and "vérification…"
			or "aucune police Nerd Font : icônes en carrés",
		fix = nerd == false and pacman("ttf-nerd-fonts-symbols") or nil,
	})
	local wayland = vim.env.WAYLAND_DISPLAY ~= nil
	local clip
	if wayland then
		clip = { label = "presse-papier", status = exe("wl-copy") and "ok" or "err", text = "Wayland : wl-copy" }
		clip.fix = clip.status == "err" and pacman("wl-clipboard") or nil
	elseif vim.env.DISPLAY then
		local ok = exe("xclip") or exe("xsel")
		clip = { label = "presse-papier", status = ok and "ok" or "err", text = "X11 : xclip / xsel", fix = not ok and pacman("xclip") or nil }
	else
		clip = { label = "presse-papier", status = "info", text = "sans affichage graphique : OSC 52 (copie via le terminal)" }
	end
	table.insert(items, clip)
	return { title = "Terminal", items = items }
end

local function section_modules()
	local items = {}
	local exists_file = exists(modules.file)
	table.insert(items, {
		label = "choix",
		status = "info",
		text = home(modules.file) .. (exists_file and "" or " (absent : tous les modules actifs)"),
		fix = INSTALL .. "  (relance-le pour changer de modules)",
	})
	for _, m in ipairs(modules.list) do
		local item = { label = m.label }
		if modules.enabled(m.id) then
			item.status, item.text = "ok", m.desc
		elseif modules.chosen(m.id) then -- choisi, mais la commande requise manque
			item.status, item.nocount = "opt", true -- déjà compté dans « Facultatifs »
			item.text = "choisi, mais « " .. m.requires .. " » est absent : module inactif"
			item.fix = pacman(m.requires) .. " puis relancer " .. INSTALL
		else
			item.status, item.text = "off", "désactivé (" .. m.desc .. ")"
			item.fix = INSTALL .. "  (relance-le pour l'activer)"
		end
		table.insert(items, item)
	end
	return { title = "Modules", items = items }
end

local function section_required()
	local list = {
		{ "git", "git" }, { "rg", "ripgrep" }, { "fd", "fd" }, { "gcc", "gcc" }, { "make", "make" },
		{ "tree-sitter", "tree-sitter-cli" }, { "curl", "curl" }, { "unzip", "unzip" },
		{ "node", "nodejs" }, { "npm", "npm" }, { "python3", "python" }, { "lazygit", "lazygit" },
	}
	local items = {}
	for _, t in ipairs(list) do
		table.insert(items, tool(t[1], pacman(t[2])))
	end
	return { title = "Indispensables", items = items }
end

-- Langages : { nom, exécutables, LSP (Mason), formateurs, débogueurs, facultatif, correctif système }
-- part = { nom, rôle, mason = paquet Mason | exe = commande }
local languages = {
	{ "Lua", { { "nvim -l", "exécuter", builtin = true }, { "lua-language-server", "LSP", mason = true },
		{ "stylua", "format", mason = true } } },
	{ "Python", { { "python3", "exécuter", exe = "python3", fix = pacman("python") },
		{ "pyright", "LSP", mason = true }, { "ruff", "LSP/format", mason = true }, { "debugpy", "debug", mason = true } },
		module = "python" },
	{ "C / C++", { { "gcc", "compiler", exe = "gcc", fix = pacman("gcc") }, { "g++", "compiler", exe = "g++", fix = pacman("gcc") },
		{ "clangd", "LSP", mason = true }, { "clang-format", "format", mason = true }, { "codelldb", "debug", mason = true } },
		module = "c" },
	{ "Rust", { { "rustc", "compiler", exe = "rustc", fix = pacman("rust") }, { "cargo", "projets", exe = "cargo", fix = pacman("rust") },
		{ "rust-analyzer", "LSP", mason = true }, { "rustfmt", "format", exe = "rustfmt", fix = pacman("rust") },
		{ "codelldb", "debug", mason = true } }, optional = true, module = "rust" },
	{ "JS / TS", { { "node", "exécuter", exe = "node", fix = pacman("nodejs") },
		{ "typescript-language-server", "LSP", mason = true, module = "web" }, { "prettierd", "format", mason = true } } },
	{ "Go", { { "go", "compiler", exe = "go", fix = pacman("go") }, { "gopls", "LSP", mason = true },
		{ "gofumpt", "format", mason = true }, { "goimports", "format", mason = true }, { "delve", "debug", mason = true } },
		optional = true, needs = "go", module = "go" },
	{ "Bash", { { "bash", "exécuter", exe = "bash", fix = pacman("bash") }, { "bash-language-server", "LSP", mason = true },
		{ "shfmt", "format", mason = true }, { "shellcheck", "lint", mason = true } } },
	{ "LaTeX", { { "latexmk", "compiler", exe = "latexmk", fix = pacman("texlive-basic texlive-latexextra texlive-binextra") },
		{ "texlab", "LSP", mason = true }, { "tex-fmt", "format", mason = true } }, optional = true, module = "latex" },
	{ "Web, données", { { "html-lsp", "LSP", mason = true, module = "web" }, { "css-lsp", "LSP", mason = true, module = "web" },
		{ "json-lsp", "LSP", mason = true }, { "yaml-language-server", "LSP", mason = true }, { "taplo", "LSP", mason = true },
		{ "marksman", "LSP", mason = true }, { "markdownlint", "lint", mason = true } } },
	{ "Docker", { { "dockerfile-language-server", "LSP", mason = true },
		{ "docker-compose-language-service", "LSP", mason = true }, { "hadolint", "lint", mason = true } }, module = "docker" },
	{ "SQL", { { "postgres-language-server", "LSP", mason = true }, { "sql-formatter", "format", mason = true } }, module = "sql" },
}

-- Le module (de la partie, sinon du langage) est-il désactivé, faute d'être choisi ?
-- (choisi mais commande requise absente : traité à part, cf. `needs`)
local function off(lang, p)
	local id = (p and p.module) or lang.module
	return id ~= nil and not modules.chosen(id)
end

--- Paquets Mason attendus par nide, modules désactivés exclus (pour les tests et :checkhealth)
function M.mason_packages()
	local out = {}
	for _, lang in ipairs(languages) do
		for _, p in ipairs(lang[2]) do
			if p.mason and not off(lang, p) and not vim.list_contains(out, p[1]) then
				table.insert(out, p[1])
			end
		end
	end
	return out
end

local function section_languages()
	local items = {}
	for _, lang in ipairs(languages) do
		if off(lang) then
			table.insert(items, {
				label = lang[1],
				status = "off",
				text = "module " .. modules.by_id[lang.module].label .. " désactivé",
			})
			goto continue
		end
		local item = { label = lang[1], parts = {}, mason = {} }
		local missing_sys, fixes = false, {}
		local blocked = lang.needs and not exe(lang.needs) -- outils Mason compilés avec `go install`
		for _, p in ipairs(lang[2]) do
			local ok
			if off(lang, p) then
				ok = true -- partie d'un module désactivé : affichée « – », jamais manquante
			elseif p.builtin then
				ok = true
			elseif p.mason then
				ok = mason_ok(p[1])
				if not ok and not blocked then
					table.insert(item.mason, p[1])
				end
			else
				ok = exe(p.exe)
				if not ok then
					missing_sys = true
					if p.fix and not vim.list_contains(fixes, p.fix) then
						table.insert(fixes, p.fix)
					end
				end
			end
			table.insert(item.parts, { name = p[1], role = p[2], ok = ok, skip = (blocked and p.mason) or off(lang, p) })
		end
		if #item.mason > 0 then
			table.insert(fixes, ":MasonInstall " .. table.concat(item.mason, " "))
		end
		if blocked then
			fixes[#fixes] = fixes[#fixes] .. " puis relancer install.sh"
		end
		local all_ok = not missing_sys and #item.mason == 0 and not blocked
		item.status = all_ok and "ok" or ((lang.optional and missing_sys) and "opt" or "err")
		item.nocount = item.status == "opt" -- déjà compté dans « Facultatifs »
		item.fix = #fixes > 0 and table.concat(fixes, "  ;  ") or nil
		if #item.mason == 0 then
			item.mason = nil
		end
		table.insert(items, item)
		::continue::
	end
	return { title = "Langages (exécuter · LSP · format · debug)", items = items }
end

local function section_notebooks()
	if not modules.enabled("notebook") then
		return {
			title = "Notebooks Jupyter",
			items = { { label = "notebooks", status = "off", text = "module désactivé (pas de venv, kernel ni molten)" } },
		}
	end
	local py = venv .. "/bin/python"
	local has_venv = exe(py)
	local items = {
		tool("uv", pacman("uv")),
		{
			label = "venv molten",
			status = has_venv and "ok" or "err",
			text = home(venv),
			fix = not has_venv and home(config_dir) .. "/install.sh" or nil,
		},
	}
	if has_venv then
		local mods = M.async.pymods
		table.insert(items, {
			label = "modules Python",
			status = (mods == nil and not M.async_done) and "wait" or mods and "ok" or "err",
			text = "pynvim, jupyter_client, ipykernel, nbformat",
			fix = mods == false
					and ("uv pip install --python " .. home(py) .. " pynvim jupyter_client nbformat ipykernel cairosvg pyperclip pillow")
				or nil,
		})
	end
	local jdata = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/jupyter/kernels/nvim-ide/kernel.json"
	local kernel = exists(jdata)
	table.insert(items, {
		label = "kernel nvim-ide",
		status = kernel and "ok" or "err",
		text = "Python (nvim-ide)",
		fix = not kernel and (home(py) .. ' -m ipykernel install --user --name nvim-ide --display-name "Python (nvim-ide)"') or nil,
	})
	local rplugin = data .. "/rplugin.vim"
	local registered = false
	local f = io.open(rplugin, "r")
	if f then
		registered = f:read("*a"):find("MoltenInit", 1, true) ~= nil
		f:close()
	end
	table.insert(items, {
		label = "molten enregistré",
		status = registered and "ok" or "err",
		text = "plugin distant (:MoltenInit)",
		fix = not registered and ":UpdateRemotePlugins (puis redémarrer)" or nil,
	})
	table.insert(items, tool("jupytext", "uv tool install jupytext", { why = ".ipynb ⇄ texte" }))
	table.insert(items, tool("magick", pacman("imagemagick"), { optional = true, why = "graphiques dans les notebooks" }))
	return { title = "Notebooks Jupyter", items = items }
end

local function section_optional()
	local o = { optional = true }
	local function opt(cmd, fix, why)
		o.why = why
		return tool(cmd, fix, o)
	end
	-- outils des modules désactivés : omis
	local items = {}
	local function add(id, cmd, fix, why)
		if id == nil or modules.chosen(id) then
			table.insert(items, opt(cmd, fix, why))
		end
	end
	add("go", "go", pacman("go") .. " puis relancer install.sh", "Go : F6, gopls, delve")
	add("latex", "latexmk", pacman("texlive-basic texlive-latexextra texlive-binextra"), "LaTeX : compilation (vimtex)")
	add("latex", "zathura", pacman("zathura zathura-pdf-mupdf"), "LaTeX : PDF synchronisé")
	add("web", "tsx", "npm i -g tsx", "TypeScript avec F6 (sinon node ≥ 22.18)")
	add(nil, "chafa", pacman("chafa"), "aperçus d'images en caractères (Snacks)")
	add("rust", "cargo", pacman("rust"), "Rust : projets cargo")
	return { title = "Facultatifs", items = items }
end

local function section_plugins()
	local items = {}
	local ok_lazy, Config = pcall(require, "lazy.core.config")
	if not ok_lazy then
		return { title = "Plugins", items = { { label = "lazy.nvim", status = "err", text = "non chargé" } } }
	end
	local Plugin = require("lazy.core.plugin")
	local count, loaded, broken, missing = 0, 0, {}, {}
	for name, p in pairs(Config.plugins) do
		count = count + 1
		if p._.loaded then
			loaded = loaded + 1
		end
		if not p._.installed then
			table.insert(missing, name)
		elseif Plugin.has_errors(p) then
			table.insert(broken, name)
		end
	end
	table.sort(missing)
	table.sort(broken)
	table.insert(items, { label = "lazy.nvim", status = "info", text = ("%d plugins, %d chargés"):format(count, loaded) })
	table.insert(items, {
		label = "installés",
		status = #missing == 0 and "ok" or "err",
		text = #missing == 0 and "tous" or ("manquants : " .. table.concat(missing, ", ")),
		fix = #missing > 0 and ":Lazy install" or nil,
	})
	table.insert(items, {
		label = "erreurs",
		status = #broken == 0 and "ok" or "err",
		text = #broken == 0 and "aucune (installation / build)" or table.concat(broken, ", "),
		fix = #broken > 0 and ":Lazy (détails, puis U pour réessayer)" or nil,
	})
	local spec_err = 0
	for _, n in ipairs(Config.spec and Config.spec.notifs or {}) do
		if n.level == vim.log.levels.ERROR then
			spec_err = spec_err + 1
		end
	end
	if spec_err > 0 then
		table.insert(items, { label = "spécification", status = "err", text = spec_err .. " erreur(s) dans lua/plugins/", fix = ":Lazy" })
	end
	local updated = package.loaded["lazy.manage.checker"] and require("lazy.manage.checker").updated or {}
	table.insert(items, {
		label = "mises à jour",
		status = "info",
		text = #updated == 0 and "aucune connue (vérification auto en arrière-plan)"
			or (#updated .. " disponible(s) : " .. table.concat(updated, ", ")),
		fix = #updated > 0 and ":Lazy update" or nil,
	})
	return { title = "Plugins", items = items }
end

local function size(kb)
	if kb >= 1024 * 1024 then
		return ("%.1f Go"):format(kb / 1024 / 1024)
	elseif kb >= 1024 then
		return ("%.0f Mo"):format(kb / 1024)
	end
	return kb .. " Ko"
end

local function section_misc()
	local items = {}
	for _, lang in ipairs({ "fr", "en" }) do
		local missing = {}
		for _, ext in ipairs({ "spl", "sug" }) do
			local file = lang .. ".utf-8." .. ext
			if not exists(spell_dir .. "/" .. file) then
				table.insert(missing, file)
			end
		end
		local fix
		if #missing > 0 then
			local cmds = { "mkdir -p " .. home(spell_dir) }
			for _, file in ipairs(missing) do
				table.insert(cmds, ("curl -fsSL -o %s/%s %s%s"):format(home(spell_dir), file, spell_url, file))
			end
			fix = table.concat(cmds, " && ")
		end
		table.insert(items, {
			label = "orthographe " .. lang,
			status = #missing == 0 and "ok" or "err",
			text = #missing == 0 and "dictionnaire présent" or ("manque " .. table.concat(missing, ", ")),
			fix = fix,
		})
	end
	if package.loaded["nvim-treesitter"] then
		local ok, inst = pcall(function()
			return require("nvim-treesitter").get_installed()
		end)
		if ok then
			local missing = {}
			for _, lang in ipairs(modules.parsers()) do
				if not vim.list_contains(inst, lang) then
					table.insert(missing, lang)
				end
			end
			table.insert(items, {
				label = "parsers treesitter",
				status = #missing == 0 and "info" or "err",
				text = #inst .. " installés" .. (#missing > 0 and (", manquants : " .. table.concat(missing, ", ")) or ""),
				fix = #missing > 0 and (":TSInstall " .. table.concat(missing, " ")) or nil,
			})
		end
	end
	local kb = M.async.cache
	table.insert(items, {
		label = "cache",
		status = (kb == nil and not M.async_done) and "wait" or "info",
		text = home(cache) .. (kb and (" : " .. size(kb)) or ""),
		fix = kb and kb > 1024 * 1024 and ("rm -rf " .. home(cache) .. "/*  (se reconstruit tout seul)") or nil,
	})
	local log = vim.fn.stdpath("log") .. "/lsp.log"
	local st = uv.fs_stat(log)
	if st then
		local big = st.size > 50 * 1024 * 1024
		table.insert(items, {
			label = "journal LSP",
			status = big and "opt" or "info",
			text = home(log) .. " : " .. size(math.floor(st.size / 1024)),
			fix = big and ("rm " .. home(log)) or nil,
		})
	end
	return { title = "Divers", items = items }
end

--- Bilan complet : { sections, problems, optional, ok, ms }
function M.collect()
	local t = uv.hrtime()
	local sections = {
		section_nvim(),
		section_modules(),
		section_terminal(),
		section_required(),
		section_languages(),
		section_notebooks(),
		section_optional(),
		section_plugins(),
		section_misc(),
	}
	local report = { sections = sections, problems = 0, optional = 0, ok = 0 }
	for _, s in ipairs(sections) do
		for _, it in ipairs(s.items) do
			if it.status == "err" then
				report.problems = report.problems + 1
			elseif it.status == "opt" and not it.nocount then
				report.optional = report.optional + 1
			elseif it.status == "ok" then
				report.ok = report.ok + 1
			end
		end
	end
	report.ms = (uv.hrtime() - t) / 1e6
	return report
end

--- Résumé en une ligne (« 3 problèmes, 5 facultatifs absents »)
function M.summary(report)
	local function plural(n, one, many)
		return n .. " " .. (n > 1 and many or one)
	end
	return ("%s, %s, %s"):format(
		report.problems == 0 and "aucun problème" or plural(report.problems, "problème", "problèmes"),
		plural(report.optional, "facultatif absent", "facultatifs absents"),
		plural(report.ok, "vérification OK", "vérifications OK")
	)
end

-- ---------------------------------------------------------------------------
-- Affichage
-- ---------------------------------------------------------------------------
local icons = { ok = "✓", err = "✗", opt = "○", info = "•", off = "–", wait = "…" }
local hls = {
	ok = "DiagnosticOk",
	err = "DiagnosticError",
	opt = "DiagnosticWarn",
	info = "DiagnosticInfo",
	off = "Comment",
	wait = "Comment",
}
local ns = vim.api.nvim_create_namespace("nide_doctor")

local function render(report)
	local lines, marks, map = {}, {}, {}
	local function add(text, hl_spans, item)
		table.insert(lines, text)
		local lnum = #lines - 1
		for _, h in ipairs(hl_spans or {}) do
			table.insert(marks, { lnum, h[1], h[2], h[3] })
		end
		map[#lines] = item
	end
	local head = "  " .. M.summary(report)
	add(head, { { 2, #head, report.problems > 0 and "DiagnosticError" or "DiagnosticOk" } })
	local keys = "  q fermer · i installer via Mason · r relancer · y copier le correctif"
		.. ("   (%.0f ms)"):format(report.ms)
	add(keys, { { 0, #keys, "Comment" } })
	for _, s in ipairs(report.sections) do
		add("")
		add(s.title, { { 0, #s.title, "Title" } })
		for _, it in ipairs(s.items) do
			local icon = icons[it.status]
			local prefix = "  " .. icon .. " "
			local label = it.label .. string.rep(" ", math.max(1, 20 - vim.fn.strdisplaywidth(it.label)))
			local line = prefix .. label
			local spans = { { 2, 2 + #icon, hls[it.status] } }
			if it.parts then
				for _, p in ipairs(it.parts) do
					local pi = p.skip and "–" or p.ok and "✓" or "✗"
					local start = #line
					line = line .. pi .. " " .. p.name .. " "
					table.insert(spans, { start, start + #pi, p.skip and "Comment" or p.ok and "DiagnosticOk" or "DiagnosticError" })
					local role = "(" .. p.role .. ")  "
					table.insert(spans, { #line, #line + #role, "Comment" })
					line = line .. role
				end
			elseif it.text then
				line = line .. it.text
			end
			add(line, spans, it)
			if it.fix then
				local fix = "      → " .. it.fix
				add(fix, { { 6, #fix, "Special" } }, it)
			end
		end
	end
	return lines, marks, map
end

M.state = nil ---@type {win: snacks.win, buf: integer, map: table, report: table}?

local function paint(buf, report)
	local lines, marks, map = render(report)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, m in ipairs(marks) do
		pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
	end
	return map
end

local function refresh()
	local st = M.state
	if not (st and vim.api.nvim_buf_is_valid(st.buf)) then
		return
	end
	st.report = M.collect()
	st.map = paint(st.buf, st.report)
end

local function rerun()
	refresh()
	M.probe(refresh)
end

--- Paquets Mason à installer : ceux de la ligne sous le curseur, sinon tous
function M.missing_mason(item)
	if item and item.mason then
		return item.mason
	end
	local all = {}
	for _, s in ipairs((M.state and M.state.report or M.collect()).sections) do
		for _, it in ipairs(s.items) do
			for _, p in ipairs(it.mason or {}) do
				if not vim.list_contains(all, p) then
					table.insert(all, p)
				end
			end
		end
	end
	return all
end

local function current_item()
	local st = M.state
	if not st then
		return
	end
	return st.map[vim.api.nvim_win_get_cursor(0)[1]]
end

local function install()
	local pkgs = M.missing_mason(current_item())
	if #pkgs == 0 then
		return vim.notify("Rien à installer via Mason", vim.log.levels.INFO, { title = "Docteur" })
	end
	if M.state and M.state.win then
		M.state.win:close()
	end
	require("lazy").load({ plugins = { "mason.nvim" } })
	vim.cmd("MasonInstall " .. table.concat(pkgs, " "))
end

local function yank()
	local it = current_item()
	if not (it and it.fix) then
		return vim.notify("Pas de correctif sur cette ligne", vim.log.levels.INFO, { title = "Docteur" })
	end
	local cmd = it.fix:gsub("  ;  .*$", ""):gsub("  %(.-%)$", "")
	vim.fn.setreg('"', cmd)
	pcall(vim.fn.setreg, "+", cmd)
	vim.notify("Copié : " .. cmd, vim.log.levels.INFO, { title = "Docteur" })
end

--- :NideDoctor
function M.open()
	if M.state and M.state.win and M.state.win:valid() then
		M.state.win:focus()
		return rerun()
	end
	local report = M.collect()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "nidedoctor"
	local map = paint(buf, report)
	local keys = {
		q = "close",
		["<Esc>"] = "close",
		i = { install, desc = "Installer via Mason" },
		r = { rerun, desc = "Relancer le bilan" },
		y = { yank, desc = "Copier le correctif" },
	}
	local win
	if package.loaded.snacks or pcall(require, "snacks") then
		win = Snacks.win({
			buf = buf,
			width = 0.8,
			height = 0.85,
			border = "rounded",
			title = " Docteur nide ",
			title_pos = "center",
			enter = true,
			backdrop = false,
			keys = keys,
			wo = { wrap = false, cursorline = true, spell = false },
		})
	else -- repli : fenêtre normale
		vim.cmd("botright split")
		vim.api.nvim_win_set_buf(0, buf)
		for lhs, rhs in pairs(keys) do
			local fn = rhs == "close" and function() vim.cmd.close() end or rhs[1]
			vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = rhs.desc })
		end
	end
	M.state = { win = win, buf = buf, map = map, report = report }
	M.probe(refresh)
end

return M
