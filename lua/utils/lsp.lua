local M = {}

-- lspsaga has no peek for declarations: show the prototype in a float (q / cursor move closes it)
M.peek_declaration = function()
	local params = vim.lsp.util.make_position_params(0, "utf-16")
	vim.lsp.buf_request(0, "textDocument/declaration", params, function(err, result)
		if err or not result or vim.tbl_isempty(result) then
			vim.notify("No declaration found", vim.log.levels.INFO)
			return
		end
		local location = vim.islist(result) and result[1] or result
		vim.lsp.util.preview_location(location, { border = "rounded" })
	end)
end

M.on_attach = function(event)
	if not event.data then
		return
	end

	local ok, client = pcall(vim.lsp.get_client_by_id, event.data.client_id)

	if not ok or not client then
		return
	end
	local bufnr = event.buf
	local keymap = vim.keymap.set

	local opts = {
		noremap = true, -- prevent recursive mapping
		silent = true, -- don't print the command to the cli
		buffer = bufnr, -- restrict the keymap to the local buffer number
	}

	-- native neovim keymaps
	keymap("n", "<leader>gd", M.peek_declaration, vim.tbl_extend("force", opts, { desc = "Peek declaration" })) -- prototype (header) in a float
	keymap("n", "<leader>gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Goto declaration" })) -- goto prototype (header)
	-- in C the "implementation" of a function is its definition (the body), not the prototype
	keymap("n", "gi", "<cmd>Lspsaga peek_definition<CR>", vim.tbl_extend("force", opts, { desc = "Peek implementation" }))
	keymap("n", "gI", "<cmd>Lspsaga goto_definition<CR>", vim.tbl_extend("force", opts, { desc = "Goto implementation" }))
	-- same as gi / gI, so they show up in the <leader>g (Goto) which-key menu
	keymap("n", "<leader>gi", "<cmd>Lspsaga peek_definition<CR>", vim.tbl_extend("force", opts, { desc = "Peek implementation (gi)" }))
	keymap("n", "<leader>gI", "<cmd>Lspsaga goto_definition<CR>", vim.tbl_extend("force", opts, { desc = "Goto implementation (gI)" }))
	keymap("n", "<leader>gsi", "<cmd>vsplit | Lspsaga goto_definition<CR>", vim.tbl_extend("force", opts, { desc = "Goto implementation (vsplit)" })) -- function body in split
	keymap("n", "<leader>gsd", "<cmd>vsplit | lua vim.lsp.buf.declaration()<CR>", vim.tbl_extend("force", opts, { desc = "Goto declaration (vsplit)" })) -- prototype (header) in split
	keymap("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", vim.tbl_extend("force", opts, { desc = "Code action" })) -- Code actions
	keymap("n", "<leader>rn", "<cmd>Lspsaga rename<CR>", vim.tbl_extend("force", opts, { desc = "Rename symbol" })) -- Rename symbol
	keymap("n", "<leader>D", "<cmd>Lspsaga show_line_diagnostics<CR>", vim.tbl_extend("force", opts, { desc = "Line diagnostics" })) -- Line diagnostics (float)
	keymap("n", "<leader>d", "<cmd>Lspsaga show_cursor_diagnostics<CR>", vim.tbl_extend("force", opts, { desc = "Cursor diagnostics" })) -- Cursor diagnostics
	keymap("n", "<leader>pd", "<cmd>Lspsaga diagnostic_jump_prev<CR>", vim.tbl_extend("force", opts, { desc = "Previous diagnostic" })) -- previous diagnostic
	keymap("n", "<leader>nd", "<cmd>Lspsaga diagnostic_jump_next<CR>", vim.tbl_extend("force", opts, { desc = "Next diagnostic" })) -- next diagnostic
	keymap("n", "K", "<cmd>Lspsaga hover_doc<CR>", vim.tbl_extend("force", opts, { desc = "Hover documentation" })) -- hover documentation

	-- fzf-lua keymaps
	keymap("n", "<leader>fd", "<cmd>FzfLua lsp_finder<CR>", vim.tbl_extend("force", opts, { desc = "LSP finder (defs + refs)" })) -- LSP Finder (definition + references)
	keymap("n", "<leader>fr", "<cmd>FzfLua lsp_references<CR>", vim.tbl_extend("force", opts, { desc = "LSP references" })) -- Show all references to the symbol under the cursor
	keymap("n", "<leader>ft", "<cmd>FzfLua lsp_typedefs<CR>", vim.tbl_extend("force", opts, { desc = "LSP type definitions" })) -- Jump to the type definition of the symbol under the cursor
	keymap("n", "<leader>fs", "<cmd>FzfLua lsp_document_symbols<CR>", vim.tbl_extend("force", opts, { desc = "LSP document symbols" })) -- List all symbols (functions, classes, etc.) in the current file
	keymap("n", "<leader>fw", "<cmd>FzfLua lsp_workspace_symbols<CR>", vim.tbl_extend("force", opts, { desc = "LSP workspace symbols" })) -- Search for any symbol across the entire project/workspace
	keymap("n", "<leader>fi", "<cmd>FzfLua lsp_implementations<CR>", vim.tbl_extend("force", opts, { desc = "LSP implementations" })) -- Go to implementation

	-- Order Imports (if supported by the client LSP)
	if client:supports_method("textDocument/codeAction", bufnr) then
		keymap("n", "<leader>oi", function()
			vim.lsp.buf.code_action({
				context = {
					only = { "source.organizeImports" },
					diagnostics = {},
				},
				apply = true,
				bufnr = bufnr,
			})
			-- format after changing import order
			vim.defer_fn(function()
				vim.lsp.buf.format({ bufnr = bufnr })
			end, 50) -- slight delay to allow for the import order to go first
		end, vim.tbl_extend("force", opts, { desc = "Organize imports" }))
	end

	-- === DAP keymaps ===
	if client.name == "rust-analyzer" or client.name == "clangd" then -- debugging configured for Rust & C/C++
		local dap = require("dap")
		keymap("n", "<leader>dc", dap.continue, vim.tbl_extend("force", opts, { desc = "Debug: continue / start" })) -- Continue / Start
		keymap("n", "<leader>do", dap.step_over, vim.tbl_extend("force", opts, { desc = "Debug: step over" })) -- Step over
		keymap("n", "<leader>di", dap.step_into, vim.tbl_extend("force", opts, { desc = "Debug: step into" })) -- Step into
		keymap("n", "<leader>du", dap.step_out, vim.tbl_extend("force", opts, { desc = "Debug: step out" })) -- Step out
		keymap("n", "<leader>db", dap.toggle_breakpoint, vim.tbl_extend("force", opts, { desc = "Debug: toggle breakpoint" })) -- Toggle breakpoint
		keymap("n", "<leader>dr", dap.repl.open, vim.tbl_extend("force", opts, { desc = "Debug: open REPL" })) -- Open DAP REPL
	end
end

return M
