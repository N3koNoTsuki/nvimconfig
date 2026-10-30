-- ================================================================================================
-- TITLE : autotools_ls (Makefile / Autotools Language Server) LSP Setup
-- LINKS :
--   > github: https://github.com/Freed-Wu/autotools-language-server
-- ================================================================================================

--- @param capabilities table LSP client capabilities (typically from nvim-cmp or similar)
--- @return nil
return function(capabilities)
	vim.lsp.config("autotools_ls", {
		capabilities = capabilities,
		filetypes = { "make", "automake", "config" },
	})
end
