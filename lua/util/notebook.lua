-- Notebooks Jupyter façon VS Code.
-- Un .ipynb est ouvert par jupytext.nvim comme du Markdown : le texte des cellules Markdown est
-- rendu par render-markdown, chaque cellule de code est un bloc ```python … ```.
-- molten-nvim exécute les cellules dans un kernel Jupyter et affiche les sorties sous la cellule
-- (graphiques compris via image.nvim, dans kitty). otter.nvim donne le LSP dans les cellules.
-- À la sauvegarde, le .ipynb est réécrit avec les sorties.
local M = {}

M.venv = vim.fn.stdpath("data") .. "/molten-venv"
M.default_kernel = "nvim-ide"

local FENCE_OPEN = "^```%s*[%w_%-]+"
local FENCE_CLOSE = "^```%s*$"

local function lines(buf)
	return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

-- toutes les cellules de code : { start = ligne du ```python, stop = ligne du ``` } (1-indexé)
function M.cells(buf)
	local out, open = {}, nil
	for i, l in ipairs(lines(buf)) do
		if not open and l:match(FENCE_OPEN) then
			open = i
		elseif open and l:match(FENCE_CLOSE) then
			table.insert(out, { start = open, stop = i })
			open = nil
		end
	end
	return out
end

-- cellule sous le curseur (ou la plus proche au-dessus)
function M.current(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local cells, best = M.cells(buf), nil
	for _, c in ipairs(cells) do
		if row >= c.start and row <= c.stop then
			return c, cells
		end
		if c.stop < row then
			best = c
		end
	end
	return best, cells
end

-- ---------------------------------------------------------------------------
-- Kernel
-- ---------------------------------------------------------------------------
-- kernels attachés au buffer (MoltenRunningKernels(true) regarde le buffer courant)
local function running(buf)
	local ok, kernels = pcall(vim.api.nvim_buf_call, buf or 0, function()
		return vim.fn.MoltenRunningKernels(true)
	end)
	return ok and type(kernels) == "table" and #kernels > 0, kernels
end

local function available_kernels()
	local py = M.venv .. "/bin/python"
	if vim.fn.executable(py) == 0 then
		return {}
	end
	local out = vim.fn.system({
		py, "-c", "import json, jupyter_client.kernelspec as k; print(json.dumps(list(k.find_kernel_specs())))",
	})
	local ok, list = pcall(vim.json.decode, out)
	return ok and list or {}
end

-- kernel enregistré dans le .ipynb (metadata.kernelspec.name)
local function notebook_kernel(buf)
	local path = vim.api.nvim_buf_get_name(buf)
	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end)
	return ok and data and data.metadata and data.metadata.kernelspec and data.metadata.kernelspec.name
end

-- .venv du projet (en remontant) qui contient ipykernel : on l'enregistre comme kernel
local function project_venv_kernel(buf)
	local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
	for _, name in ipairs({ ".venv", "venv", ".env" }) do
		local found = vim.fs.find(name, { path = dir, upward = true, type = "directory" })[1]
		if found then
			local py = found .. "/bin/python"
			vim.fn.system({ py, "-c", "import ipykernel" })
			if vim.v.shell_error ~= 0 then
				vim.notify(
					("%s n'a pas ipykernel : kernel par défaut utilisé.\nPour utiliser ce venv : uv pip install --python %s ipykernel"):format(found, py),
					vim.log.levels.WARN
				)
				return nil
			end
			local kname = "venv-" .. vim.fs.basename(vim.fs.dirname(found)):gsub("[^%w_-]", "_")
			vim.fn.system({ py, "-m", "ipykernel", "install", "--user", "--name", kname, "--display-name", kname })
			return kname
		end
	end
end

function M.pick_kernel(buf)
	buf = buf or 0
	local venv = project_venv_kernel(buf)
	if venv then
		return venv
	end
	local wanted, list = notebook_kernel(buf), available_kernels()
	if wanted and vim.list_contains(list, wanted) then
		return wanted
	end
	return M.default_kernel
end

function M.init_kernel(buf, kernel)
	buf = buf or vim.api.nvim_get_current_buf()
	if running(buf) then
		return true
	end
	kernel = kernel or M.pick_kernel(buf)
	local ok, err = pcall(vim.cmd, "MoltenInit " .. kernel)
	if not ok then
		vim.notify("Impossible de démarrer le kernel " .. kernel .. "\n" .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	vim.b[buf].nb_kernel = kernel
	-- réaffiche les sorties enregistrées dans le .ipynb
	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_call(buf, function()
				pcall(vim.cmd, "MoltenImportOutput")
			end)
		end
	end, 500)
	return true
end

function M.choose_kernel()
	local list = available_kernels()
	vim.ui.select(list, { prompt = "Kernel Jupyter" }, function(choice)
		if choice then
			if running(0) then
				pcall(vim.cmd, "MoltenDeinit")
			end
			M.init_kernel(0, choice)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Exécution
-- ---------------------------------------------------------------------------
local function eval(c)
	if c.stop - c.start < 2 then
		return -- cellule vide
	end
	vim.fn.MoltenEvaluateRange(c.start + 1, c.stop - 1)
end

local function goto_line(l)
	vim.api.nvim_win_set_cursor(0, { l, 0 })
end

function M.run_cell()
	vim.cmd.stopinsert()
	local c = M.current()
	if not c then
		return vim.notify("Pas de cellule de code ici", vim.log.levels.WARN)
	end
	if M.init_kernel() then
		eval(c)
	end
end

-- Maj+Entrée : exécute puis va à la cellule suivante (en crée une à la fin, comme VS Code)
function M.run_and_next()
	local c, cells = M.current()
	M.run_cell()
	if not c then
		return
	end
	for _, n in ipairs(cells) do
		if n.start > c.stop then
			return goto_line(n.start + 1)
		end
	end
	M.add_cell(true)
	vim.cmd.stopinsert()
end

-- Alt+Entrée : exécute puis insère une cellule juste en dessous
function M.run_and_insert()
	M.run_cell()
	M.add_cell(true)
end

function M.run_all()
	if not M.init_kernel() then
		return
	end
	for _, c in ipairs(M.cells()) do
		eval(c)
	end
end

function M.run_above()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	if not M.init_kernel() then
		return
	end
	for _, c in ipairs(M.cells()) do
		if c.start <= row then
			eval(c)
		end
	end
end

function M.restart()
	pcall(vim.cmd, "MoltenRestart!")
end

-- ---------------------------------------------------------------------------
-- Édition des cellules
-- ---------------------------------------------------------------------------
function M.goto_cell(dir)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local cells = M.cells()
	if dir > 0 then
		for _, c in ipairs(cells) do
			if c.start > row then
				return goto_line(c.start + 1)
			end
		end
	else
		for i = #cells, 1, -1 do
			if cells[i].stop < row then
				return goto_line(cells[i].start + 1)
			end
		end
	end
end

-- nouvelle cellule de code sous (ou au-dessus de) la cellule courante, curseur dedans en insertion
function M.add_cell(below)
	local c = M.current()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local at
	if c then
		at = below and c.stop or (c.start - 1)
	else
		at = below and row or row - 1
	end
	vim.api.nvim_buf_set_lines(0, at, at, false, { "", "```python", "", "```" })
	goto_line(at + 3)
	vim.cmd.startinsert()
end

-- nouvelle cellule Markdown (du texte simple entre deux cellules de code)
function M.add_markdown(below)
	local c = M.current()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local at = c and (below and c.stop or c.start - 1) or row
	vim.api.nvim_buf_set_lines(0, at, at, false, { "", "" })
	goto_line(at + 2)
	vim.cmd.startinsert()
end

function M.delete_cell()
	local c = M.current()
	if c then
		pcall(vim.cmd, "MoltenDelete")
		vim.api.nvim_buf_set_lines(0, c.start - 1, c.stop, false, {})
	end
end

-- ---------------------------------------------------------------------------
-- Mise en place sur un buffer notebook
-- ---------------------------------------------------------------------------
function M.attach(buf)
	-- options locales à chaque fenêtre qui affiche le notebook (pas globales)
	local win = vim.fn.bufwinid(buf)
	if win ~= -1 then
		vim.wo[win][0].spell = false
		vim.wo[win][0].conceallevel = 2
	end
	if vim.b[buf].nb_attached then
		return
	end
	vim.b[buf].nb_attached = true
	vim.b[buf].disable_autoformat = true -- prettier réécrirait le notebook

	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
	end
	-- Comme dans VS Code
	map({ "n", "i" }, "<C-CR>", M.run_cell, "Exécuter la cellule")
	map({ "n", "i" }, "<S-CR>", M.run_and_next, "Exécuter et passer à la suivante")
	map({ "n", "i" }, "<M-CR>", M.run_and_insert, "Exécuter et insérer une cellule")
	-- Les mêmes sous <Espace>j
	map("n", "<leader>jj", M.run_cell, "Exécuter la cellule  (Ctrl+Entrée)")
	map("n", "<leader>jn", M.run_and_next, "Exécuter → suivante  (Maj+Entrée)")
	map("n", "<leader>ja", M.run_all, "Tout exécuter")
	map("n", "<leader>jA", M.run_above, "Exécuter jusqu'ici")
	map("x", "<leader>jv", ":<C-u>MoltenEvaluateVisual<CR>", "Exécuter la sélection")
	map("n", "<leader>jl", "<Cmd>MoltenEvaluateLine<CR>", "Exécuter la ligne")
	map("n", "<leader>jb", function() M.add_cell(true) end, "Nouvelle cellule de code dessous")
	map("n", "<leader>jB", function() M.add_cell(false) end, "Nouvelle cellule de code dessus")
	map("n", "<leader>jm", function() M.add_markdown(true) end, "Nouveau texte (Markdown) dessous")
	map("n", "<leader>jd", M.delete_cell, "Supprimer la cellule")
	map("n", "<leader>jo", "<Cmd>noautocmd MoltenEnterOutput<CR>", "Entrer dans la sortie (scroller)")
	map("n", "<leader>jh", "<Cmd>MoltenHideOutput<CR>", "Masquer la sortie flottante")
	map("n", "<leader>jc", "<Cmd>MoltenDelete<CR>", "Effacer la sortie de la cellule")
	map("n", "<leader>jx", "<Cmd>MoltenInterrupt<CR>", "Interrompre le calcul")
	map("n", "<leader>jr", M.restart, "Redémarrer le kernel")
	map("n", "<leader>jk", M.choose_kernel, "Choisir le kernel")
	map("n", "<leader>ji", "<Cmd>MoltenInfo<CR>", "Infos kernel")
	map("n", "]j", function() M.goto_cell(1) end, "Cellule suivante")
	map("n", "[j", function() M.goto_cell(-1) end, "Cellule précédente")

	pcall(function()
		require("otter").activate({ "python" }, true, true)
	end)
	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf then
			M.init_kernel(buf)
		end
	end, 300)
end

-- à la sauvegarde : réécrit les sorties dans le .ipynb
function M.export(buf)
	if running(buf) then
		vim.api.nvim_buf_call(buf, function()
			pcall(vim.cmd, "MoltenExportOutput!")
		end)
	end
end

-- nouveau notebook vide
function M.new(name)
	name = (name and name ~= "") and name or "notebook.ipynb"
	if not name:match("%.ipynb$") then
		name = name .. ".ipynb"
	end
	if vim.uv.fs_stat(name) then
		return vim.cmd.edit(vim.fn.fnameescape(name))
	end
	local nb = {
		cells = {
			{ cell_type = "markdown", metadata = vim.empty_dict(), source = { "# Nouveau notebook" } },
			{ cell_type = "code", metadata = vim.empty_dict(), execution_count = vim.NIL, outputs = {}, source = { "import numpy as np\n", "import matplotlib.pyplot as plt" } },
		},
		metadata = {
			kernelspec = { name = M.default_kernel, display_name = "Python (nvim-ide)", language = "python" },
			language_info = { name = "python" },
		},
		nbformat = 4,
		nbformat_minor = 5,
	}
	vim.fn.writefile({ vim.json.encode(nb) }, name)
	vim.cmd.edit(vim.fn.fnameescape(name))
end

return M
