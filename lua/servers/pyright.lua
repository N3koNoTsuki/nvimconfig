-- ================================================================================================
-- TITLE : pyright (Python Language Server) LSP Setup
-- LINKS :
--   > github: https://github.com/microsoft/pyright
-- ================================================================================================

--- @param capabilities table LSP client capabilities (typically from nvim-cmp or similar)
--- @return nil This function doesn't return a value, it configures the LSP server
return function(capabilities)
	vim.lsp.config('pyright', {
		capabilities = capabilities,
		-- resolve the imports with the project's .venv, even when it isn't activated
		before_init = function(_, config)
			local venv = vim.env.VIRTUAL_ENV
				or vim.fs.find(".venv", { path = config.root_dir or vim.fn.getcwd(), upward = true, type = "directory" })[1]
			if venv then
				config.settings.python = { pythonPath = venv .. "/bin/python" }
			end
		end,
		settings = {
			pyright = {
				disableOrganizeImports = false,
				analysis = {
					useLibraryCodeForTypes = true,
					autoSearchPaths = true,
					diagnosticMode = "workspace",
					autoImportCompletions = true,
				},
			},
		},
	})
end
