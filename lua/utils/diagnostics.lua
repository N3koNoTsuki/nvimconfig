local M = {}

local diagnostic_signs = {
	Error = " ",
	Warn = " ",
	Hint = "",
	Info = "",
}

M.setup = function()
	vim.diagnostic.config({
		-- lsp_lines (built into Neovim since 0.11): the full message on virtual lines under the code
		virtual_lines = true,
		virtual_text = false,
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = diagnostic_signs.Error,
				[vim.diagnostic.severity.WARN] = diagnostic_signs.Warn,
				[vim.diagnostic.severity.INFO] = diagnostic_signs.Info,
				[vim.diagnostic.severity.HINT] = diagnostic_signs.Hint,
			},
		},
	})

	-- virtual lines are long on a file full of errors : toggle back to short text at the end of the line
	vim.keymap.set("n", "<leader>dl", function()
		local lines = not vim.diagnostic.config().virtual_lines
		vim.diagnostic.config({ virtual_lines = lines, virtual_text = not lines })
	end, { desc = "Toggle diagnostics: virtual lines / end of line" })
end

return M
