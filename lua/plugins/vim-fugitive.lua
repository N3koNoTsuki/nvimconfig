-- ================================================================================================
-- TITLE : vim-fugitive
-- ABOUT : A Git wrapper plugin for Vim and Neovim. Provides powerful Git integration and commands.
--         :Gvdiffsplit = diff of the current file in two vertical panes, in the same tab : the
--         right pane IS the real file (editable), the left one the index / HEAD version.
-- LINKS :
--   > github : https://github.com/tpope/vim-fugitive
-- ================================================================================================

return {
	"tpope/vim-fugitive",
	lazy = false, -- :Git / :G must exist without pressing a key first
	keys = {
		{ "<leader>hg", "<Cmd>Git<CR>", desc = "Git status (fugitive)" },
		{ "<leader>hv", "<Cmd>Gvdiffsplit<CR>", desc = "Diff current file vs index (split)" },
		{ "<leader>hV", "<Cmd>Gvdiffsplit HEAD<CR>", desc = "Diff current file vs last commit (split)" },
		{ "<leader>hc", "<Cmd>Git commit<CR>", desc = "Git commit" },
	},
}
