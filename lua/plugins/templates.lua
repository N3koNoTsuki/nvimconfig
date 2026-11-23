-- Modèles : nouveau projet (:NideNew, Espace f N) et squelettes des nouveaux fichiers.
-- Logique : lua/util/templates.lua ; fichiers modèles : templates/
-- Désactiver les squelettes : vim.g.nide_skeletons = false
local T = function()
	return require("util.templates")
end

vim.api.nvim_create_user_command("NideNew", function(o)
	T().command(o)
end, {
	nargs = "*",
	complete = function(arg, line)
		return T().complete(arg, line)
	end,
	desc = "Nouveau projet (C, C++, Python, Rust, LaTeX, notebook)",
})

vim.api.nvim_create_user_command("NideSkeleton", function()
	T().skeleton_command()
end, { desc = "Insérer le squelette dans le fichier vide" })

-- squelette à la création d'un fichier (pas pour les fichiers existants)
vim.api.nvim_create_autocmd("BufNewFile", {
	group = vim.api.nvim_create_augroup("nide_skeletons", { clear = true }),
	pattern = { "*.c", "*.cpp", "*.cc", "*.cxx", "*.h", "*.hpp", "*.hh", "*.hxx", "*.py", "*.sh", "*.bash", "Makefile", "makefile", "GNUmakefile" },
	callback = function(a)
		T().on_new_file(a)
	end,
})

-- (pas de `init` ici : il remplacerait celui de snacks.lua)
return {
	{
		"folke/snacks.nvim",
		keys = {
			{ "<leader>fN", function() T().wizard() end, desc = "Nouveau projet" },
		},
	},
}
