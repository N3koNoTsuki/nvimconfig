-- ================================================================================================
-- TITLE : gitsigns.nvim
-- LINKS :
--   > github : https://github.com/lewis6991/gitsigns.nvim
-- ABOUT : deep buffer integration for git.
-- ================================================================================================

return {
	"lewis6991/gitsigns.nvim",
	opts = {
		on_attach = function(bufnr)
			local gs = require("gitsigns")
			local function map(mode, lhs, rhs, desc)
				vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
			end

			-- in a diff window ]c / [c stay the native "next / previous change"
			map("n", "]h", function()
				gs.nav_hunk("next")
			end, "Next git hunk")
			map("n", "[h", function()
				gs.nav_hunk("prev")
			end, "Previous git hunk")

			map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
			map("n", "<leader>hs", gs.stage_hunk, "Stage / unstage hunk")
			map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
			map("x", "<leader>hs", function()
				gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
			end, "Stage selected lines")
			map("x", "<leader>hr", function()
				gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
			end, "Reset selected lines")
			map("n", "<leader>hS", gs.stage_buffer, "Stage the whole file")
			map("n", "<leader>hb", function()
				gs.blame_line({ full = true })
			end, "Blame line")
			map("n", "<leader>hB", "<Cmd>Gitsigns blame<CR>", "Blame the whole file")
		end,
	},
}
