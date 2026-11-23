-- Raccourcis "de base". Ceux des plugins sont définis avec chaque plugin.
local map = vim.keymap.set

-- Sauvegarder / quitter, comme partout
map({ "n", "i", "x", "s" }, "<C-s>", "<Cmd>w<CR><Esc>", { desc = "Sauvegarder" })
map("n", "<leader>qq", "<Cmd>qa<CR>", { desc = "Quitter tout" })

-- Échap efface aussi le surlignage de recherche
map({ "n", "i" }, "<Esc>", "<Cmd>nohlsearch<CR><Esc>", { desc = "Échap + effacer la recherche" })

-- Haut / bas qui suivent les lignes visuelles quand elles sont repliées
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

-- Fenêtres
map("n", "<C-h>", "<C-w>h", { desc = "Fenêtre de gauche" })
map("n", "<C-j>", "<C-w>j", { desc = "Fenêtre du bas" })
map("n", "<C-k>", "<C-w>k", { desc = "Fenêtre du haut" })
map("n", "<C-l>", "<C-w>l", { desc = "Fenêtre de droite" })
map("n", "<C-Up>", "<Cmd>resize +2<CR>", { desc = "Agrandir (hauteur)" })
map("n", "<C-Down>", "<Cmd>resize -2<CR>", { desc = "Réduire (hauteur)" })
map("n", "<C-Left>", "<Cmd>vertical resize -2<CR>", { desc = "Réduire (largeur)" })
map("n", "<C-Right>", "<Cmd>vertical resize +2<CR>", { desc = "Agrandir (largeur)" })
map("n", "<leader>wv", "<C-w>v", { desc = "Découper verticalement" })
map("n", "<leader>ws", "<C-w>s", { desc = "Découper horizontalement" })
map("n", "<leader>wd", "<C-w>c", { desc = "Fermer la fenêtre" })
map("n", "<leader>wo", "<C-w>o", { desc = "Garder seulement celle-ci" })
map("n", "<leader>w=", "<C-w>=", { desc = "Égaliser les tailles" })

-- Buffers (= onglets en haut)
map("n", "<S-h>", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Onglet précédent" })
map("n", "<S-l>", "<Cmd>BufferLineCycleNext<CR>", { desc = "Onglet suivant" })
map("n", "<leader>bb", "<Cmd>e #<CR>", { desc = "Onglet précédemment ouvert" })

-- Onglets Vim (espaces de travail)
map("n", "<leader><Tab><Tab>", "<Cmd>tabnew<CR>", { desc = "Nouvel espace (tab)" })
map("n", "<leader><Tab>d", "<Cmd>tabclose<CR>", { desc = "Fermer l'espace" })
map("n", "<leader><Tab>]", "<Cmd>tabnext<CR>", { desc = "Espace suivant" })
map("n", "<leader><Tab>[", "<Cmd>tabprevious<CR>", { desc = "Espace précédent" })

-- Indenter en gardant la sélection
map("x", "<", "<gv")
map("x", ">", ">gv")

-- Coller sur une sélection sans perdre ce qu'on a copié
map("x", "p", "P", { desc = "Coller (garde le registre)" }) -- "_dP se trompait en fin de ligne

-- Recherche centrée
map("n", "n", "nzzzv", { desc = "Résultat suivant" })
map("n", "N", "Nzzzv", { desc = "Résultat précédent" })

-- Sortir du mode terminal (Échap reste pour les programmes du terminal)
map("t", "<C-q>", "<C-\\><C-n>", { desc = "Terminal → mode normal" })
map("t", "<C-h>", "<Cmd>wincmd h<CR>", { desc = "Fenêtre de gauche" })
map("t", "<C-k>", "<Cmd>wincmd k<CR>", { desc = "Fenêtre du haut" })

-- Diagnostics
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Diagnostic de la ligne" })
map("n", "]e", function()
	vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { desc = "Erreur suivante" })
map("n", "[e", function()
	vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { desc = "Erreur précédente" })

-- Divers
map("n", "<leader>L", "<Cmd>Lazy<CR>", { desc = "Plugins (Lazy)" })
map("n", "<leader>cm", "<Cmd>Mason<CR>", { desc = "Outils (Mason)" })
map("n", "<leader>?", function()
	require("tuto").open()
end, { desc = "Tutoriel / prise en main" })

-- Palette de commandes façon VS Code. Ctrl+Maj+P n'arrive que si le terminal
-- distingue les touches modifiées (protocole clavier kitty, voir :h tui-csiu) : Espace P partout.
map({ "n", "i", "x" }, "<C-S-p>", function()
	require("nide.palette").open()
end, { desc = "Palette de commandes" })
map("n", "<leader>P", function()
	require("nide.palette").open()
end, { desc = "Palette de commandes" })
map("n", "<leader>cD", "<Cmd>NideDoctor<CR>", { desc = "Docteur (bilan de l'installation)" })
