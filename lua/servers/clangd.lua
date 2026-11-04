-- ================================================================================================
-- TITLE : clangd (C/C++ Language Server) LSP Setup
-- LINKS :
--   > website: https://clangd.llvm.org/
-- ================================================================================================

--- @param capabilities table LSP client capabilities (typically from nvim-cmp or similar)
--- @return nil
return function(capabilities)
	local compiledb = require("utils.compiledb")

	vim.lsp.config("clangd", {
		capabilities = capabilities,
		-- a function, to give each project its own generated compile_commands.json
		cmd = function(dispatchers, config)
			local cmd = {
				"clangd",
				"--offset-encoding=utf-16",
				"--background-index",
				"--clang-tidy",
				"--header-insertion=iwyu",
				"--completion-style=detailed",
			}
			vim.list_extend(cmd, compiledb.args_for(config.root_dir))
			return vim.lsp.rpc.start(cmd, dispatchers, { cwd = config.cmd_cwd or config.root_dir, env = config.cmd_env })
		end,
		root_dir = function(bufnr, on_dir)
			local file = vim.api.nvim_buf_get_name(bufnr)
			if file ~= "" then
				on_dir(compiledb.prepare(vim.fs.dirname(file)))
			end
		end,
		filetypes = { "c", "cpp", "objc", "objcpp" },
	})
end
