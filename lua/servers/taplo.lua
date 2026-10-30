-- ================================================================================================
-- TITLE : taplo (TOML Language Server) LSP Setup
-- ABOUT : used for Cargo.toml, pyproject.toml, etc.
-- LINKS :
--   > github: https://github.com/tamasfe/taplo
-- ================================================================================================

--- @param capabilities table LSP client capabilities (typically from nvim-cmp or similar)
--- @return nil
return function(capabilities)
	vim.lsp.config("taplo", {
		capabilities = capabilities,
		filetypes = { "toml" },
	})
end
