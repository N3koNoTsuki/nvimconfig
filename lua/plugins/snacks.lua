-- snacks.nvim : dashboard, explorateur, recherche floue, terminal, lazygit, notifications…
-- https://github.com/folke/snacks.nvim
local function P(name, opts)
	return function()
		Snacks.picker[name](opts)
	end
end

return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	opts = {
		bigfile = { enabled = true },
		quickfile = { enabled = true },
		input = { enabled = true },
		notifier = { enabled = true, timeout = 3000 },
		indent = { enabled = true },
		scope = { enabled = true },
		words = { enabled = true }, -- surligne les autres occurrences du symbole (LSP)
		statuscolumn = { enabled = true },
		explorer = { replace_netrw = true },
		picker = {
			ui_select = true, -- vim.ui.select passe par le picker (branché à UIEnter)
			sources = {
				explorer = { hidden = true, layout = { layout = { position = "left" } } },
				files = { hidden = true },
			},
			win = {
				input = {
					keys = {
						["<C-j>"] = { "list_down", mode = { "i", "n" } },
						["<C-k>"] = { "list_up", mode = { "i", "n" } },
					},
				},
			},
		},
		terminal = { win = { position = "bottom", height = 0.3 } },
		lazygit = {},
		zen = {},
		dashboard = {
			preset = {
				keys = {
					{ icon = "\u{f059} ", key = "?", desc = "Prise en main (tutoriel)", action = ":Tuto" },
					{ icon = "\u{f002} ", key = "f", desc = "Chercher un fichier", action = ":lua Snacks.picker.files()" },
					{ icon = "\u{f15b} ", key = "n", desc = "Nouveau fichier", action = ":ene | startinsert" },
					{ icon = "\u{f0257} ", key = "N", desc = "Nouveau projet", action = ":NideNew" },
					{ icon = "\u{f022} ", key = "g", desc = "Chercher du texte", action = ":lua Snacks.picker.grep()" },
					{ icon = "\u{f1da} ", key = "r", desc = "Fichiers récents", action = ":lua Snacks.picker.recent()" },
					{ icon = "\u{f07b} ", key = "p", desc = "Projets", action = ":lua Snacks.picker.projects()" },
					{ icon = "\u{f021} ", key = "s", desc = "Restaurer la session", section = "session" },
					{ icon = "\u{f07c} ", key = "e", desc = "Explorateur", action = ":lua Snacks.explorer()" },
					{ icon = "\u{f013} ", key = "c", desc = "Configuration", action = ":lua Snacks.picker.files({ cwd = vim.fn.stdpath('config') })" },
					{ icon = "󰒲 ", key = "L", desc = "Plugins", action = ":Lazy" },
					{ icon = "\u{f011} ", key = "q", desc = "Quitter", action = ":qa" },
				},
			},
			-- en-tête = logo de l'intro (lua/nide/intro.lua) ; la taille du logo, les
			-- espacements et ce qui est affiché s'adaptent à la fenêtre à chaque rendu
			sections = function(self)
				return require("nide.intro").layout(self, {
					{ section = "keys", gap = 1, padding = 1 },
					{ icon = "\u{f1da} ", title = "Récents", section = "recent_files", cwd = true, limit = 5, indent = 2, padding = 1 },
					{ section = "startup" },
				})
			end,
		},
	},
	keys = {
		-- Les plus utilisés, juste après Espace
		{ "<leader><space>", P("smart"), desc = "Chercher un fichier (intelligent)" },
		{ "<leader>,", P("buffers"), desc = "Fichiers ouverts" },
		{ "<leader>/", P("grep"), desc = "Chercher du texte (projet)" },
		{ "<leader>:", P("command_history"), desc = "Historique des commandes" },
		{ "<leader>e", function() Snacks.explorer() end, desc = "Explorateur de fichiers" },
		{ "<C-p>", P("files"), desc = "Chercher un fichier" },

		-- f : fichiers
		{ "<leader>ff", P("files"), desc = "Fichiers" },
		{ "<leader>fr", P("recent"), desc = "Récents" },
		{ "<leader>fb", P("buffers"), desc = "Fichiers ouverts" },
		{ "<leader>fp", P("projects"), desc = "Projets" },
		{ "<leader>fc", P("files", { cwd = vim.fn.stdpath("config") }), desc = "Fichiers de config" },
		{ "<leader>fn", "<Cmd>enew<CR>", desc = "Nouveau fichier" },
		{ "<leader>fR", function() Snacks.rename.rename_file() end, desc = "Renommer le fichier" },

		-- s : rechercher
		{ "<leader>sg", P("grep"), desc = "Texte dans le projet" },
		{ "<leader>sw", P("grep_word"), desc = "Mot sous le curseur", mode = { "n", "x" } },
		{ "<leader>sb", P("lines"), desc = "Lignes du fichier" },
		{ "<leader>ss", P("lsp_symbols"), desc = "Symboles du fichier" },
		{ "<leader>sS", P("lsp_workspace_symbols"), desc = "Symboles du projet" },
		{ "<leader>sd", P("diagnostics"), desc = "Diagnostics" },
		{ "<leader>sh", P("help"), desc = "Aide de Neovim" },
		{ "<leader>sk", P("keymaps"), desc = "Tous les raccourcis" },
		{ "<leader>sc", P("commands"), desc = "Commandes" },
		{ "<leader>sm", P("marks"), desc = "Marques" },
		{ "<leader>su", P("undo"), desc = "Historique d'annulation" },
		{ "<leader>sR", P("resume"), desc = "Reprendre la dernière recherche" },
		{ "<leader>sn", function() Snacks.notifier.show_history() end, desc = "Notifications" },

		-- LSP : aller à…
		{ "gd", P("lsp_definitions"), desc = "Aller à la définition" },
		{ "gD", P("lsp_declarations"), desc = "Aller à la déclaration" },
		{ "gr", P("lsp_references"), nowait = true, desc = "Références" },
		{ "gI", P("lsp_implementations"), desc = "Implémentations" },
		{ "gy", P("lsp_type_definitions"), desc = "Définition du type" },
		{ "]]", function() Snacks.words.jump(vim.v.count1) end, desc = "Occurrence suivante" },
		{ "[[", function() Snacks.words.jump(-vim.v.count1) end, desc = "Occurrence précédente" },

		-- g : git
		{ "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
		{ "<leader>gs", P("git_status"), desc = "Fichiers modifiés" },
		{ "<leader>gl", P("git_log"), desc = "Historique (log)" },
		{ "<leader>gf", P("git_log_file"), desc = "Historique du fichier" },
		{ "<leader>gB", function() Snacks.gitbrowse() end, desc = "Ouvrir sur GitHub/GitLab", mode = { "n", "x" } },

		-- Terminal
		{ "<C-/>", function() Snacks.terminal() end, desc = "Terminal", mode = { "n", "t" } },
		{ "<C-_>", function() Snacks.terminal() end, desc = "which_key_ignore", mode = { "n", "t" } },
		{ "<leader>tt", function() Snacks.terminal() end, desc = "Terminal (bas)" },
		{ "<leader>tf", function() Snacks.terminal(nil, { win = { position = "float" } }) end, desc = "Terminal flottant" },

		-- Buffers
		{ "<leader>bd", function() Snacks.bufdelete() end, desc = "Fermer l'onglet" },
		{ "<leader>bo", function() Snacks.bufdelete.other() end, desc = "Fermer les autres" },

		-- Fenêtres
		{ "<leader>wm", function() Snacks.zen.zoom() end, desc = "Agrandir / restaurer" },
		{ "<leader>uz", function() Snacks.zen() end, desc = "Mode zen" },
		{ "<leader>un", function() Snacks.notifier.hide() end, desc = "Masquer les notifications" },
		{ "<leader>uC", P("colorschemes"), desc = "Choisir un thème" },
	},
	init = function()
		require("nide.intro").setup() -- intro animée sur l'écran d'accueil, :NideIntro
		vim.api.nvim_create_autocmd("User", {
			pattern = "VeryLazy",
			callback = function()
				-- u : interrupteurs d'interface (le libellé montre l'état actuel)
				Snacks.toggle.option("wrap", { name = "Retour à la ligne" }):map("<leader>uw")
				Snacks.toggle.option("spell", { name = "Orthographe" }):map("<leader>us")
				Snacks.toggle.option("relativenumber", { name = "Numéros relatifs" }):map("<leader>uL")
				Snacks.toggle.line_number():map("<leader>ul")
				Snacks.toggle.diagnostics():map("<leader>ud")
				Snacks.toggle.inlay_hints():map("<leader>uh")
				Snacks.toggle.indent():map("<leader>ug")
				Snacks.toggle.dim():map("<leader>uD")
				Snacks.toggle.treesitter():map("<leader>uT")
			end,
		})
	end,
}
