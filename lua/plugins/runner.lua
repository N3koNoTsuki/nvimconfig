-- Exécuter / compiler comme dans un IDE
--   F6 / Espace r : lancer le fichier courant (voir lua/util/runner.lua)
--   Espace o …    : tâches du projet (make, cargo, npm…) avec overseer.nvim
-- https://github.com/stevearc/overseer.nvim
local function run(fn)
	return function()
		require("util.runner")[fn]()
	end
end

-- Composant overseer maison : si la tâche a rempli la quickfix, ouvre le panneau Problèmes
package.preload["overseer.component.nide_trouble"] = function()
	return {
		desc = "Ouvre Trouble (quickfix) si la sortie contient des erreurs",
		constructor = function()
			return {
				on_complete = function(_, task)
					vim.schedule(function()
						local qf = vim.fn.getqflist({ context = 0, items = 0 })
						if qf.context ~= task.id then
							return
						end
						for _, item in ipairs(qf.items) do
							if item.valid == 1 then
								return vim.cmd("Trouble qflist open")
							end
						end
					end)
				end,
			}
		end,
	}
end

-- :Run [arguments] (pas de `init` ici : il remplacerait celui de snacks.lua)
vim.api.nvim_create_user_command("Run", function(o)
	require("util.runner").run(o.args)
end, { nargs = "*", complete = "file", desc = "Lancer le fichier courant" })

return {
	-- Lancer le fichier courant (terminal Snacks)
	{
		"folke/snacks.nvim",
		keys = {
			{ "<F6>", run("run"), desc = "Lancer le fichier", mode = { "n", "i", "t" } },
			{ "<leader>r", run("run"), desc = "Lancer le fichier" },
			{ "<leader>R", run("run_with_args"), desc = "Lancer avec des arguments" },
			{ "<leader>or", run("toggle"), desc = "Sortie du dernier lancement" },
		},
	},

	-- Gestionnaire de tâches
	{
		"stevearc/overseer.nvim",
		cmd = { "OverseerRun", "OverseerToggle", "OverseerOpen", "OverseerShell", "OverseerTaskAction" },
		keys = {
			{ "<leader>oo", "<Cmd>OverseerRun<CR>", desc = "Lancer une tâche" },
			{ "<leader>ot", "<Cmd>OverseerToggle<CR>", desc = "Panneau des tâches" },
			-- Espace o b : alias de Espace k (lua/plugins/compile.lua)
			{
				"<leader>ol",
				function()
					local overseer = require("overseer")
					local tasks = overseer.list_tasks({
						status = { "SUCCESS", "FAILURE", "CANCELED" },
						sort = require("overseer.task_list").sort_finished_recently,
					})
					if #tasks == 0 then
						return vim.notify("Aucune tâche terminée à relancer", vim.log.levels.WARN)
					end
					overseer.run_action(tasks[1], "restart")
				end,
				desc = "Relancer la dernière tâche",
			},
			{ "<leader>os", "<Cmd>OverseerShell<CR>", desc = "Commande shell (en tâche)" },
			{ "<leader>oa", "<Cmd>OverseerTaskAction<CR>", desc = "Action sur une tâche" },
			{ "<leader>oq", "<Cmd>Trouble qflist toggle<CR>", desc = "Erreurs de compilation (quickfix)" },
		},
		opts = {
			-- Sortie dans un buffer normal : les longues lignes d'erreur ne sont pas coupées
			-- (un terminal les replie à sa largeur, ce qui casse la lecture des erreurs)
			output = { use_terminal = false },
			task_list = { direction = "bottom" },
			component_aliases = {
				-- Toutes les tâches : sortie affichée, erreurs (format gcc, cargo…) → quickfix → Trouble
				default = {
					{ "open_output", on_start = "always", direction = "dock" },
					{ "on_output_quickfix", items_only = true, tail = false },
					"nide_trouble",
					"on_exit_set_status",
					"on_complete_notify",
					{ "on_complete_dispose", require_view = { "SUCCESS", "FAILURE" } },
				},
			},
		},
		config = function(_, opts)
			local overseer = require("overseer")
			overseer.setup(opts)
			-- « make » tout court (cible par défaut), marqué BUILD (Espace o o)
			overseer.register_template({
				name = "make",
				tags = { "BUILD" },
				priority = 40,
				condition = {
					callback = function(search)
						return vim.fs.find({ "Makefile", "makefile", "GNUmakefile" }, { upward = true, path = search.dir })[1] ~= nil
					end,
				},
				builder = function()
					local mk = vim.fs.find({ "Makefile", "makefile", "GNUmakefile" }, { upward = true, path = vim.fn.getcwd() })[1]
					return { cmd = { "make" }, cwd = mk and vim.fs.dirname(mk) or nil }
				end,
			})
		end,
	},
}
