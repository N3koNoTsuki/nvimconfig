-- Modules de nide : ce que chaque module optionnel apporte (serveurs LSP, outils Mason,
-- parsers treesitter, plugins), et lesquels sont activés.
--
-- Source unique de vérité, lue par :
--   install.sh          (menu à cocher, --all, --only ; écrit le fichier de choix)
--   lua/plugins/*.lua   (n'installe / ne charge que les modules activés)
--   lua/util/doctor.lua (ignore les modules désactivés)
--
-- Choix enregistrés dans stdpath("data")/nide-modules.json (hors du dépôt git) :
--   { "modules": { "c": true, "rust": false, ... } }
-- Fichier absent ou illisible, ou module absent du fichier : module ACTIVÉ
-- (une installation sans choix garde tout, un module ajouté plus tard est actif par défaut).

local M = {}

-- NIDE_MODULES_FILE : autre fichier de choix (tests, sans toucher à celui de l'utilisateur)
M.file = vim.env.NIDE_MODULES_FILE or (vim.fn.stdpath("data") .. "/nide-modules.json")

-- Toujours installé : l'éditeur et les langages de tous les jours
M.base = {
	servers = { "lua_ls", "bashls", "jsonls", "yamlls", "marksman", "taplo" },
	tools = { "stylua", "shfmt", "shellcheck", "markdownlint", "prettierd" }, -- prettierd : JSON, YAML, Markdown
	parsers = {
		"bash", "diff", "git_config", "gitcommit", "gitignore", "json", "lua", "luadoc", "make",
		"markdown", "markdown_inline", "query", "regex", "toml", "vim", "vimdoc", "yaml", "java",
	},
}

-- Modules optionnels, dans l'ordre du menu de install.sh.
--   id       : identifiant (install.sh --only c,python ; M.enabled("c"))
--   label    : nom affiché ; desc : résumé affiché dans le menu
--   servers  : serveurs LSP (noms lspconfig, installés par Mason)
--   tools    : formateurs / linters / débogueurs Mason
--   parsers  : parsers treesitter
--   plugins  : plugins lazy.nvim propres au module (chargés seulement s'il est activé)
--   requires : commande système sans laquelle le module ne s'active pas (Mason compile avec)
M.list = {
	{
		id = "c", label = "C / C++", desc = "clangd, clang-format, débogueur codelldb",
		servers = { "clangd" }, tools = { "clang-format", "codelldb" }, parsers = { "c", "cpp" },
	},
	{
		id = "rust", label = "Rust", desc = "rust-analyzer, débogueur codelldb, tests",
		servers = { "rust_analyzer" }, tools = { "codelldb" }, parsers = { "rust" },
		plugins = { "rouge8/neotest-rust" },
	},
	{
		id = "python", label = "Python", desc = "pyright, ruff, débogueur debugpy, tests",
		servers = { "pyright", "ruff" }, tools = { "debugpy" }, parsers = { "python" },
		plugins = { "nvim-neotest/neotest-python" },
	},
	{
		id = "web", label = "Web", desc = "TypeScript / JavaScript, HTML, CSS",
		servers = { "ts_ls", "html", "cssls" }, tools = {},
		parsers = { "javascript", "typescript", "tsx", "html", "css" },
	},
	{
		id = "go", label = "Go", desc = "gopls, gofumpt, débogueur delve, tests", requires = "go",
		servers = { "gopls" }, tools = { "gofumpt", "goimports", "delve" },
		parsers = { "go", "gomod", "gosum", "gowork" },
		plugins = { "leoluz/nvim-dap-go", "fredrikaverpil/neotest-golang" },
	},
	{
		id = "latex", label = "LaTeX", desc = "texlab, tex-fmt, vimtex (compilation, PDF)",
		servers = { "texlab" }, tools = { "tex-fmt" }, parsers = {},
		plugins = { "lervag/vimtex" },
	},
	{
		id = "docker", label = "Docker", desc = "Dockerfile, compose, hadolint",
		servers = { "dockerls", "docker_compose_language_service" }, tools = { "hadolint" },
		parsers = { "dockerfile" },
	},
	{
		id = "sql", label = "SQL", desc = "PostgreSQL (postgres_lsp), sql-formatter",
		servers = { "postgres_lsp" }, tools = { "sql-formatter" }, parsers = { "sql" },
	},
	{
		id = "notebook", label = "Notebooks", desc = "Jupyter (.ipynb) : cellules, kernel, graphiques",
		servers = {}, tools = {}, parsers = {},
		plugins = { "benlubas/molten-nvim", "3rd/image.nvim", "GCBallesteros/jupytext.nvim", "jmbuhr/otter.nvim" },
	},
	{
		id = "discord", label = "Discord", desc = "activité Rich Presence (cord.nvim, marche avec Vesktop)",
		servers = {}, tools = {}, parsers = {},
		plugins = { "vyfor/cord.nvim" },
	},
}

M.by_id = {}
for _, m in ipairs(M.list) do
	M.by_id[m.id] = m
end

local choices -- cache : { id = bool } lu depuis M.file

--- Choix enregistrés (table id -> bool), {} si pas de fichier
function M.choices()
	if choices == nil then
		choices = {}
		local ok, data = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(M.file), "\n"))
		end)
		if ok and type(data) == "table" and type(data.modules) == "table" then
			for id, v in pairs(data.modules) do
				choices[id] = v == true
			end
		end
	end
	return choices
end

--- Le module est-il choisi (sans tenir compte de `requires`) ?
function M.chosen(id)
	local v = M.choices()[id]
	return v == nil or v
end

--- Le module est-il actif : choisi, et sa commande requise présente ?
function M.enabled(id)
	local m = M.by_id[id]
	if not m then
		error("nide.modules : module inconnu « " .. tostring(id) .. " »")
	end
	if not M.chosen(id) then
		return false
	end
	return m.requires == nil or vim.fn.executable(m.requires) == 1
end

-- Concatène sans doublons le champ `field` de la base et des modules actifs
local function collect(field)
	local out, seen = {}, {}
	local function add(list)
		for _, v in ipairs(list or {}) do
			if not seen[v] then
				seen[v] = true
				table.insert(out, v)
			end
		end
	end
	add(M.base[field])
	for _, m in ipairs(M.list) do
		if M.enabled(m.id) then
			add(m[field])
		end
	end
	return out
end

function M.servers() return collect("servers") end
function M.tools() return collect("tools") end
function M.parsers() return collect("parsers") end

--- Tous les serveurs LSP connus (base + tous les modules), pour savoir lesquels désactiver
function M.all_servers()
	local out = vim.deepcopy(M.base.servers)
	for _, m in ipairs(M.list) do
		vim.list_extend(out, m.servers or {})
	end
	return out
end

--- Le plugin (nom "auteur/depot") appartient-il à un module désactivé ?
--- Usage dans une spec lazy (enabled, pas cond : un plugin désactivé est ainsi désinstallé par Lazy clean) :
---   enabled = function() return require("nide.modules").plugin_enabled("vyfor/cord.nvim") end
function M.plugin_enabled(name)
	for _, m in ipairs(M.list) do
		if vim.tbl_contains(m.plugins or {}, name) and not M.enabled(m.id) then
			return false
		end
	end
	return true
end

--- Écrit les choix (table id -> bool) ; utilisé par install.sh via nvim --headless
function M.save(tbl)
	local data = { modules = {} }
	for _, m in ipairs(M.list) do
		data.modules[m.id] = tbl[m.id] ~= false
	end
	vim.fn.mkdir(vim.fn.fnamemodify(M.file, ":h"), "p")
	vim.fn.writefile({ vim.json.encode(data) }, M.file)
	choices = nil
end

return M
