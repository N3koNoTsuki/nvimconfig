-- ================================================================================================
-- TITLE : auto-commands
-- ABOUT : automatically run code on defined events (e.g. save, yank)
-- ================================================================================================
local on_attach = require("utils.lsp").on_attach

-- Restore last cursor position when reopening a file
local last_cursor_group = vim.api.nvim_create_augroup("LastCursorGroup", {})
vim.api.nvim_create_autocmd("BufReadPost", {
	group = last_cursor_group,
	callback = function()
		local mark = vim.api.nvim_buf_get_mark(0, '"')
		local lcount = vim.api.nvim_buf_line_count(0)
		if mark[1] > 0 and mark[1] <= lcount then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- Highlight the yanked text for 200ms
local highlight_yank_group = vim.api.nvim_create_augroup("HighlightYank", {})
vim.api.nvim_create_autocmd("TextYankPost", {
	group = highlight_yank_group,
	pattern = "*",
	callback = function()
		vim.hl.on_yank({
			higroup = "IncSearch",
			timeout = 200,
		})
	end,
})

-- format on save using efm langserver and configured formatters
-- not for C/C++ : clang-format's default style rewrites the code (short functions on one line...),
-- format those by hand with <leader>cf
local no_format_on_save = { c = true, cpp = true }
local lsp_fmt_group = vim.api.nvim_create_augroup("FormatOnSaveGroup", {})
vim.api.nvim_create_autocmd("BufWritePre", {
	group = lsp_fmt_group,
	callback = function(args)
		-- notebooks : prettier and the trim would rewrite the cells of the .ipynb
		if vim.api.nvim_buf_get_name(args.buf):find("%.ipynb$") then
			return
		end
		require("mini.trailspace").trim()
		if no_format_on_save[vim.bo[args.buf].filetype] then
			return
		end
		local efm = vim.lsp.get_clients({ name = "efm", bufnr = args.buf })
		if vim.tbl_isempty(efm) then
			return
		end
		-- synchronous : an async format lands after the write, on a buffer that may have changed since
		vim.lsp.buf.format({ name = "efm", bufnr = args.buf, timeout_ms = 2000 })
	end,
})

vim.keymap.set({ "n", "x" }, "<leader>cf", function()
	vim.lsp.buf.format({ name = "efm", timeout_ms = 2000 })
end, { desc = "Format file / selection (efm)" })

-- on attach function shortcuts
local lsp_on_attach_group = vim.api.nvim_create_augroup("LspMappings", {})
vim.api.nvim_create_autocmd("LspAttach", {
	group = lsp_on_attach_group,
	callback = on_attach,
})

-- custom options for text/markdown files
local markdown_options = vim.api.nvim_create_augroup("MardownOptions", {})
vim.api.nvim_create_autocmd("FileType", {
	group = markdown_options,
	pattern = { "markdown", "text", "gitcommit" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.linebreak = true
		vim.opt_local.relativenumber = false
		vim.opt_local.number = false
		vim.opt_local.cursorline = false
		vim.opt_local.colorcolumn = ""
		vim.opt_local.signcolumn = "no"
	end,
})

-- sky blue cursor (re-applied after every colorscheme change)
local cursor_color_group = vim.api.nvim_create_augroup("CursorColor", {})
vim.api.nvim_create_autocmd("ColorScheme", {
	group = cursor_color_group,
	callback = function()
		vim.api.nvim_set_hl(0, "Cursor", { fg = "#1a1b26", bg = "#87ceeb" })
		vim.api.nvim_set_hl(0, "lCursor", { fg = "#1a1b26", bg = "#87ceeb" })
	end,
})

-- clangd project file for C folders (lua/utils/compiledb.lua)
require("utils.compiledb").setup()
