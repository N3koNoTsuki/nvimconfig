-- Débogueur (points d'arrêt, pas à pas, variables) + lanceur de tests
local function dbg(fn)
	return function()
		require("util.debug")[fn]()
	end
end

-- Plugins d'un module (lua/nide/modules.lua) : installés et chargés seulement s'il est activé
local function enabled(name)
	return function()
		return require("nide.modules").plugin_enabled(name)
	end
end

local function dap(fn, ...)
	local args = { ... }
	return function()
		require("dap")[fn](unpack(args))
	end
end

return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			{ "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" }, opts = {} },
			{ "theHamsta/nvim-dap-virtual-text", opts = {} }, -- valeurs des variables dans le code
			{
				"jay-babu/mason-nvim-dap.nvim",
				dependencies = { "mason-org/mason.nvim" },
				-- handlers : configure automatiquement codelldb (C/C++/Rust) et debugpy (Python) ;
				-- Go est configuré par nvim-dap-go (voir lang.lua), delve est installé par lsp.lua si Go est présent
				opts = {
					-- codelldb et debugpy sont installés par mason-tool-installer (lsp.lua) ;
					-- les demander ici aussi lance deux installations en même temps
					-- (« Package is already installing » sur une installation neuve)
					ensure_installed = {},
					automatic_installation = false,
					handlers = { delve = function() end },
				},
			},
		},
		keys = {
			-- Touches F façon VS Code
			-- F5 : déboguer le fichier courant (compilé si besoin, voir lua/util/debug.lua) ou continuer
			{ "<F5>", dbg("continue"), desc = "Débogueur : lancer le fichier / continuer" },
			{ "<F9>", dap("toggle_breakpoint"), desc = "Point d'arrêt" },
			{ "<F10>", dap("step_over"), desc = "Pas à pas (passer)" },
			{ "<F11>", dap("step_into"), desc = "Pas à pas (entrer)" },
			{ "<S-F11>", dap("step_out"), desc = "Pas à pas (sortir)" },
			{ "<F17>", dap("step_out"), desc = "which_key_ignore" }, -- S-F11 sur certains terminaux
			-- Et les mêmes sous <Espace>d
			{ "<leader>db", dap("toggle_breakpoint"), desc = "Point d'arrêt" },
			{
				"<leader>dB",
				function() require("dap").set_breakpoint(vim.fn.input("Condition : ")) end,
				desc = "Point d'arrêt conditionnel",
			},
			{ "<leader>dc", dap("continue"), desc = "Lancer (choisir la configuration) / continuer" },
			{ "<leader>dA", dbg("start_with_args"), desc = "Déboguer avec des arguments" },
			{ "<leader>dM", function() require("util.debug").make_choice = {} end, desc = "Oublier le choix Makefile" },
			{
				"<leader>dT",
				function()
					local buf = require("dap").session() and require("dap").session().term_buf
					local win = buf and vim.fn.bufwinid(buf) or -1
					if win == -1 then
						return vim.notify("Pas de console de programme ouverte", vim.log.levels.INFO, { title = "Débogueur" })
					end
					vim.api.nvim_set_current_win(win)
					vim.cmd.startinsert()
				end,
				desc = "Console du programme (saisie)",
			},
			{ "<leader>dC", dap("run_to_cursor"), desc = "Aller jusqu'au curseur" },
			{ "<leader>do", dap("step_over"), desc = "Passer (step over)" },
			{ "<leader>di", dap("step_into"), desc = "Entrer (step into)" },
			{ "<leader>dO", dap("step_out"), desc = "Sortir (step out)" },
			{ "<leader>dr", dap("repl.toggle"), desc = "Console (REPL)" },
			{ "<leader>dl", dbg("run_last"), desc = "Relancer la dernière session" },
			{ "<leader>dt", dap("terminate"), desc = "Arrêter" },
			{ "<leader>du", function() require("dapui").toggle() end, desc = "Interface du débogueur" },
			{ "<leader>de", function() require("dapui").eval() end, mode = { "n", "x" }, desc = "Évaluer l'expression" },
		},
		config = function()
			local d, ui = require("dap"), require("dapui")
			-- ouverte au lancement, laissée ouverte à la fin (sortie visible) : voir util.debug
			d.listeners.after.event_initialized.dapui = function() ui.open() end
			require("util.debug").setup()

			vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })
			for name, sign in pairs({
				Stopped = { "\u{f061} ", "DiagnosticWarn", "DapStoppedLine" },
				Breakpoint = { "\u{f111} ", "DiagnosticError" },
				BreakpointCondition = { "\u{f059} ", "DiagnosticError" },
				BreakpointRejected = { "\u{f06a} ", "DiagnosticError" },
				LogPoint = { ".>", "DiagnosticInfo" },
			}) do
				vim.fn.sign_define("Dap" .. name, { text = sign[1], texthl = sign[2], linehl = sign[3], numhl = sign[3] })
			end

			-- Exécutables C/C++ : demande le binaire à lancer
			for _, ft in ipairs({ "c", "cpp" }) do
				d.configurations[ft] = d.configurations[ft] or {}
				table.insert(d.configurations[ft], {
					name = "Lancer un exécutable",
					type = "codelldb",
					request = "launch",
					program = function()
						return vim.fn.input("Exécutable : ", vim.fn.getcwd() .. "/", "file")
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = false,
				})
			end
		end,
	},

	-- Tests unitaires : lancer le test sous le curseur, voir les résultats dans la marge
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-neotest/nvim-nio",
			"nvim-lua/plenary.nvim",
			{ "nvim-neotest/neotest-python", enabled = enabled("nvim-neotest/neotest-python") },
			{ "rouge8/neotest-rust", enabled = enabled("rouge8/neotest-rust") },
			{ "fredrikaverpil/neotest-golang", version = "*", enabled = enabled("fredrikaverpil/neotest-golang") },
		},
		keys = {
			{ "<leader>tr", function() require("neotest").run.run() end, desc = "Lancer le test sous le curseur" },
			{ "<leader>tF", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Lancer les tests du fichier" },
			{ "<leader>tA", function() require("neotest").run.run(vim.uv.cwd()) end, desc = "Lancer tous les tests" },
			{ "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Déboguer le test" },
			{ "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Panneau des tests" },
			{ "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Sortie du test" },
			{ "<leader>tS", function() require("neotest").run.stop() end, desc = "Arrêter les tests" },
		},
		config = function()
			-- adaptateurs des modules activés seulement (Python, Rust, Go)
			local modules, adapters = require("nide.modules"), {}
			if modules.plugin_enabled("nvim-neotest/neotest-python") then
				table.insert(adapters, require("neotest-python"))
			end
			if modules.plugin_enabled("rouge8/neotest-rust") then
				table.insert(adapters, require("neotest-rust"))
			end
			if modules.plugin_enabled("fredrikaverpil/neotest-golang") then
				table.insert(adapters, require("neotest-golang")({}))
			end
			require("neotest").setup({
				adapters = adapters,
				status = { virtual_text = true },
				output = { open_on_run = true },
			})
		end,
	},
}
