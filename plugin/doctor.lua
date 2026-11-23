-- :NideDoctor   bilan de l'installation (fenêtre flottante, q pour fermer)
-- :NidePalette  palette de commandes (aussi Ctrl+Maj+P / Espace P)
vim.api.nvim_create_user_command("NideDoctor", function()
	require("util.doctor").open()
end, { desc = "Bilan de l'installation de nide" })

vim.api.nvim_create_user_command("NidePalette", function()
	require("nide.palette").open()
end, { desc = "Palette de commandes" })
