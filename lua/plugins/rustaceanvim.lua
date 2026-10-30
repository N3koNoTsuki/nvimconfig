-- ================================================================================================
-- TITLE : rustaceanvim
-- ABOUT : A heavily modified fork of rust-tools.nvim
-- LINKS :
--   > github : https://github.com/mrcjkb/rustaceanvim
-- ================================================================================================

local on_attach = require("utils.lsp").on_attach

local get_codelldb_adapter = function()
	local extension_path = vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/"
	local codelldb_path = extension_path .. "adapter/codelldb"
	if vim.fn.executable(codelldb_path) == 0 then
		return nil
	end
	local liblldb_path = extension_path .. "lldb/lib/liblldb.so"
	local cfg = require("rustaceanvim.config")
	return cfg.get_codelldb_adapter(codelldb_path, liblldb_path)
end

local config = function()
	local settings = {
		tools = {
			hover_actions = {
				auto_focus = true,
			},
		},
		server = {
			on_attach = on_attach,
			settings = {
				["rust-analyzer"] = {
					cargo = {
						allFeatures = true,
					},
				},
			},
		},
		dap = {},
	}
	local ok, adapter = pcall(get_codelldb_adapter)
	if ok and adapter then
		settings.dap.adapter = adapter
	end
	vim.g.rustaceanvim = settings
end

return {
	"mrcjkb/rustaceanvim",
	version = "^6",
	lazy = false,
	config = config,
}
