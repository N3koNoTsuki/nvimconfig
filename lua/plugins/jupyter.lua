-- ================================================================================================
-- TITLE : Jupyter notebooks (jupytext.nvim + molten-nvim + image.nvim)
-- ABOUT : a .ipynb opens as markdown (jupytext), drawn by render-markdown.nvim, and is converted back
--         on :w. Code cells are ```python fences : otter.nvim gives them the LSP, molten runs them in a
--         Jupyter kernel and shows the outputs below them, image.nvim draws the plots (kitty graphics).
-- LINKS :
--   > jupytext : https://github.com/GCBallesteros/jupytext.nvim
--   > molten   : https://github.com/benlubas/molten-nvim
--   > image    : https://github.com/3rd/image.nvim
--   > otter    : https://github.com/jmbuhr/otter.nvim
-- DEPENDENCIES/INTEGRATIONS:
--   > imagemagick (pacman), jupytext (uv tool install jupytext)
--   > ~/.config/jupytext/jupytext.toml : hides the YAML header
--       notebook_metadata_filter = "-all"
--       cell_metadata_filter = "-all"
--   > ~/.local/share/nvim/molten-venv : python host of molten
--       uv venv --python 3.13 ~/.local/share/nvim/molten-venv
--       uv pip install --python ~/.local/share/nvim/molten-venv/bin/python \
--         pynvim jupyter_client nbformat ipykernel cairosvg pyperclip octave_kernel
--   > octave (pacman) : for the notebooks whose kernelspec is octave
--   > after a change of the venv or of molten : :UpdateRemotePlugins, then restart nvim
-- ================================================================================================

local function nb(name, ...)
	local args = { ... }
	return function()
		require("utils.notebook")[name](unpack(args))
	end
end

return {
	{
		"GCBallesteros/jupytext.nvim",
		lazy = false, -- must catch the BufReadCmd of the first .ipynb
		opts = { style = "markdown", output_extension = "md", force_ft = "markdown" },
	},
	{
		"3rd/image.nvim",
		lazy = true,
		opts = {
			backend = "kitty",
			processor = "magick_cli",
			integrations = {},
			max_width_window_percentage = 100,
			max_height_window_percentage = 100,
			window_overlap_clear_enabled = true,
		},
	},
	{ "jmbuhr/otter.nvim", lazy = true, dependencies = { "nvim-treesitter/nvim-treesitter" }, opts = {} },
	{
		"benlubas/molten-nvim",
		branch = "main", -- v1.9.2 crashes on export of cells with comments (nvim 0.12), fixed after it
		build = ":UpdateRemotePlugins",
		dependencies = { "3rd/image.nvim" },
		init = function()
			local host = vim.fn.stdpath("data") .. "/molten-venv/bin/python"
			if vim.fn.executable(host) == 1 then
				vim.g.python3_host_prog = host
			end
			vim.g.molten_image_provider = "image.nvim"
			vim.g.molten_auto_open_output = false -- the outputs stay below the cells, as virtual lines
			vim.g.molten_virt_text_output = true
			-- on the last line of code, not on the closing fence : render-markdown conceals that line
			-- with conceal_lines, which hides its virtual lines too (and the plot then covers the text)
			vim.g.molten_virt_lines_off_by_1 = false
			vim.g.molten_virt_text_max_lines = 40
			vim.g.molten_wrap_output = true
			vim.g.molten_output_win_max_height = 30

			-- molten looks for a parser named after the kernel's language when it exports the outputs
			local matlab = vim.api.nvim_get_runtime_file("parser/matlab.so", false)[1]
			if matlab then
				vim.treesitter.language.add("octave", { path = matlab, symbol_name = "matlab" })
			end

			require("utils.notebook").setup()
			local group = vim.api.nvim_create_augroup("Notebook", {})
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = group,
				pattern = "*.ipynb",
				callback = function()
					require("utils.notebook").export_outputs()
				end,
			})
			vim.api.nvim_create_autocmd("BufWinEnter", {
				group = group,
				pattern = "*.ipynb",
				callback = function(args)
					vim.schedule(function()
						require("utils.notebook").on_open(args.buf)
					end)
				end,
			})
		end,
		keys = {
			{ "<leader>ji", nb("init_kernel"), desc = "Start kernel (project .venv)" },
			{ "<leader>jj", nb("run_cell"), desc = "Run cell" },
			{ "<leader>jn", nb("run_cell_and_next"), desc = "Run cell, go to next" },
			{ "<leader>ja", nb("run_all"), desc = "Run all cells" },
			{ "<leader>jl", "<cmd>MoltenEvaluateLine<cr>", desc = "Run line" },
			{ "<leader>jv", ":<C-u>MoltenEvaluateVisual<cr>", mode = "x", silent = true, desc = "Run selection" },
			{ "<leader>jo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Enter output window" },
			{ "<leader>jh", "<cmd>MoltenHideOutput<cr>", desc = "Hide output" },
			{ "<leader>jd", "<cmd>MoltenDelete<cr>", desc = "Delete cell output" },
			{ "<leader>jx", "<cmd>MoltenInterrupt<cr>", desc = "Interrupt kernel" },
			{ "<leader>jr", nb("restart"), desc = "Restart kernel (clears outputs)" },
			{ "]j", nb("goto_cell", 1), desc = "Next notebook cell" },
			{ "[j", nb("goto_cell", -1), desc = "Previous notebook cell" },
		},
	},
}
