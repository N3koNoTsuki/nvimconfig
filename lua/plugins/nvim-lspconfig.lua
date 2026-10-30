-- ================================================================================================
-- TITLE : nvim-lspconfig
-- ABOUT : Quickstart configurations for the built-in Neovim LSP client.
-- LINKS :
--   > github                         : https://github.com/neovim/nvim-lspconfig
--   > mason.nvim (dep)               : https://github.com/mason-org/mason.nvim
--   > mason-tool-installer.nvim (dep): https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim
--   > efmls-configs-nvim (dep)       : https://github.com/creativenull/efmls-configs-nvim
--   > cmp-nvim-lsp (dep)             : https://github.com/hrsh7th/cmp-nvim-lsp
-- ================================================================================================

return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{ "mason-org/mason.nvim", opts = {} }, -- LSP/DAP/Linter installer & manager
		{
			"WhoIsSethDaniel/mason-tool-installer.nvim", -- auto-install the tools below via mason
			opts = {
				ensure_installed = {
					-- LSP
					"lua-language-server",
					"pyright",
					"clangd",
					"rust-analyzer",
					"bash-language-server",
					"json-lsp",
					"yaml-language-server",
					"marksman",
					"taplo",
					"autotools-language-server",
					"efm",
					-- Linters & Formatters
					"stylua",
					"flake8",
					"black",
					"clang-format",
					"shellcheck",
					"shfmt",
					"prettierd",
					"fixjson",
					-- Debuggers
					"codelldb",
				},
			},
		},
		"creativenull/efmls-configs-nvim", -- Preconfigured EFM Language Server setups
		"hrsh7th/cmp-nvim-lsp", -- nvim-cmp source for LSP-based completion
	},
	config = function()
		require("utils.diagnostics").setup()
		require("servers")
	end,
}
