-- ================================================================================================
-- TITLE : oil.nvim
-- ABOUT : edit the filesystem like a buffer, with an `ll`-like listing (eza -l --icons --git).
--         Opened automatically on the cwd when nvim is started without arguments.
-- LINKS :
--   > github : https://github.com/stevearc/oil.nvim
--   > github : https://github.com/refractalize/oil-git-status.nvim
-- ================================================================================================

return {
	{
		"stevearc/oil.nvim",
		lazy = false,
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("oil").setup({
				default_file_explorer = true,
				columns = {
					"permissions",
					"size",
					"mtime",
					"icon",
				},
				win_options = {
					signcolumn = "yes:2", -- room for oil-git-status (index + worktree)
				},
				view_options = {
					show_hidden = true, -- like dotfiles = false in nvim-tree
				},
			})

			vim.keymap.set("n", "-", "<Cmd>Oil<CR>", { desc = "Open parent directory (oil)" })

			-- `nvim` without arguments (and not reading stdin) -> listing of the cwd
			local oil_startup_group = vim.api.nvim_create_augroup("OilStartup", {})
			vim.api.nvim_create_autocmd("StdinReadPre", {
				group = oil_startup_group,
				callback = function()
					vim.g.read_from_stdin = true
				end,
			})
			vim.api.nvim_create_autocmd("VimEnter", {
				group = oil_startup_group,
				nested = true, -- let oil's BufReadCmd fire for the oil:// buffer
				callback = function()
					if vim.fn.argc() == 0 and not vim.g.read_from_stdin then
						require("oil").open(vim.fn.getcwd())
					end
				end,
			})

			-- :bd on the last buffer -> back to the listing instead of an empty [No Name]
			local exiting = false
			vim.api.nvim_create_autocmd("VimLeavePre", {
				group = oil_startup_group,
				callback = function()
					exiting = true
				end,
			})
			vim.api.nvim_create_autocmd("BufDelete", {
				group = oil_startup_group,
				callback = function(args)
					local file = args.file
					local dir = (file ~= "" and not file:match("^oil://")) and vim.fn.fnamemodify(file, ":p:h")
						or vim.fn.getcwd()
					vim.schedule(function()
						if exiting then
							return
						end
						local buf = vim.api.nvim_get_current_buf()
						local is_empty = vim.api.nvim_buf_get_name(buf) == ""
							and vim.bo[buf].buftype == ""
							and not vim.bo[buf].modified
							and vim.api.nvim_buf_line_count(buf) == 1
							and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
						if is_empty then
							require("oil").open(dir)
						end
					end)
				end,
			})
		end,
	},
	{
		"refractalize/oil-git-status.nvim",
		dependencies = { "stevearc/oil.nvim" },
		config = true,
	},
}
