local o = vim.opt

-- Apparence
o.number = true
o.relativenumber = true
o.cursorline = true
o.signcolumn = "yes"
o.termguicolors = true
o.showmode = false -- le mode est affiché par lualine
o.laststatus = 3 -- une seule barre de statut globale, comme un IDE
o.cmdheight = 0 -- la ligne de commande apparaît en popup (noice)
o.pumheight = 12
o.scrolloff = 8
o.sidescrolloff = 8
o.wrap = false
o.linebreak = true
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.fillchars = { eob = " ", fold = " ", foldopen = "\u{f078}", foldclose = "\u{f054}", foldsep = " " }
o.splitright = true
o.splitbelow = true
o.splitkeep = "screen"
o.winborder = "rounded"
o.smoothscroll = true

-- Édition
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.softtabstop = 4
o.smartindent = true
o.shiftround = true
o.virtualedit = "block"
o.clipboard = "unnamedplus" -- presse-papier système
o.mouse = "a"
o.undofile = true
o.undolevels = 10000
o.swapfile = false
o.confirm = true -- demande au lieu de refuser de quitter un fichier modifié
o.autowrite = true
o.completeopt = { "menu", "menuone", "noselect" }

-- Recherche
o.ignorecase = true
o.smartcase = true
o.inccommand = "split" -- aperçu en direct de :s/…/…/
o.grepprg = "rg --vimgrep"
o.grepformat = "%f:%l:%c:%m"

-- Repli de code (treesitter), tout ouvert par défaut
o.foldlevel = 99
o.foldlevelstart = 99
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldtext = ""

-- Réactivité
o.updatetime = 200
o.timeoutlen = 400

o.spelllang = { "fr", "en" }
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }
o.shortmess:append({ W = true, I = true, c = true, C = true })
