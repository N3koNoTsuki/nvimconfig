return {
	"rcarriga/nvim-dap-ui",
	dependencies = {
		"nvim-neotest/nvim-nio",
		{
			"mfussenegger/nvim-dap",
			config = function()
				local dap, dapui = require("dap"), require("dapui")
				dap.listeners.before.attach.dapui_config = function()
					dapui.open()
				end
				dap.listeners.before.launch.dapui_config = function()
					dapui.open()
				end
				dap.listeners.before.event_terminated.dapui_config = function()
					dapui.close()
				end
				dap.listeners.before.event_exited.dapui_config = function()
					dapui.close()
				end

				-- C/C++ debugging via codelldb (installed by mason)
				dap.adapters.codelldb = {
					type = "executable",
					command = vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/adapter/codelldb",
				}
				dap.configurations.c = {
					{
						name = "Launch executable",
						type = "codelldb",
						request = "launch",
						program = function()
							return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
						end,
						args = function()
							return vim.split(vim.fn.input("Arguments: "), " ", { trimempty = true })
						end,
						cwd = "${workspaceFolder}",
						stopOnEntry = false,
					},
				}
				dap.configurations.cpp = dap.configurations.c
			end,
		},
	},
	config = function()
		require("dapui").setup()
	end,
}
