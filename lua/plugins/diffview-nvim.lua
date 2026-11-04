-- ================================================================================================
-- TITLE : diffview.nvim
-- ABOUT : side-by-side git diff (old version left, working file right) with a panel listing the
--         changed files, and the commit history of a file or of the current TD folder of the
--         mono-repo. Keymaps under <leader>h (see lua/utils/git.lua).
-- LINKS :
--   > github : https://github.com/sindrets/diffview.nvim
-- ================================================================================================

local git = function()
	return require("utils.git")
end

return {
	"sindrets/diffview.nvim",
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
	keys = {
		{
			"<leader>hD",
			function()
				git().diff()
			end,
			desc = "Diff of the whole repo (diffview)",
		},
		{
			"<leader>hf",
			function()
				git().history("file")
			end,
			desc = "History of the current file",
		},
		{
			"<leader>hF",
			function()
				git().history("scope")
			end,
			desc = "History of the current TD",
		},
		{
			"<leader>hj",
			function()
				git().jump()
			end,
			desc = "Leave the diff, jump to the real file",
		},
		{
			"<leader>hq",
			function()
				git().close()
			end,
			desc = "Close the diff",
		},
	},
	opts = {
		enhanced_diff_hl = true,
		view = {
			default = { layout = "diff2_horizontal" }, -- two panes side by side
			file_history = { layout = "diff2_horizontal" },
		},
		file_panel = {
			listing_style = "tree",
			win_config = { position = "left", width = 30 },
		},
	},
}
