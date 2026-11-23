-- ============================================================================
--  nide : une config Neovim pensée comme un IDE
--  Lancement : `nvim` (ou `nide`)
--  Prise en main interactive : <Espace>?  ou  :Tuto
-- ============================================================================

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- `nide dossier` : se placer dans le dossier et démarrer sur l'écran d'accueil
-- (logo + options), sans ouvrir de panneaux. Le mode IDE reste sur <Espace>uI.
if vim.fn.argc(-1) == 1 and vim.fn.isdirectory(vim.fn.argv(0, -1)) == 1 then
	local dir = vim.fn.fnamemodify(vim.fn.argv(0, -1), ":p")
	vim.fn.chdir(dir)
	vim.cmd("silent! argdelete *")
	-- le buffer du dossier devient un buffer vide sans nom : l'écran d'accueil
	-- (snacks) s'affiche s'il est seul et que c'est le buffer 1
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name ~= "" and vim.fn.isdirectory(name) == 1 then
			vim.api.nvim_buf_set_name(buf, "")
		end
	end
end

require("core.options")
require("core.keymaps")
require("core.autocmds")
require("core.lazy")
