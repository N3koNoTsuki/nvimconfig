local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Language Server Protocol (LSP)
require("servers.lua_ls")(capabilities)
require("servers.pyright")(capabilities)
require("servers.jsonls")(capabilities)
require("servers.bashls")(capabilities)
require("servers.clangd")(capabilities)
require("servers.yamlls")(capabilities)
require("servers.marksman")(capabilities)
require("servers.taplo")(capabilities)
require("servers.autotools_ls")(capabilities)
-- NOTE: rust-analyzer is configured by rustaceanvim (see plugins/rustaceanvim.lua)

-- Linters & Formatters
require("servers.efm-langserver")(capabilities)

vim.lsp.enable({
	"lua_ls",
	"pyright",
	"jsonls",
	"bashls",
	"clangd",
	"yamlls",
	"marksman",
	"taplo",
	"autotools_ls",
	"efm",
})
