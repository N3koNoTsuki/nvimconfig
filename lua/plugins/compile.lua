-- Compiler le projet (Espace k), façon « M-x compile » d'Emacs : voir lua/util/compile.lua
--   Espace k   : compiler (commande pré-remplie, modifiable, retenue par projet)
--   Espace K   : recompiler sans question     Espace k w : surveillance on/off
--   Espace k t : choisir une cible            Espace k c : arrêter
local function c(fn)
	return function()
		require("util.compile")[fn]()
	end
end

-- :Compile [commande] (sans argument : comme Espace k) et :Recompile
vim.api.nvim_create_user_command("Compile", function(o)
	local compile = require("util.compile")
	if o.args == "" then
		return compile.prompt()
	end
	local p = require("util.project").detect()
	compile.remember(p.root, o.args)
	compile.run(o.args, p.root, { main = p.main })
end, { nargs = "*", complete = "shellcmdline", desc = "Compiler le projet" })
vim.api.nvim_create_user_command("Recompile", c("recompile"), { desc = "Recompiler (dernière commande)" })

return {
	{
		"stevearc/overseer.nvim",
		keys = {
			{ "<leader>k", c("prompt"), desc = "Compiler le projet…" },
			{ "<leader>K", c("recompile"), desc = "Recompiler (sans question)" },
			{ "<leader>kh", c("history"), desc = "Historique des compilations" },
			{ "<leader>kt", c("pick_target"), desc = "Choisir une cible et la lancer" },
			{ "<leader>kw", c("toggle_watch"), desc = "Surveillance (compile à l'enregistrement)" },
			{ "<leader>kc", c("stop"), desc = "Arrêter la compilation" },
			{ "<leader>ko", c("toggle_output"), desc = "Sortie de la compilation" },
			{ "<leader>ob", c("prompt"), desc = "Compiler le projet…" },
		},
	},
}
