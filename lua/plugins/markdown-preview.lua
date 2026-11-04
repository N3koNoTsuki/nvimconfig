return {
	"iamcco/markdown-preview.nvim",
	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	build = function()
		vim.fn["mkdp#util#install"]()
	end,
	init = function()
		vim.g.mkdp_filetypes = { "markdown" }
		vim.g.mkdp_auto_close = 0 -- the window is closed by <leader>mp, not when leaving the buffer
		-- open the page in a niri-tiled window (lua/utils/mdpreview.lua)
		vim.cmd([[
			function! MkdpOpenNiri(url) abort
				call v:lua.require'utils.mdpreview'.open_url(a:url)
			endfunction
		]])
		vim.g.mkdp_browserfunc = "MkdpOpenNiri"
	end,
	ft = { "markdown" },
}
