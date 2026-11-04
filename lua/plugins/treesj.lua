-- ================================================================================================
-- TITLE : treesj
-- LINKS :
--   > github : https://github.com/Wansmer/treesj
-- ABOUT : split / join blocks of code with treesitter: arguments, arrays, struct initialisers,
--         if bodies... { 1, 2, 3 } on one line <-> one element per line.
-- ================================================================================================

return {
	"Wansmer/treesj",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	keys = {
		{
			"<leader>cj",
			function()
				require("treesj").toggle()
			end,
			desc = "Split / join block (treesj)",
		},
		{
			"<leader>cJ",
			function()
				require("treesj").toggle({ split = { recursive = true } })
			end,
			desc = "Split / join block, nested too (treesj)",
		},
	},
	opts = {
		use_default_keymaps = false, -- <leader>s is taken by the splits
		max_join_length = 150,
	},
}
