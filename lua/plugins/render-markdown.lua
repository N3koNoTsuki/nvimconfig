-- ================================================================================================
-- TITLE : render-markdown.nvim
-- ABOUT : Renders markdown in place (headings, lists, checkboxes, tables, code blocks, quotes).
-- LINKS :
--   > github : https://github.com/MeanderingProgrammer/render-markdown.nvim
-- DEPENDENCIES/INTEGRATIONS:
--   > nvim-treesitter (parsers "markdown" & "markdown_inline")
--   > nvim-web-devicons (icons, requires a Nerd Font)
-- ================================================================================================

return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},
	ft = { "markdown" },

	keys = {
		{ "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", ft = "markdown", desc = "Toggle Markdown Render" },
		{ "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", ft = "markdown", desc = "Toggle Markdown Preview (browser)" },
	},

	opts = {
		completions = { lsp = { enabled = true } },
	},
}
