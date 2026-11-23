-- Plugins propres à un langage (installés et chargés seulement si leur module est activé,
-- voir lua/nide/modules.lua)
local function enabled(name)
	return function()
		return require("nide.modules").plugin_enabled(name)
	end
end

return {
	-- LaTeX : compilation continue, aperçu PDF synchronisé, objets texte (\ll, \lv… sous <localleader> = \)
	{
		"lervag/vimtex",
		enabled = enabled("lervag/vimtex"),
		lazy = false, -- vimtex se charge lui-même sur les fichiers .tex (ne pas le charger en différé)
		init = function()
			-- Visionneuse : zathura si présent, sinon l'application PDF par défaut
			vim.g.vimtex_view_method = vim.fn.executable("zathura") == 1 and "zathura" or "general"
			-- Compilateur : latexmk, sinon tectonic, sinon désactivé (pas d'erreur à l'ouverture)
			if vim.fn.executable("latexmk") == 1 then
				vim.g.vimtex_compiler_method = "latexmk"
			elseif vim.fn.executable("tectonic") == 1 then
				vim.g.vimtex_compiler_method = "tectonic"
			else
				vim.g.vimtex_compiler_enabled = 0
			end
			vim.g.vimtex_quickfix_open_on_warning = 0 -- la liste ne s'ouvre que pour les erreurs
			vim.g.vimtex_mappings_disable = { n = { "K" } } -- K reste la documentation LSP (texlab)
		end,
	},

	-- Go : configuration delve pour nvim-dap (utilisée aussi par neotest-golang pour <leader>td)
	{
		"leoluz/nvim-dap-go",
		enabled = enabled("leoluz/nvim-dap-go"),
		ft = "go",
		dependencies = { "mfussenegger/nvim-dap" },
		opts = {},
	},
}
