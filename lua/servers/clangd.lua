-- ================================================================================================
-- TITLE : clangd (C/C++ Language Server) LSP Setup
-- LINKS :
--   > website: https://clangd.llvm.org/
-- ================================================================================================

--- @param capabilities table LSP client capabilities (typically from nvim-cmp or similar)
--- @return nil
return function(capabilities)
	vim.lsp.config("clangd", {
		capabilities = capabilities,
		cmd = {
			"clangd",
			"--offset-encoding=utf-16",
			"--background-index",
			"--clang-tidy",
			"--header-insertion=iwyu",
			"--completion-style=detailed",
		},
		filetypes = { "c", "cpp", "objc", "objcpp" },
	})
end
