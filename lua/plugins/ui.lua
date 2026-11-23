return {
	-- Thème
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = false,
		priority = 1000,
		opts = {
			flavour = "mocha",
			auto_integrations = false, -- intégrations listées à la main ci-dessous
			integrations = {
				blink_cmp = true,
				bufferline = true,
				dap = true,
				dap_ui = true,
				flash = true,
				gitsigns = true,
				grug_far = true,
				mason = true,
				noice = true,
				snacks = { enabled = true },
				which_key = true,
				aerial = true,
				diffview = true,
				lsp_trouble = true,
				neotest = true,
				overseer = true,
				dropbar = { enabled = true, color_mode = true },
				native_lsp = { enabled = true, inlay_hints = { background = true } },
			},
		},
		config = function(_, opts)
			require("catppuccin").setup(opts)
			vim.cmd.colorscheme("catppuccin")
		end,
	},
	{ "folke/tokyonight.nvim", lazy = true },
	{ "rebelot/kanagawa.nvim", lazy = true },

	{ "nvim-mini/mini.icons", lazy = true, opts = {}, init = function()
		package.preload["nvim-web-devicons"] = function()
			require("mini.icons").mock_nvim_web_devicons()
			return package.loaded["nvim-web-devicons"]
		end
	end },

	-- Barre de statut
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		opts = function()
			local function lsp_names()
				local names = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = 0 }))
				return #names > 0 and ("\u{f085} " .. table.concat(names, ", ")) or ""
			end
			return {
				options = {
					theme = "auto", -- suit le thème actif
					globalstatus = true,
					component_separators = "",
					section_separators = { left = "\u{e0b4}", right = "\u{e0b6}" },
					disabled_filetypes = { statusline = { "snacks_dashboard" } },
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff" },
					lualine_c = {
						{ "filetype", icon_only = true, padding = { left = 1, right = 0 } },
						{ "filename", path = 1, symbols = { modified = " ●", readonly = " \u{f023}" } },
						"diagnostics",
					},
					lualine_x = {
						{
							function() return require("noice").api.status.mode.get() end,
							cond = function() return package.loaded.noice and require("noice").api.status.mode.has() end,
						},
						{
							function() return "\u{f188} " .. require("dap").status() end,
							cond = function() return package.loaded.dap and require("dap").status() ~= "" end,
						},
						{
							-- compilation en cours (Espace k) / surveillance
							function() return require("util.compile").status() end,
							cond = function() return package.loaded["util.compile"] ~= nil and require("util.compile").status() ~= "" end,
							color = function() return package.loaded["util.compile"] and require("util.compile").status_color() end,
						},
						lsp_names,
					},
					lualine_y = { "encoding", "fileformat", "progress" },
					lualine_z = { "selectioncount", "location" }, -- taille de la sélection en mode visuel
				},
				extensions = { "lazy", "mason", "trouble", "quickfix", "nvim-dap-ui", "aerial", "overseer" },
			}
		end,
	},

	-- Onglets des fichiers ouverts, en haut
	{
		"akinsho/bufferline.nvim",
		event = "VeryLazy",
		keys = {
			{ "<leader>bp", "<Cmd>BufferLineTogglePin<CR>", desc = "Épingler l'onglet" },
			{ "<leader>bj", "<Cmd>BufferLinePick<CR>", desc = "Choisir un onglet (lettre)" },
			{ "<leader>bl", "<Cmd>BufferLineCloseLeft<CR>", desc = "Fermer ceux à gauche" },
			{ "<leader>br", "<Cmd>BufferLineCloseRight<CR>", desc = "Fermer ceux à droite" },
			{ "<A-,>", "<Cmd>BufferLineMovePrev<CR>", desc = "Déplacer l'onglet à gauche" },
			{ "<A-;>", "<Cmd>BufferLineMoveNext<CR>", desc = "Déplacer l'onglet à droite" },
		},
		opts = {
			options = {
				close_command = function(n) Snacks.bufdelete(n) end,
				right_mouse_command = function(n) Snacks.bufdelete(n) end,
				diagnostics = "nvim_lsp",
				always_show_bufferline = true,
				show_buffer_close_icons = true,
				separator_style = "slant",
				offsets = {
					{ filetype = "snacks_layout_box", text = "Explorateur", highlight = "Directory", separator = true },
				},
			},
		},
		config = function(_, opts)
			if (vim.g.colors_name or ""):find("catppuccin") then
				opts.highlights = require("catppuccin.special.bufferline").get_theme()
			end
			require("bufferline").setup(opts)
		end,
	},

	-- Ligne de commande en popup, messages propres
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = { "MunifTanjim/nui.nvim" },
		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
				},
			},
			routes = {
				{ filter = { event = "msg_show", any = { { find = "%d+L, %d+B" }, { find = "; after #%d+" }, { find = "; before #%d+" } } }, view = "mini" },
			},
			presets = {
				bottom_search = true,
				command_palette = true,
				long_message_to_split = true,
				lsp_doc_border = true,
			},
		},
	},

	-- Aide contextuelle : appuie sur Espace et attends
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "helix",
			delay = 300,
			spec = {
				{ "<leader>b", group = "Onglets (buffers)" },
				{ "<leader>c", group = "Code" },
				{ "<leader>d", group = "Débogueur" },
				{ "<leader>f", group = "Fichiers" },
				{ "<leader>g", group = "Git" },
				{ "<leader>gh", group = "Blocs modifiés (hunks)" },
				{ "<leader>j", group = "Jupyter (notebook)" },
				{ "<leader>k", group = "Compiler" },
				{ "<leader>m", group = "Markdown" },
				{ "<leader>o", group = "Tâches (overseer)" },
				{ "<leader>q", group = "Session / quitter" },
				{ "<leader>s", group = "Rechercher" },
				{ "<leader>t", group = "Terminal / tests" },
				{ "<leader>u", group = "Interface (on/off)" },
				{ "<leader>w", group = "Fenêtres" },
				{ "<leader>x", group = "Problèmes (diagnostics)" },
				{ "<leader><Tab>", group = "Espaces (tabs)" },
				{ "<localleader>l", group = "LaTeX (vimtex)" },
				{ "g", group = "Aller à" },
				{ "gs", group = "Entourer (surround)" },
				{ "[", group = "Précédent" },
				{ "]", group = "Suivant" },
				{ "z", group = "Replis / vue" },
			},
		},
		keys = {
			{ "<leader>sK", function() require("which-key").show({ global = false }) end, desc = "Raccourcis de ce fichier" },
		},
	},

	-- Fil d'Ariane cliquable en haut de chaque fenêtre (fichier › classe › fonction)
	{
		"Bekaboo/dropbar.nvim",
		event = "BufReadPost",
		keys = {
			{ "<leader>cb", function() require("dropbar.api").pick() end, desc = "Naviguer dans le fil d'Ariane" },
		},
		opts = {},
	},

	-- Barre de défilement avec erreurs / git / recherche
	{ "lewis6991/satellite.nvim", event = "BufReadPost", opts = {} },
}
