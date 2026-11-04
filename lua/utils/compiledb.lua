-- ================================================================================================
-- TITLE : compiledb
-- ABOUT : clangd only knows a project through compile_commands.json : without it every .c is
--         alone, and <leader>rn / references miss function.c, header.h... This writes one outside
--         the project, in stdpath("cache")/compiledb, from `make -nB` (dry run, nothing is compiled)
--         or from the *.c files of the folder when there is no Makefile. clangd gets its folder with
--         --compile-commands-dir (lua/servers/clangd.lua). Rebuilt once per session for each project;
--         :CompileDb to rebuild it right away (new .c, Makefile changed).
--         A compile_commands.json already in the project (cmake, bear...) is left alone and used.
-- ================================================================================================

local M = {}

local DB = "compile_commands.json"

-- where the project stops : the git root, else $HOME
local function boundary(dir)
	local git = vim.fs.root(dir, ".git")
	return git or vim.env.HOME
end

local function find_up(dir, name)
	local stop = boundary(dir)
	local found = vim.fs.find(name, { path = dir, upward = true, stop = vim.fs.dirname(stop) })[1]
	return found
end

-- compiler lines of `make -nB`, turned into one entry per .c file
local function from_make(dir)
	local res = vim.system({ "make", "-nB" }, { cwd = dir, text = true, timeout = 3000 }):wait()
	if res.code ~= 0 then
		return {}
	end
	local entries = {}
	for _, line in ipairs(vim.split(res.stdout, "\n")) do
		local args = vim.split(vim.trim(line), "%s+", { trimempty = true })
		local cc = args[1] and vim.fs.basename(args[1])
		if cc and (cc:match("gcc") or cc:match("clang") or cc == "cc" or cc:match("g%+%+")) then
			local flags, files, skip = {}, {}, false
			for _, arg in ipairs(vim.list_slice(args, 2)) do
				if skip then
					skip = false
				elseif arg == "-o" then
					skip = true
				elseif arg:match("%.c$") or arg:match("%.cpp$") then
					table.insert(files, arg)
				elseif arg:match("^%-") and arg ~= "-c" then
					table.insert(flags, arg)
				end
			end
			for _, file in ipairs(files) do
				local arguments = vim.list_extend({ args[1] }, flags)
				vim.list_extend(arguments, { "-c", file })
				table.insert(entries, { directory = dir, file = file, arguments = arguments })
			end
		end
	end
	return entries
end

local function from_files(dir)
	local entries = {}
	for name, kind in vim.fs.dir(dir) do
		if kind == "file" and name:match("%.c$") then
			table.insert(entries, { directory = dir, file = name, arguments = { "gcc", "-Wall", "-c", name } })
		end
	end
	return entries
end

-- where the generated file of a project goes
function M.dir_for(root)
	return string.format("%s/compiledb/%s-%s", vim.fn.stdpath("cache"), vim.fs.basename(root), vim.fn.sha256(root):sub(1, 8))
end

-- the project of `dir` : next to its own compile_commands.json if it has one, else its Makefile,
-- else `dir` itself. Second value : true when the project has its own file.
function M.root(dir)
	local own = find_up(dir, DB)
	if own then
		return vim.fs.dirname(own), true
	end
	local makefile = find_up(dir, "Makefile")
	return makefile and vim.fs.dirname(makefile) or dir, false
end

-- write compile_commands.json for the project `root`; returns its path and its number of entries
function M.generate(root)
	local entries = vim.uv.fs_stat(root .. "/Makefile") and from_make(root) or {}
	if #entries == 0 then
		entries = from_files(root)
	end
	if #entries == 0 then
		return nil
	end
	local dir = M.dir_for(root)
	vim.fn.mkdir(dir, "p")
	local path = dir .. "/" .. DB
	local fd = io.open(path, "w")
	if not fd then
		return nil
	end
	fd:write(vim.json.encode(entries))
	fd:close()
	return path, #entries
end

local generated = {} -- projects already done in this session

-- root of the project of `dir`, its generated file written if needed
function M.prepare(dir)
	local root, own = M.root(dir)
	if not own and not generated[root] then
		generated[root] = true
		M.generate(root)
	end
	return root
end

-- the --compile-commands-dir argument for a project, if a generated file exists
function M.args_for(root)
	if not root or select(2, M.root(root)) then
		return {} -- the project's own file is found by clangd itself
	end
	local dir = M.dir_for(root)
	if vim.uv.fs_stat(dir .. "/" .. DB) then
		return { "--compile-commands-dir=" .. dir }
	end
	return {}
end

function M.setup()
	vim.api.nvim_create_user_command("CompileDb", function()
		local root, own = M.root(vim.fn.expand("%:p:h"))
		if own then
			vim.notify(root .. " a déjà son propre " .. DB, vim.log.levels.WARN)
			return
		end
		local path, n = M.generate(root)
		if not path then
			vim.notify("Aucun fichier .c trouvé", vim.log.levels.WARN)
			return
		end
		generated[root] = true
		vim.notify(string.format("%s : %d fichier(s), redémarrage de clangd", root, n))
		vim.cmd("lsp restart clangd")
	end, { desc = "Rebuild the project's compile_commands.json (clangd)" })
end

return M
