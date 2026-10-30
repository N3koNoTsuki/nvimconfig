-- ================================================================================================
-- TITLE : git
-- ABOUT : helpers shared by the git keymaps (diffview, fugitive). Made for a mono-repo like
--         INSA/3A/TD : one git repo, one sub-folder per TD/TP. "scope" = that sub-folder, so a diff
--         or a history can be limited to the TD being worked on instead of the whole repo.
-- ================================================================================================

local M = {}

-- directory of the current file, or of the oil listing, or the cwd
local function current_dir()
	local ok, oil = pcall(require, "oil")
	local dir = ok and oil.get_current_dir() or nil
	if not dir then
		dir = vim.bo.buftype == "" and vim.fn.expand("%:p:h") or vim.fn.getcwd()
	end
	return dir
end

-- git top-level of the current file (nil outside a repo)
function M.root()
	local out = vim.fn.systemlist({ "git", "-C", current_dir(), "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 or not out[1] then
		vim.notify("Pas dans un dépôt git", vim.log.levels.WARN)
		return nil
	end
	return out[1]
end

-- first folder under the repo root that contains the current file/dir, e.g. "TD5"
-- (nil at the root of the repo, e.g. on README.md)
function M.scope(root)
	local dir = vim.fs.normalize(current_dir())
	if dir == root then
		return nil
	end
	local rel = dir:sub(#root + 2)
	return rel:match("^[^/]+")
end

-- current file relative to the repo root, e.g. "TD5/main.c"
local function relative_file(root)
	local file = vim.fn.expand("%:p")
	if file == "" or file:sub(1, #root + 1) ~= root .. "/" then
		return nil
	end
	return file:sub(#root + 2)
end

-- :DiffviewOpen on the whole repo (scoped = false) or on the current TD only
function M.diff(scoped)
	local root = M.root()
	if not root then
		return
	end
	local cmd = "DiffviewOpen -C" .. vim.fn.fnameescape(root)
	local scope = scoped and M.scope(root)
	if scope then
		cmd = cmd .. " -- " .. vim.fn.fnameescape(scope)
	end
	vim.cmd(cmd)
end

-- :DiffviewFileHistory of the current file (what = "file") or of the current TD (what = "scope")
function M.history(what)
	local root = M.root()
	if not root then
		return
	end
	local path = what == "file" and relative_file(root) or M.scope(root)
	vim.cmd("DiffviewFileHistory -C" .. vim.fn.fnameescape(root) .. (path and (" " .. vim.fn.fnameescape(path)) or ""))
end

local function in_diffview()
	local ok, lib = pcall(require, "diffview.lib")
	return ok and lib.get_current_view() or nil
end

-- windows of the current tab that show a fugitive:// buffer in diff mode
local function fugitive_diff_wins()
	local wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
		if vim.wo[win].diff and name:match("^fugitive://") then
			table.insert(wins, win)
		end
	end
	return wins
end

-- close the fugitive side(s) of a :Gvdiffsplit and leave the real file, diff off
local function close_fugitive_diff()
	local wins = fugitive_diff_wins()
	if #wins == 0 then
		return false
	end
	for _, win in ipairs(wins) do
		pcall(vim.api.nvim_win_close, win, false) -- fails only if it is the last window
	end
	vim.cmd("diffoff!")
	return true
end

-- leave the diff and land on the real file, at the line under the cursor
function M.jump()
	local view = in_diffview()
	if view then
		require("diffview.actions").goto_file_edit() -- opens the working file in the previous tab, same line
		view:close()
		require("diffview.lib").dispose_view(view)
		vim.cmd("normal! zz")
		return
	end
	if not close_fugitive_diff() then
		vim.notify("Pas de diff ouvert", vim.log.levels.INFO)
		return
	end
	vim.cmd("normal! zz")
end

-- close the diff, back to where it was opened
function M.close()
	if in_diffview() then
		vim.cmd("DiffviewClose")
	elseif not close_fugitive_diff() then
		vim.notify("Pas de diff ouvert", vim.log.levels.INFO)
	end
end

return M
