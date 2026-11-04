-- ================================================================================================
-- TITLE : telescope.nvim
-- LINKS :
--   > github : https://github.com/nvim-telescope/telescope.nvim
-- ABOUT : highly extendable fuzzy finder (files, grep, buffers, LSP, diagnostics...).
--         telescope-fzf-native : faster sorting with the fzf syntax ('exact ^start end$ !not)
--         telescope-ui-select  : vim.ui.select (code actions...) in telescope
-- ================================================================================================

local function builtin(name, opts)
	return function()
		require("telescope.builtin")[name](opts)
	end
end

return {
	"nvim-telescope/telescope.nvim",
	cmd = "Telescope",
	event = "VeryLazy", -- for vim.ui.select
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
		"nvim-telescope/telescope-ui-select.nvim",
	},
	keys = {
		{ "<leader>ff", builtin("find_files"), desc = "Telescope Files" },
		{ "<leader>fg", builtin("live_grep"), desc = "Telescope Live Grep" },
		{ "<leader>fb", builtin("buffers"), desc = "Telescope Buffers" },
		{ "<leader>fh", builtin("help_tags"), desc = "Telescope Help Tags" },
		{ "<leader>fo", builtin("oldfiles"), desc = "Telescope Recent Files" },
		{ "<leader>f/", builtin("current_buffer_fuzzy_find"), desc = "Telescope Search in File" },
		{ "<leader>fx", builtin("diagnostics", { bufnr = 0 }), desc = "Telescope Diagnostics Document" },
		{ "<leader>fX", builtin("diagnostics"), desc = "Telescope Diagnostics Workspace" },
		{ "<leader>fs", builtin("lsp_document_symbols"), desc = "Telescope Document Symbols" },
		{ "<leader>fS", builtin("lsp_dynamic_workspace_symbols"), desc = "Telescope Workspace Symbols" },
		{ "<leader>fR", builtin("resume"), desc = "Telescope Resume Last Picker" },
	},
	config = function()
		local telescope = require("telescope")
		local actions = require("telescope.actions")
		telescope.setup({
			defaults = {
				sorting_strategy = "ascending",
				layout_config = { prompt_position = "top" },
				mappings = {
					i = {
						["<C-j>"] = actions.move_selection_next,
						["<C-k>"] = actions.move_selection_previous,
						["<C-q>"] = actions.smart_send_to_qflist + actions.open_qflist,
					},
				},
			},
			extensions = {
				["ui-select"] = { require("telescope.themes").get_dropdown() },
			},
		})
		telescope.load_extension("fzf")
		telescope.load_extension("ui-select")
	end,
}
