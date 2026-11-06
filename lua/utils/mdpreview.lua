-- ================================================================================================
-- TITLE : mdpreview
-- ABOUT : <leader>mp under niri : markdown-preview opens in its own browser window, tiled 50/50
--         to the right of the terminal (even if the terminal was fullscreen / maximized), and
--         <leader>mp again closes that window and gives the terminal back its previous state.
--         Outside niri, plain :MarkdownPreviewToggle.
-- ================================================================================================

local M = {}

local BROWSER = "helium-browser"
local state = nil -- { term = id, restore = "fullscreen" | "maximized" | "<n>%", browser = id? }

local function niri(...)
	local res = vim.system({ "niri", "msg", ... }, { text = true }):wait()
	return res.code == 0 and res.stdout or nil
end

local function niri_json(...)
	local out = niri("--json", ...)
	return out and vim.json.decode(out) or nil
end

local function window_ids()
	local ids = {}
	for _, win in ipairs(niri_json("windows") or {}) do
		ids[win.id] = true
	end
	return ids
end

-- how the terminal looks now, to put it back later
local function current_shape(win)
	local out = niri_json("focused-output")
	local w, h = win.layout.tile_size[1], win.layout.tile_size[2]
	local ow, oh = out.logical.width, out.logical.height
	if w >= ow - 1 and h >= oh - 1 then
		return "fullscreen"
	elseif w >= ow * 0.9 then
		return "maximized"
	end
	return math.floor(w / ow * 100 + 0.5) .. "%"
end

-- wait for the browser window that did not exist before, then tile it next to the terminal
local function place_browser(before, tries)
	for _, win in ipairs(niri_json("windows") or {}) do
		if not before[win.id] then
			state.browser = win.id
			niri("action", "set-window-width", "--id", tostring(win.id), "50%")
			niri("action", "focus-window", "--id", tostring(state.term)) -- keep typing in nvim
			return
		end
	end
	if tries > 0 then
		vim.defer_fn(function()
			place_browser(before, tries - 1)
		end, 200)
	end
end

-- g:mkdp_browserfunc : called by markdown-preview with the url of the page
function M.open_url(url)
	if not state then -- :MarkdownPreview typed by hand
		vim.ui.open(url)
		return
	end
	local before = window_ids()
	vim.system({ BROWSER, "--app=" .. url }, { detach = true })
	place_browser(before, 50) -- up to 10 s for the browser to start
end

local function open()
	local term = niri_json("focused-window")
	if not term then
		vim.cmd("MarkdownPreview")
		return
	end
	state = { term = term.id, restore = current_shape(term) }
	if state.restore == "fullscreen" then
		niri("action", "fullscreen-window", "--id", tostring(term.id))
	end
	niri("action", "set-window-width", "--id", tostring(term.id), "50%")
	vim.cmd("MarkdownPreview")
end

local function close()
	vim.cmd("silent! MarkdownPreviewStop")
	local s = state
	state = nil
	if s.browser then
		niri("action", "close-window", "--id", tostring(s.browser))
	end
	local id = tostring(s.term)
	niri("action", "focus-window", "--id", id)
	if s.restore == "fullscreen" then
		niri("action", "fullscreen-window", "--id", id)
	elseif s.restore == "maximized" then
		niri("action", "maximize-column")
	else
		niri("action", "set-window-width", "--id", id, s.restore)
	end
end

function M.toggle()
	if not vim.env.NIRI_SOCKET or vim.fn.executable("niri") == 0 or vim.fn.executable(BROWSER) == 0 then
		vim.cmd("MarkdownPreviewToggle")
	elseif state then
		close()
	else
		open()
	end
end

-- quitting nvim with the preview open : still put the terminal back
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("MdPreviewNiri", {}),
	callback = function()
		if state then
			close()
		end
	end,
})

return M
