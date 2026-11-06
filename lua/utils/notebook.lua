-- ================================================================================================
-- TITLE : notebook
-- ABOUT : helpers for .ipynb buffers (shown as markdown by jupytext.nvim, code cells are ``` fences) :
--         find the cells, run them through molten, start a kernel from the project's .venv.
-- ================================================================================================

local M = {}

-- kernel id -> true once it accepts code / list of what waits for it
local ready, pending = {}, {}

-- every code cell of the buffer : first / last = fences, body_first / body_last = code to send, 1-indexed
local function cells(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local found, open = {}, nil
	for i, line in ipairs(lines) do
		if not open and line:find("^```%a") then
			open = i
		elseif open and line:find("^```%s*$") then
			local body_last = i - 1
			while body_last > open and lines[body_last]:find("^%s*$") do
				body_last = body_last - 1
			end
			found[#found + 1] = { first = open, last = i, body_first = open + 1, body_last = body_last }
			open = nil
		end
	end
	return found
end

local function current_cell(found)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	for _, cell in ipairs(found) do
		if row >= cell.first and row <= cell.last then
			return cell
		end
	end
end

local function has_kernel()
	return #vim.fn.MoltenRunningKernels(true) > 0
end

-- the kernel of the project : <venv>/bin/python registered under the project's name,
-- or the bundled "python3" (only ipykernel, no numpy etc.) when there is no usable venv
local function project_kernel()
	local dir = vim.fn.expand("%:p:h")
	local venv = vim.env.VIRTUAL_ENV
	if not venv then
		venv = vim.fs.find(".venv", { path = dir, upward = true, type = "directory" })[1]
	end
	if not venv then
		vim.notify("Pas de .venv trouvé : kernel python3 de base (sans numpy...)", vim.log.levels.WARN)
		return "python3"
	end

	local python = venv .. "/bin/python"
	local name = vim.fs.basename(vim.fs.dirname(venv)):gsub("[^%w_.-]", "_")
	local res = vim.system({ python, "-m", "ipykernel", "install", "--user", "--name", name }, { text = true }):wait()
	if res.code ~= 0 then
		vim.notify(
			"ipykernel absent de " .. venv .. " (uv pip install ipykernel) : kernel python3 de base",
			vim.log.levels.WARN
		)
		return "python3"
	end
	return name
end

-- the kernel named by the .ipynb when it isn't written in python (octave...), nil otherwise
local function foreign_kernel()
	if vim.fn.expand("%:e") ~= "ipynb" then
		return nil
	end
	local ok, notebook = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(vim.fn.expand("%:p")), "\n"))
	end)
	local metadata = ok and notebook.metadata or {}
	local spec = metadata.kernelspec or {}
	local language = spec.language or (metadata.language_info or {}).name
	if spec.name and language and language ~= "python" then
		return spec.name
	end
end

function M.init_kernel()
	vim.cmd("MoltenInit " .. (foreign_kernel() or project_kernel()))
	-- show the outputs already stored in the notebook
	if vim.fn.expand("%:e") == "ipynb" then
		vim.cmd("MoltenImportOutput")
	end
end

-- molten silently loses the output of code sent before the kernel is ready : hold it back until then
local function when_ready(fn)
	local buf = vim.api.nvim_get_current_buf()
	if not has_kernel() then
		M.init_kernel()
	end
	local kernel = vim.fn.MoltenRunningKernels(true)[1]
	if not kernel then
		return
	end
	if ready[kernel] then
		fn()
	else
		pending[kernel] = pending[kernel] or {}
		table.insert(pending[kernel], { buf = buf, fn = fn })
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("NotebookKernel", {})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MoltenKernelReady",
		callback = function(args)
			local kernel = args.data.kernel_id
			ready[kernel] = true
			for _, job in ipairs(pending[kernel] or {}) do
				if vim.api.nvim_buf_is_valid(job.buf) then
					vim.api.nvim_buf_call(job.buf, job.fn)
				end
			end
			pending[kernel] = nil
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "MoltenDeinitPost",
		callback = function()
			ready, pending = {}, {}
		end,
	})
end

local function run(cell)
	if cell.body_last >= cell.body_first then
		vim.fn.MoltenEvaluateRange(cell.body_first, cell.body_last)
	end
end

function M.run_cell()
	local cell = current_cell(cells(0))
	if not cell then
		vim.notify("Curseur hors d'une cellule de code", vim.log.levels.WARN)
		return
	end
	when_ready(function()
		run(cell)
	end)
end

function M.run_all()
	local found = cells(0)
	when_ready(function()
		for _, cell in ipairs(found) do
			run(cell)
		end
	end)
end

function M.restart()
	for _, kernel in ipairs(vim.fn.MoltenRunningKernels(true)) do
		ready[kernel] = nil
	end
	vim.cmd("MoltenRestart!")
end

function M.goto_cell(direction)
	local found = cells(0)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local target
	for _, cell in ipairs(found) do
		if direction > 0 and cell.first > row then
			target = cell
			break
		elseif direction < 0 and cell.last < row then
			target = cell
		end
	end
	if target then
		vim.api.nvim_win_set_cursor(0, { target.body_first, 0 })
	end
end

function M.run_cell_and_next()
	M.run_cell()
	M.goto_cell(1)
end

-- molten keeps the outputs in memory : write them in the .ipynb along with the code
function M.export_outputs()
	if require("lazy.core.config").plugins["molten-nvim"]._.loaded and has_kernel() then
		vim.cmd("MoltenExportOutput!")
	end
end

-- on open, like VS Code : stored outputs visible, LSP in the code cells
function M.on_open(buf)
	if vim.b[buf].notebook_opened or buf ~= vim.api.nvim_get_current_buf() then
		return
	end
	vim.b[buf].notebook_opened = true
	require("lazy").load({ plugins = { "molten-nvim", "otter.nvim" } })
	require("otter").activate({ "python" })
	M.init_kernel()
end

return M
