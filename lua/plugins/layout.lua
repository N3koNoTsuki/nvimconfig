-- Disposition IDE stable : chaque panneau a sa place (edgy.nvim)
--   gauche : explorateur   droite : plan / symboles / tests   bas : terminal, problèmes, tâches…
-- <Espace>uI : mode IDE (explorateur + plan + terminal d'un coup)
-- https://github.com/folke/edgy.nvim

-- Fenêtre normale (pas flottante) : edgy transforme sinon les flottantes en splits
local function split(win)
	return vim.api.nvim_win_get_config(win).relative == ""
end

-- Vue Trouble pour un côté donné ; `mode` nil = tous les autres modes
local function trouble(pos, mode, title)
	return {
		ft = "trouble",
		title = title,
		filter = function(_, win)
			local t = vim.w[win].trouble
			return t ~= nil
				and t.position == pos
				and t.type == "split"
				and t.relative == "editor"
				and not vim.w[win].trouble_preview
				and (mode == nil or t.mode == mode)
		end,
	}
end

-- Terminal Snacks en bas (pas le flottant de <Espace>tf)
local function terminal_bas(_, win)
	local w = vim.w[win].snacks_win
	return split(win) and w ~= nil and w.position == "bottom"
end

local ide = {}

-- Le mode IDE est actif si un panneau edgy est ouvert dans cet onglet
function ide.is_open()
	for win in pairs(require("edgy.editor").list_wins().edgy) do
		if vim.api.nvim_win_is_valid(win) then
			return true
		end
	end
	return false
end

-- Ouvre ce qui manque : explorateur, plan, terminal ; garde le curseur dans le code
function ide.open(opts)
	opts = opts or {}
	local main = vim.api.nvim_get_current_win()
	if #Snacks.picker.get({ source = "explorer" }) == 0 then
		Snacks.explorer({ focus = false })
	end
	local aerial = require("aerial")
	if not aerial.is_open() then
		pcall(aerial.open, { focus = false, direction = "right" })
	end
	local term, created = Snacks.terminal.get(nil, { start_insert = false })
	if term and not created and not term:valid() then
		term:show()
	end
	if vim.api.nvim_win_is_valid(main) then
		vim.api.nvim_set_current_win(main)
	end
	vim.cmd.stopinsert()
	if opts.focus_explorer then
		local p = Snacks.picker.get({ source = "explorer" })[1]
		if p then
			p:focus()
		end
	end
end

-- Ferme tous les panneaux (les terminaux sont masqués, pas tués)
function ide.close()
	for _, t in ipairs(Snacks.terminal.list()) do
		if t:valid() and split(t.win) then
			t:hide()
		end
	end
	for _, p in ipairs(Snacks.picker.get({ source = "explorer" })) do
		p:close()
	end
	require("edgy").close()
end

function ide.toggle()
	if ide.is_open() then
		ide.close()
	else
		ide.open()
	end
end

return {
	{
		"folke/edgy.nvim",
		event = "VeryLazy",
		keys = {
			{ "<leader>uI", ide.toggle, desc = "Mode IDE (tous les panneaux)" },
			{ "<leader>uE", function() require("edgy").select() end, desc = "Aller à un panneau" },
		},
		opts = {
			animate = { enabled = false }, -- l'explorateur se redessine à chaque pas sinon
			options = {
				left = { size = 32 },
				right = { size = 36 },
				bottom = { size = 0.3 },
			},
			left = {
				{
					title = "Explorateur",
					ft = "snacks_layout_box",
					filter = function(_, win)
						return split(win)
					end,
					wo = { winbar = false }, -- l'explorateur a déjà son titre (bufferline)
				},
			},
			right = {
				{ title = "Plan du fichier", ft = "aerial", filter = function(_, win) return split(win) end },
				trouble("right", "symbols", "Symboles"),
				trouble("right", "lsp", "Références"),
				trouble("right", nil, "Trouble"),
				{ title = "Tests", ft = "neotest-summary", filter = function(_, win) return split(win) end },
			},
			bottom = {
				{ title = "Terminal", ft = "snacks_terminal", filter = terminal_bas },
				{ title = "Compilation", ft = "nide_compile", filter = function(_, win) return split(win) end },
				trouble("bottom", "diagnostics", "Problèmes"),
				trouble("bottom", "qflist", "Quickfix"),
				trouble("bottom", "loclist", "Liste locale"),
				trouble("bottom", nil, "Trouble"),
				{ title = "Quickfix", ft = "qf", filter = function(_, win) return split(win) end },
				{ title = "Sortie des tests", ft = "neotest-output-panel", filter = function(_, win) return split(win) end },
				{ title = "Tâches", ft = "OverseerList", filter = function(_, win) return split(win) end },
				{
					title = "Aide",
					ft = "help",
					filter = function(buf, win)
						return split(win) and vim.bo[buf].buftype == "help"
					end,
				},
				{ title = "Messages", ft = "noice", filter = function(_, win) return split(win) end },
			},
		},
	},
}
