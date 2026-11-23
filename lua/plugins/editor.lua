return {
	-- Sauter n'importe où à l'écran : s + 2 lettres + étiquette
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = { modes = { char = { jump_labels = true } } },
		keys = {
			{ "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Sauter (flash)" },
			{ "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Sélectionner un bloc (flash)" },
			{ "r", mode = "o", function() require("flash").remote() end, desc = "Action à distance" },
			{ "<C-s>", mode = "c", function() require("flash").toggle() end, desc = "Flash dans la recherche" },
		},
	},

	-- Petits modules mini.nvim
	{ "nvim-mini/mini.ai", event = "VeryLazy", opts = { n_lines = 500 } }, -- objets texte : af, aa, iq, ib…
	{ "nvim-mini/mini.pairs", event = "InsertEnter", opts = {} }, -- ferme ( [ { " automatiquement
	{ "nvim-mini/mini.move", event = "VeryLazy", opts = {} }, -- Alt+hjkl déplace lignes / sélection
	{
		"nvim-mini/mini.surround",
		event = "VeryLazy",
		opts = {
			mappings = {
				add = "gsa", delete = "gsd", replace = "gsr", find = "gsf",
				find_left = "gsF", highlight = "gsh", update_n_lines = "gsn",
			},
		},
	},

	-- Multi-curseurs, comme Ctrl+D dans VS Code
	{
		"jake-stewart/multicursor.nvim",
		branch = "1.0",
		event = "VeryLazy",
		config = function()
			local mc = require("multicursor-nvim")
			mc.setup()
			local map = vim.keymap.set
			map({ "n", "x" }, "<C-n>", function() mc.matchAddCursor(1) end, { desc = "Curseur sur l'occurrence suivante" })
			map({ "n", "x" }, "<C-S-n>", function() mc.matchSkipCursor(1) end, { desc = "Sauter l'occurrence" })
			map({ "n", "x" }, "<M-Down>", function() mc.lineAddCursor(1) end, { desc = "Curseur en dessous" })
			map({ "n", "x" }, "<M-Up>", function() mc.lineAddCursor(-1) end, { desc = "Curseur au-dessus" })
			map({ "n", "x" }, "<leader>cM", function() mc.matchAllAddCursors() end, { desc = "Curseur sur toutes les occurrences" })
			map("n", "<C-LeftMouse>", mc.handleMouse)
			map("n", "<C-LeftDrag>", mc.handleMouseDrag)
			map("n", "<C-LeftRelease>", mc.handleMouseRelease)
			mc.addKeymapLayer(function(layer)
				layer({ "n", "x" }, "<Left>", mc.prevCursor)
				layer({ "n", "x" }, "<Right>", mc.nextCursor)
				layer({ "n", "x" }, "<leader>x", mc.deleteCursor)
				layer("n", "<Esc>", function()
					if not mc.cursorsEnabled() then
						mc.enableCursors()
					else
						mc.clearCursors()
					end
				end)
			end)
		end,
	},

	-- Git dans la marge : +, ~, _ et actions sur les blocs
	{
		"lewis6991/gitsigns.nvim",
		event = "BufReadPre",
		opts = {
			current_line_blame = false,
			on_attach = function(buf)
				local gs = require("gitsigns")
				local function map(mode, l, r, desc)
					vim.keymap.set(mode, l, r, { buffer = buf, desc = desc })
				end
				map("n", "]h", function() gs.nav_hunk("next") end, "Bloc modifié suivant")
				map("n", "[h", function() gs.nav_hunk("prev") end, "Bloc modifié précédent")
				map("n", "<leader>ghp", gs.preview_hunk_inline, "Aperçu du bloc")
				map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stager le bloc")
				map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Annuler le bloc")
				map("n", "<leader>ghS", gs.stage_buffer, "Stager le fichier")
				map("n", "<leader>ghR", gs.reset_buffer, "Annuler tout le fichier")
				map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame de la ligne")
				map("n", "<leader>ub", gs.toggle_current_line_blame, "Blame en continu (on/off)")
				map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Bloc git")
			end,
		},
	},

	-- Diff côte à côte de tout le projet
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewFileHistory" },
		keys = {
			{ "<leader>gd", "<Cmd>DiffviewOpen<CR>", desc = "Diff du projet" },
			{ "<leader>gD", "<Cmd>DiffviewClose<CR>", desc = "Fermer le diff" },
			{ "<leader>gH", "<Cmd>DiffviewFileHistory %<CR>", desc = "Historique du fichier (diff)" },
		},
		opts = {},
	},

	-- Panneau des problèmes, références, symboles
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		opts = { focus = true },
		keys = {
			{ "<leader>xx", "<Cmd>Trouble diagnostics toggle<CR>", desc = "Problèmes du projet" },
			{ "<leader>xX", "<Cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Problèmes du fichier" },
			{ "<leader>xq", "<Cmd>Trouble qflist toggle<CR>", desc = "Liste quickfix" },
			{ "<leader>xl", "<Cmd>Trouble loclist toggle<CR>", desc = "Liste locale" },
			{ "<leader>cs", "<Cmd>Trouble symbols toggle focus=false win.position=right<CR>", desc = "Symboles (panneau)" },
			{ "<leader>cR", "<Cmd>Trouble lsp toggle focus=false win.position=right<CR>", desc = "Références / définitions (panneau)" },
		},
	},

	-- Plan du fichier (fonctions, classes) dans un panneau
	{
		"stevearc/aerial.nvim",
		cmd = "AerialToggle",
		keys = { { "<leader>co", "<Cmd>AerialToggle! right<CR>", desc = "Plan du fichier (outline)" } },
		opts = { layout = { min_width = 30 }, show_guides = true, filter_kind = false },
	},

	-- TODO / FIXME / HACK surlignés et listables
	{
		"folke/todo-comments.nvim",
		event = "BufReadPost",
		opts = {},
		keys = {
			{ "]t", function() require("todo-comments").jump_next() end, desc = "TODO suivant" },
			{ "[t", function() require("todo-comments").jump_prev() end, desc = "TODO précédent" },
			{ "<leader>st", function() Snacks.picker.todo_comments() end, desc = "Tous les TODO" },
		},
	},

	-- Rechercher / remplacer dans tout le projet (avec aperçu)
	{
		"MagicDuck/grug-far.nvim",
		cmd = "GrugFar",
		opts = { headerMaxWidth = 80 },
		keys = {
			{ "<leader>sr", function() require("grug-far").open() end, mode = { "n", "x" }, desc = "Remplacer dans le projet" },
			{
				"<leader>sW",
				function() require("grug-far").open({ prefills = { search = vim.fn.expand("<cword>") } }) end,
				desc = "Remplacer le mot sous le curseur (projet)",
			},
		},
	},

	-- Sessions : rouvre tes fichiers et fenêtres là où tu les avais laissés
	{
		"folke/persistence.nvim",
		event = "BufReadPre",
		opts = {},
		keys = {
			{ "<leader>qs", function() require("persistence").load() end, desc = "Restaurer la session (dossier)" },
			{ "<leader>qS", function() require("persistence").select() end, desc = "Choisir une session" },
			{ "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Dernière session" },
			{ "<leader>qd", function() require("persistence").stop() end, desc = "Ne pas sauver cette session" },
		},
	},
}
