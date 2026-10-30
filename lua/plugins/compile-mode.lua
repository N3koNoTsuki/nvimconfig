-- ================================================================================================
-- TITLE : compile-mode.nvim
-- ABOUT : Emacs' M-x compile in Neovim: run a build command, get its output in a *compilation*
--         buffer and jump to the errors (<CR> on a line, ]e / [e from anywhere).
-- LINKS :
--   > github : https://github.com/ej-shafran/compile-mode.nvim
-- ================================================================================================

-- run the command from the directory of the current file (or oil listing), like Emacs'
-- default-directory, so each TD's own Makefile is picked up
local function compile_here()
	local dir = require("oil").get_current_dir()
	if not dir then
		dir = vim.bo.buftype == "" and vim.fn.expand("%:p:h") or vim.fn.getcwd()
	end
	vim.g.compilation_directory = dir
	vim.cmd("Compile")
end

return {
	"ej-shafran/compile-mode.nvim",
	version = "^5.0.0",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ "m00qek/baleia.nvim", tag = "v1.3.0" },
	},
	cmd = { "Compile", "Recompile", "NextError", "PrevError" },
	keys = {
		{ "<leader>k", compile_here, desc = "Compile (from file directory)" },
		{ "<leader>K", "<Cmd>Recompile<CR>", desc = "Recompile" },
		{ "]e", "<Cmd>NextError<CR>", desc = "Next compilation error" },
		{ "[e", "<Cmd>PrevError<CR>", desc = "Previous compilation error" },
	},
	init = function()
		---@type CompileModeOpts
		vim.g.compile_mode = {
			default_command = "make -k ",
			ansi_color = { kind = "render" }, -- keep gcc's colors (needs baleia)
			ask_about_save = false, -- save modified buffers without asking
		}
	end,
}
