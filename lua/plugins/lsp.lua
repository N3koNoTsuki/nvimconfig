-- Serveurs de langage et outils (formateurs, linters, débogueurs) installés par Mason :
-- base + modules activés (voir lua/nide/modules.lua ; Go seulement si `go` est présent)
local modules = require("nide.modules")
local servers = modules.servers()
local tools = modules.tools()

local function on_attach(args)
	local buf = args.buf
	local client = vim.lsp.get_client_by_id(args.data.client_id)
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
	end
	map("n", "K", function() vim.lsp.buf.hover() end, "Documentation (survol)")
	map("n", "gK", vim.lsp.buf.signature_help, "Signature de la fonction")
	map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "Actions de code (corrections)")
	map("n", "<leader>cr", vim.lsp.buf.rename, "Renommer le symbole")
	map("n", "<F2>", vim.lsp.buf.rename, "Renommer le symbole")
	map("n", "<leader>cl", vim.lsp.codelens.run, "Lancer la CodeLens")
	map("n", "<leader>ci", "<Cmd>checkhealth vim.lsp<CR>", "Infos LSP")

	-- CodeLens affichées au-dessus du code (ex. gopls : lancer les tests, go generate)
	if client and client:supports_method("textDocument/codeLens") then
		vim.lsp.codelens.enable(true, { bufnr = buf })
	end

	-- ruff s'occupe du lint Python, pyright des types : on évite les doublons de survol
	if client and client.name == "ruff" then
		client.server_capabilities.hoverProvider = false
	end
end

return {
	{ "mason-org/mason.nvim", cmd = "Mason", opts = { ui = { border = "rounded" } } },
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		init = function()
			-- Fichiers Docker Compose : type dédié (yaml + serveur compose)
			vim.filetype.add({
				filename = {
					["compose.yaml"] = "yaml.docker-compose",
					["compose.yml"] = "yaml.docker-compose",
					["docker-compose.yaml"] = "yaml.docker-compose",
					["docker-compose.yml"] = "yaml.docker-compose",
				},
			})
			vim.treesitter.language.register("yaml", "yaml.docker-compose")
		end,
		dependencies = {
			"mason-org/mason.nvim",
			"mason-org/mason-lspconfig.nvim",
			"WhoIsSethDaniel/mason-tool-installer.nvim",
			"saghen/blink.cmp",
		},
		config = function()
			vim.diagnostic.config({
				severity_sort = true,
				underline = true,
				update_in_insert = false,
				virtual_text = { spacing = 2, source = "if_many", prefix = "●" },
				float = { border = "rounded", source = true },
				signs = {
					text = {
						[vim.diagnostic.severity.ERROR] = "\u{f057} ",
						[vim.diagnostic.severity.WARN] = "\u{f071} ",
						[vim.diagnostic.severity.HINT] = "\u{f0eb} ",
						[vim.diagnostic.severity.INFO] = "\u{f05a} ",
					},
				},
			})

			vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						completion = { callSnippet = "Replace" },
						hint = { enable = true },
						workspace = { checkThirdParty = false },
					},
				},
			})
			-- C/C++ : base de compilation générée si le projet n'en a pas (voir lua/util/compiledb.lua),
			-- pour que gd aille au corps de la fonction dans le .c et pas au prototype du .h
			local compiledb = require("util.compiledb")
			vim.lsp.config("clangd", {
				cmd = { "clangd", "--background-index", "--clang-tidy", "--header-insertion=iwyu" },
				root_dir = function(bufnr, on_dir)
					on_dir(compiledb.root(bufnr))
				end,
				before_init = function(params, config)
					local dir = config.root_dir and compiledb.generate(config.root_dir)
					if dir then
						params.initializationOptions = vim.tbl_extend(
							"force",
							params.initializationOptions or {},
							{ compilationDatabasePath = dir }
						)
					end
				end,
			})
			vim.lsp.config("gopls", {
				settings = {
					gopls = {
						gofumpt = true,
						staticcheck = true,
						usePlaceholders = true,
						analyses = { unusedparams = true, unusedwrite = true, nilness = true },
						codelenses = { test = true, tidy = true, upgrade_dependency = true, generate = true },
						hints = {
							assignVariableTypes = true,
							compositeLiteralFields = true,
							constantValues = true,
							functionTypeParameters = true,
							parameterNames = true,
							rangeVariableTypes = true,
						},
					},
				},
			})
			-- LaTeX : vimtex compile et affiche le PDF, texlab sert à la complétion et aux références
			vim.lsp.config("texlab", {
				settings = { texlab = { build = { onSave = false }, chktex = { onOpenAndSave = false } } },
			})
			-- SQL (PostgreSQL) : marche aussi sans fichier de config, à la racine git ou dans le dossier
			vim.lsp.config("postgres_lsp", {
				root_markers = { "postgres-language-server.jsonc", ".git" },
				workspace_required = false,
			})

			vim.api.nvim_create_user_command("CompileDb", compiledb.refresh, {
				desc = "Régénérer compile_commands.json (après ajout d'un .c) et relancer clangd",
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("ide_lsp", { clear = true }),
				callback = on_attach,
			})

			local exclude = { "stylua" }
			for _, name in ipairs(modules.all_servers()) do
				if not vim.list_contains(servers, name) then
					table.insert(exclude, name)
				end
			end
			require("mason-lspconfig").setup({
				ensure_installed = servers,
				-- stylua formate via conform ; les serveurs des modules désactivés ne démarrent pas,
				-- même si leur paquet Mason est resté installé
				automatic_enable = { exclude = exclude },
			})
			require("mason-tool-installer").setup({
				ensure_installed = vim.list_extend(vim.deepcopy(servers), tools),
				run_on_start = true,
			})
		end,
	},
}
