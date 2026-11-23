-- clangd ne connaît que les fichiers ouverts tant qu'il n'a pas de compile_commands.json :
-- `gd` sur un appel tombe alors sur le prototype du .h au lieu du corps dans le .c.
-- Si le projet n'en a pas (Makefile simple, TD…), on en génère un dans le cache de nvim
-- à partir de tous les .c / .cpp du projet. Rien n'est écrit dans le projet.
local M = {}

local SOURCES = { c = "cc", cc = "c++", cpp = "c++", cxx = "c++" }
local SKIP = { [".git"] = true, build = true, node_modules = true, [".cache"] = true }
local MAX_FILES = 2000

-- dossier du projet : le premier parent qui contient un de ces marqueurs, sinon le dossier du fichier
M.markers = {
	"compile_commands.json", "compile_flags.txt", ".clangd", "CMakeLists.txt",
	"Makefile", "makefile", "meson.build", "configure.ac", ".git",
}

function M.root(bufnr)
	local file = vim.api.nvim_buf_get_name(bufnr)
	return vim.fs.root(bufnr, M.markers) or (file ~= "" and vim.fs.dirname(file)) or vim.uv.cwd()
end

-- le projet fournit déjà sa base de compilation (cmake, bear, meson…)
local function has_own_db(root)
	for _, p in ipairs({ "compile_commands.json", "build/compile_commands.json", "compile_flags.txt" }) do
		if vim.uv.fs_stat(root .. "/" .. p) then
			return true
		end
	end
	return false
end

local function scan(root)
	local sources, include_dirs, seen = {}, {}, {}
	local function walk(dir, depth)
		if depth > 6 or #sources > MAX_FILES then
			return
		end
		for name, kind in vim.fs.dir(dir) do
			local path = dir .. "/" .. name
			if kind == "directory" and not SKIP[name] and not name:match("^%.") then
				walk(path, depth + 1)
			elseif kind == "file" then
				local ext = name:match("%.(%w+)$")
				if ext and SOURCES[ext] then
					table.insert(sources, { path = path, compiler = SOURCES[ext] })
				end
				if ext and (ext == "h" or ext == "hpp" or ext == "hh" or SOURCES[ext]) and not seen[dir] then
					seen[dir] = true
					table.insert(include_dirs, "-I" .. dir)
				end
			end
		end
	end
	walk(root, 0)
	return sources, include_dirs
end

function M.dir_for(root)
	return vim.fn.stdpath("cache") .. "/compiledb/" .. vim.fn.sha256(root):sub(1, 16)
end

-- (re)génère la base ; renvoie le dossier à donner à clangd, ou nil si le projet a la sienne
function M.generate(root)
	if has_own_db(root) then
		return nil
	end
	local sources, includes = scan(root)
	local entries = {}
	for _, src in ipairs(sources) do
		local args = { src.compiler, "-Wall", "-Wextra" }
		vim.list_extend(args, includes)
		vim.list_extend(args, { "-c", src.path })
		table.insert(entries, { directory = root, file = src.path, arguments = args })
	end
	local dir = M.dir_for(root)
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({ vim.json.encode(entries) }, dir .. "/compile_commands.json")
	return dir
end

-- :CompileDb : à relancer après avoir ajouté un .c au projet
function M.refresh()
	local root = M.root(0)
	local dir = M.generate(root)
	vim.cmd("lsp restart clangd")
	vim.notify(dir and ("compile_commands.json régénéré pour " .. root) or "Le projet a sa propre base de compilation")
end

return M
