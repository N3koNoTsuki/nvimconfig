-- ================================================================================================
-- TITLE : marksman (Markdown Language Server) LSP Setup
-- LINKS :
--   > github: https://github.com/artempyanykh/marksman
-- ================================================================================================

--- @param capabilities table LSP client capabilities (typically from nvim-cmp or similar)
--- @return nil
return function(capabilities)
	vim.lsp.config("marksman", {
		capabilities = capabilities,
		filetypes = { "markdown", "markdown.mdx" },
	})
end
