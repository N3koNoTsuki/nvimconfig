local group = vim.api.nvim_create_augroup("ide", { clear = true })
local au = function(event, opts)
	opts.group = group
	vim.api.nvim_create_autocmd(event, opts)
end

-- Surligner brièvement ce qu'on vient de copier
au("TextYankPost", {
	callback = function()
		vim.hl.on_yank({ timeout = 200 })
	end,
})

-- Revenir à la dernière position dans un fichier
au("BufReadPost", {
	callback = function(args)
		if vim.bo[args.buf].filetype == "gitcommit" then
			return -- un message de commit commence toujours en haut
		end
		local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
		if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(args.buf) then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- Recharger un fichier modifié hors de nvim
au({ "FocusGained", "TermClose", "TermLeave" }, {
	callback = function()
		if vim.o.buftype ~= "nofile" then
			vim.cmd("checktime")
		end
	end,
})

-- Neovim 0.12 se bloque si la fenêtre d'où l'on tape :qa est fermée pendant ExitPre, ce que
-- fait Snacks avec ses terminaux. Défini avant ceux de Snacks, donc exécuté avant : on retire
-- leurs ExitPre (Neovim arrête de toute façon les programmes des terminaux en quittant).
au("ExitPre", {
	callback = function()
		for _, a in ipairs(vim.api.nvim_get_autocmds({ event = "ExitPre" })) do
			if (a.group_name or ""):match("^snacks_win_%d+$") then
				pcall(vim.api.nvim_del_autocmd, a.id)
			end
		end
	end,
})

-- Égaliser les fenêtres quand le terminal est redimensionné
au("VimResized", { command = "tabdo wincmd =" })

-- q ferme les fenêtres "utilitaires"
au("FileType", {
	pattern = { "help", "qf", "man", "lspinfo", "checkhealth", "notify", "grug-far", "dap-float" },
	callback = function(args)
		vim.bo[args.buf].buflisted = false
		vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = args.buf, silent = true, desc = "Fermer" })
	end,
})

-- Texte : retour à la ligne + correcteur orthographique
au("FileType", {
	pattern = { "markdown", "text", "gitcommit" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

-- Créer les dossiers manquants à la sauvegarde
au("BufWritePre", {
	callback = function(args)
		if args.match:match("^%w%w+:[\\/][\\/]") then
			return
		end
		vim.fn.mkdir(vim.fn.fnamemodify(vim.uv.fs_realpath(args.match) or args.match, ":p:h"), "p")
	end,
})
