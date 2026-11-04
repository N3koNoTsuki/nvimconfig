-- ================================================================================================
-- TITLE : flash.nvim
-- LINKS :
--   > github : https://github.com/folke/flash.nvim
-- ABOUT : jump anywhere on screen: type a few chars of the target, then its label.
--         On S, not on the usual s : s is the prefix of mini.surround (sa, sd, sr...).
--         f / t / F / T are enhanced too (repeat with f/t again, labels after the cursor).
-- ================================================================================================

return {
	"folke/flash.nvim",
	event = "VeryLazy",
	opts = {},
	keys = {
		{
			"S",
			mode = { "n", "x", "o" },
			function()
				require("flash").jump()
			end,
			desc = "Flash jump",
		},
		{
			"gs",
			mode = { "n", "x", "o" },
			function()
				require("flash").treesitter()
			end,
			desc = "Flash Treesitter (select a node)",
		},
		{
			"r",
			mode = "o",
			function()
				require("flash").remote()
			end,
			desc = "Remote Flash",
		},
		{
			"R",
			mode = { "o", "x" },
			function()
				require("flash").treesitter_search()
			end,
			desc = "Treesitter Search",
		},
		{
			"<c-s>",
			mode = { "c" },
			function()
				require("flash").toggle()
			end,
			desc = "Toggle Flash Search",
		},
	},
}
