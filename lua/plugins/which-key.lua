-- ================================================================================================
-- TITLE : which-key
-- ABOUT : WhichKey helps you remember your Neovim keymaps, by showing keybindings as you type.
-- LINKS :
--   > github : https://github.com/folke/which-key.nvim
-- ================================================================================================

return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		spec = {
			{ "<leader>b", group = "Buffers" },
			{ "<leader>c", group = "Code" },
			{ "<leader>d", group = "Debug / Diagnostics" },
			{ "<leader>f", group = "Find (fzf)" },
			{ "<leader>g", group = "Goto" },
			{ "<leader>gs", group = "Goto in vsplit" },
			{ "<leader>n", group = "Next" },
			{ "<leader>p", group = "Previous / Path" },
			{ "<leader>r", group = "Rename / Config" },
			{ "<leader>s", group = "Splits" },
			{ "<leader>h", group = "Git" },
		},
	},
	keys = {
		{
			"<leader>/",
			function()
				require("utils.cheatsheet").open()
			end,
			desc = "Cheatsheet (keymaps with examples)",
		},
		{
			"<leader>fk",
			function()
				require("fzf-lua").keymaps({ show_desc = true, show_details = false })
			end,
			desc = "Search all keymaps (with descriptions)",
		},
	},
}
