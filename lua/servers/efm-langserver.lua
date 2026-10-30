-- ================================================================================================
-- TITLE : efm-langserver
-- ABOUT : a general purpose language server protocol implemented here for linters/formatters
-- LINKS :
--   > github : https://github.com/mattn/efm-langserver
--   > configs: https://github.com/creativenull/efmls-configs-nvim/tree/main
-- ================================================================================================

--- @param capabilities table LSP client capabilities (from nvim-cmp)
--- @return nil
return function(capabilities)
	local stylua = require("efmls-configs.formatters.stylua") -- lua formatter
	local flake8 = require("efmls-configs.linters.flake8") -- python linter
	local black = require("efmls-configs.formatters.black") -- python formatter
	local prettier_d = require("efmls-configs.formatters.prettier_d") -- markdown/yaml formatter
	local fixjson = require("efmls-configs.formatters.fixjson") -- json formatter
	local shellcheck = require("efmls-configs.linters.shellcheck") -- bash linter
	local shfmt = require("efmls-configs.formatters.shfmt") -- bash formatter
	local clangformat = require("efmls-configs.formatters.clang_format") -- c/cpp formatter

	vim.lsp.config("efm", {
		capabilities = capabilities,
		filetypes = {
			"c",
			"cpp",
			"json",
			"jsonc",
			"lua",
			"markdown",
			"python",
			"sh",
			"yaml",
		},
		init_options = {
			documentFormatting = true,
			documentRangeFormatting = true,
			hover = true,
			documentSymbol = true,
			codeAction = true,
			completion = true,
		},
		settings = {
			languages = {
				c = { clangformat },
				cpp = { clangformat },
				json = { fixjson },
				jsonc = { fixjson },
				lua = { stylua },
				markdown = { prettier_d },
				python = { flake8, black },
				sh = { shellcheck, shfmt },
				yaml = { prettier_d },
			},
		},
	})
end
