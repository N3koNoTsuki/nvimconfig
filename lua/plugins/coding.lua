-- Parsers treesitter : base + modules activés (voir lua/nide/modules.lua)
local modules = require("nide.modules")
local parsers = modules.parsers()

-- Formateurs (conform) et linters (nvim-lint) des modules : déclarés seulement si le module
-- est activé, sinon conform signalerait à chaque sauvegarde un formateur introuvable
local function by_module(base, extra)
	for id, fts in pairs(extra) do
		if modules.enabled(id) then
			base = vim.tbl_extend("force", base, fts)
		end
	end
	return base
end

local formatters_by_ft = by_module({
	lua = { "stylua" },
	javascript = { "prettierd" },
	typescript = { "prettierd" },
	javascriptreact = { "prettierd" },
	typescriptreact = { "prettierd" },
	css = { "prettierd" },
	html = { "prettierd" },
	json = { "prettierd" },
	yaml = { "prettierd" },
	markdown = { "prettierd" },
	sh = { "shfmt" },
	bash = { "shfmt" },
	["_"] = { "trim_whitespace" },
}, {
	python = { python = { "ruff_organize_imports", "ruff_format" } },
	c = { c = { "clang-format" }, cpp = { "clang-format" } },
	rust = { rust = { "rustfmt", lsp_format = "fallback" } },
	go = { go = { "goimports", "gofumpt" } },
	latex = { tex = { "tex-fmt" } },
	sql = { sql = { "sql_formatter" } },
})

local linters_by_ft = by_module({
	sh = { "shellcheck" },
	bash = { "shellcheck" },
	markdown = { "markdownlint" },
}, {
	docker = { dockerfile = { "hadolint" } },
	latex = { tex = { "chktex" } }, -- fourni par TeX Live (ignoré s'il est absent)
})

return {
	-- Coloration et compréhension du code
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local ts = require("nvim-treesitter")
			ts.setup({})
			local missing = vim.tbl_filter(function(p)
				return not vim.list_contains(ts.get_installed(), p)
			end, parsers)
			if #missing > 0 then
				ts.install(missing)
			end
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("ide_treesitter", { clear = true }),
				callback = function(args)
					if args.match == "tex" then
						return -- LaTeX : la coloration de vimtex est plus complète
					end
					local lang = vim.treesitter.language.get_lang(args.match)
					if lang and pcall(vim.treesitter.start, args.buf, lang) then
						vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
	},
	-- Garde la signature de la fonction / la classe visible en haut quand on scrolle
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = "BufReadPost",
		opts = { max_lines = 3 },
		keys = {
			{ "[u", function() require("treesitter-context").go_to_context(vim.v.count1) end, desc = "Remonter au contexte" },
		},
	},

	-- Autocomplétion
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = { "rafamadriz/friendly-snippets" },
		opts = {
			keymap = {
				preset = "enter",
				["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
				["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
				["<C-j>"] = { "select_next", "fallback" },
				["<C-k>"] = { "select_prev", "fallback" },
			},
			appearance = { nerd_font_variant = "mono" },
			completion = {
				documentation = { auto_show = true, auto_show_delay_ms = 200 },
				ghost_text = { enabled = true },
				menu = { draw = { treesitter = { "lsp" } } },
				list = { selection = { preselect = false, auto_insert = true } },
			},
			signature = { enabled = true },
			cmdline = { completion = { menu = { auto_show = true } } },
			sources = {
				default = { "lazydev", "lsp", "path", "snippets", "buffer" },
				providers = {
					lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
				},
			},
		},
	},

	-- Lua de Neovim compris par le LSP (pour modifier cette config)
	{ "folke/lazydev.nvim", ft = "lua", opts = { library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } } } },

	-- Formatage (automatique à la sauvegarde)
	{
		"stevearc/conform.nvim",
		event = "BufWritePre",
		cmd = "ConformInfo",
		keys = {
			{ "<leader>cf", function() require("conform").format({ async = true }) end, mode = { "n", "x" }, desc = "Formater" },
			{
				"<leader>uf",
				function()
					vim.g.disable_autoformat = not vim.g.disable_autoformat
					vim.notify("Formatage à la sauvegarde : " .. (vim.g.disable_autoformat and "OFF" or "ON"))
				end,
				desc = "Formatage auto (on/off)",
			},
		},
		opts = {
			formatters_by_ft = formatters_by_ft,
			format_on_save = function(buf)
				if vim.g.disable_autoformat or vim.b[buf].disable_autoformat then
					return
				end
				return { timeout_ms = 1500, lsp_format = "fallback" }
			end,
		},
	},

	-- Linting (en plus des diagnostics LSP)
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufWritePost" },
		config = function()
			local lint = require("lint")
			lint.linters_by_ft = linters_by_ft
			local function try_lint(buf)
				if vim.api.nvim_buf_get_name(buf):match("%.ipynb$") then
					return -- notebook : le markdown généré n'est pas à corriger
				end
				lint.try_lint(nil, { ignore_errors = true })
			end
			vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
				group = vim.api.nvim_create_augroup("ide_lint", { clear = true }),
				callback = function(args) try_lint(args.buf) end,
			})
			vim.schedule(function() try_lint(0) end) -- fichier qui a déclenché le chargement (type connu après)
		end,
	},

	-- Markdown rendu directement dans l'éditeur
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = "markdown",
		opts = { completions = { blink = { enabled = true } } },
		keys = { { "<leader>um", "<Cmd>RenderMarkdown toggle<CR>", desc = "Rendu Markdown (on/off)" } },
	},
}
