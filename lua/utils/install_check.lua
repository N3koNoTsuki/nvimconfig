-- Used by install.sh : writes what the config expects against what is really installed.
local M = {}

local function compare(lines, label, wanted, installed)
	local absent = vim.tbl_filter(function(name)
		return not vim.list_contains(installed, name)
	end, wanted)
	table.insert(lines, ("%s: %d/%d"):format(label, #wanted - #absent, #wanted))
	if #absent > 0 then
		table.insert(lines, ("missing %s: %s"):format(label, table.concat(absent, " ")))
	end
end

function M.write_report(path)
	local lines = { "theme: " .. tostring(vim.g.colors_name) }

	local plugins = require("lazy").plugins()
	local names, installed = {}, {}
	for _, plugin in ipairs(plugins) do
		table.insert(names, plugin.name)
		if plugin._.installed then
			table.insert(installed, plugin.name)
		end
	end
	compare(lines, "plugins", names, installed)

	compare(lines, "parsers", vim.g.treesitter_parsers, require("nvim-treesitter.config").get_installed())

	local installer = require("lazy.core.config").plugins["mason-tool-installer.nvim"]
	local tools = require("lazy.core.plugin").values(installer, "opts", false).ensure_installed
	local packages = vim.fn.stdpath("data") .. "/mason/packages"
	compare(lines, "mason tools", tools, vim.fn.isdirectory(packages) == 1 and vim.fn.readdir(packages) or {})

	local cord = vim.fn.stdpath("data") .. "/cord/bin/cord"
	table.insert(lines, "cord: " .. tostring(vim.fn.executable(cord) == 1))

	vim.fn.writefile(lines, path)
end

return M
