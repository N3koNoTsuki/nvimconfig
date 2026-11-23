-- Notebooks Jupyter (comme VS Code) et aperçu Markdown réel dans le navigateur.
-- Logique des cellules : lua/util/notebook.lua
local function nb(fn, ...)
	local args = { ... }
	return function()
		require("util.notebook")[fn](unpack(args))
	end
end

-- terminal capable d'afficher des images (protocole graphique kitty)
local has_graphics = vim.env.KITTY_WINDOW_ID ~= nil
	or (vim.env.TERM or ""):find("kitty") ~= nil
	or vim.env.TERM_PROGRAM == "ghostty"
	or vim.env.TERM_PROGRAM == "WezTerm"

-- Module notebook (lua/nide/modules.lua) : jupytext, molten, image.nvim et otter ne sont
-- installés et chargés que s'il est activé
local modules = require("nide.modules")
local function enabled(name)
	return function()
		return modules.plugin_enabled(name)
	end
end

-- Module désactivé : :NotebookNew, Espace j N et l'ouverture d'un .ipynb expliquent comment l'activer
-- (le .ipynb s'ouvre alors en JSON brut)
if not modules.enabled("notebook") then
	local function disabled()
		vim.notify(
			"Module notebook désactivé : relance "
				.. vim.fn.fnamemodify(vim.fn.stdpath("config"), ":~")
				.. "/install.sh pour l'activer",
			vim.log.levels.WARN,
			{ title = "Notebook" }
		)
	end
	vim.api.nvim_create_user_command("NotebookNew", disabled, { nargs = "?", desc = "Créer un notebook Jupyter" })
	vim.keymap.set("n", "<leader>jN", disabled, { desc = "Nouveau notebook" })
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = vim.api.nvim_create_augroup("ide_notebook", { clear = true }),
		pattern = "*.ipynb",
		once = true,
		callback = function()
			vim.schedule(disabled)
		end,
	})
end

return {
	-- .ipynb ⇄ texte lisible (Markdown + blocs de code)
	{
		"GCBallesteros/jupytext.nvim",
		enabled = enabled("GCBallesteros/jupytext.nvim"),
		lazy = false, -- doit intercepter l'ouverture du premier .ipynb
		opts = { style = "markdown", output_extension = "md", force_ft = "markdown" },
		config = function(_, opts)
			require("jupytext").setup(opts)
			-- son :checkhealth (non maintenu) appelle vim.health.report_*, supprimés en 0.11 : on le remplace
			package.loaded["jupytext.health"] = {
				check = function()
					vim.health.start("jupytext.nvim")
					if vim.fn.executable("jupytext") == 1 then
						vim.health.ok("jupytext est disponible")
					else
						vim.health.error("jupytext introuvable", "Installe-le : uv tool install jupytext (ou pipx install jupytext)")
					end
				end,
			}
			local group = vim.api.nvim_create_augroup("ide_notebook", { clear = true })
			vim.api.nvim_create_autocmd("BufWinEnter", {
				group = group,
				pattern = "*.ipynb",
				callback = function(args)
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(args.buf) then
							require("util.notebook").attach(args.buf)
						end
					end)
				end,
			})
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = group,
				pattern = "*.ipynb",
				callback = function(args)
					require("util.notebook").export(args.buf)
				end,
			})
			vim.api.nvim_create_user_command("NotebookNew", function(o)
				require("util.notebook").new(o.args)
			end, { nargs = "?", complete = "file", desc = "Créer un notebook Jupyter" })
		end,
	},

	-- Exécution dans un kernel Jupyter, sorties sous les cellules
	{
		"benlubas/molten-nvim",
		enabled = enabled("benlubas/molten-nvim"),
		version = "^1.0.0",
		lazy = false,
		build = ":UpdateRemotePlugins",
		-- image.nvim n'est pas une dépendance : molten ne fait require("image") que si
		-- molten_image_provider = "image.nvim" (terminal graphique), et lazy le charge alors
		keys = {
			{ "<leader>jN", "<Cmd>NotebookNew<CR>", desc = "Nouveau notebook" },
		},
		init = function()
			local py = vim.fn.stdpath("data") .. "/molten-venv/bin/python"
			if vim.fn.executable(py) == 1 then
				vim.g.python3_host_prog = py
			end
			vim.g.molten_image_provider = has_graphics and "image.nvim" or "none"
			vim.g.molten_auto_open_output = false -- sorties sous la cellule, pas en fenêtre flottante
			vim.g.molten_virt_text_output = true
			vim.g.molten_virt_lines_off_by_1 = true -- sortie sous le ``` de fin de cellule
			vim.g.molten_virt_text_max_lines = 30
			vim.g.molten_wrap_output = true
			vim.g.molten_output_win_max_height = 30
			vim.g.molten_output_show_exec_time = true
			vim.g.molten_enter_output_behavior = "open_and_enter"
		end,
	},

	-- Images (graphiques matplotlib) dans le terminal
	{
		"3rd/image.nvim",
		enabled = enabled("3rd/image.nvim"),
		-- toujours installé (pas de `cond`) : un install.sh lancé hors de kitty doit l'installer
		-- aussi ; il n'est chargé que dans un terminal graphique (voir molten ci-dessus)
		lazy = true,
		opts = {
			backend = "kitty",
			processor = "magick_cli",
			integrations = { markdown = { enabled = false } },
			max_width_window_percentage = 100,
			max_height_window_percentage = 50,
			window_overlap_clear_enabled = true,
		},
	},

	-- LSP (complétion, doc, erreurs) dans les cellules de code
	{ "jmbuhr/otter.nvim", enabled = enabled("jmbuhr/otter.nvim"), lazy = true, dependencies = { "nvim-treesitter/nvim-treesitter" }, opts = {} },

	-- Aperçu Markdown réel dans le navigateur, suit le curseur, maths KaTeX + diagrammes mermaid
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" },
		ft = "markdown",
		build = "cd app && ./install.sh", -- télécharge le serveur d'aperçu précompilé
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
			vim.g.mkdp_auto_close = 0 -- reste ouvert quand on change de fichier
			vim.g.mkdp_theme = "dark"
			vim.g.mkdp_page_title = "${name}"
			-- sous niri : la page s'ouvre dans sa propre fenêtre, en 50/50 à côté du terminal
			-- (lua/util/mdpreview.lua) ; ailleurs, navigateur par défaut
			vim.cmd([[
				function! MkdpOpenNiri(url) abort
					call v:lua.require'util.mdpreview'.open_url(a:url)
				endfunction
			]])
			vim.g.mkdp_browserfunc = "MkdpOpenNiri"
		end,
		keys = {
			{ "<leader>mp", function() require("util.mdpreview").toggle() end, ft = "markdown", desc = "Aperçu navigateur (on/off)" },
			{ "<leader>mr", "<Cmd>RenderMarkdown toggle<CR>", ft = "markdown", desc = "Rendu dans l'éditeur (on/off)" },
		},
	},
}
