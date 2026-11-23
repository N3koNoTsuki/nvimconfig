-- Palette de commandes façon VS Code (Ctrl+Maj+P / Espace P) : un seul picker Snacks avec
--   1. les actions de nide (raccourcis qui ont une description, touche affichée)
--   2. les commandes utilisateur (:Run, :Tuto, :NideDoctor…)
--   3. les commandes Ex de Neovim
-- Entrée exécute l'élément choisi.
local M = {}

-- Actions sans raccourci (ajoutées si la commande existe et qu'aucun raccourci ne porte ce nom)
local extra = {
	{ "Docteur (bilan de l'installation)", "NideDoctor" },
	{ "Nouveau projet", "NideNew" },
	{ "Tutoriel / prise en main", "Tuto" },
	{ "Rejouer l'intro animée", "NideIntro" },
	{ "Nouveau notebook", "NotebookNew" },
	{ "Régénérer la base clangd (C/C++)", "CompileDb" },
	{ "Santé de Neovim (checkhealth)", "checkhealth" },
	{ "Mettre à jour les plugins", "Lazy update" },
}

-- Touche lisible : <leader>r → « Espace r », <C-S-p> → « Ctrl+Maj+p »
local mods = { C = "Ctrl", S = "Maj", M = "Alt", A = "Alt", D = "Cmd" }
function M.keyname(lhs)
	local s = vim.fn.keytrans(vim.keycode(lhs))
	s = s:gsub("<Space>", " Espace "):gsub("<lt>", "<"):gsub("<Bslash>", "\\")
	s = s:gsub("<([^<>]+)>", function(inner)
		local parts = vim.split(inner, "-", { plain = true })
		if #parts == 1 then
			return " " .. inner .. " "
		end
		local key = table.remove(parts)
		for i, m in ipairs(parts) do
			parts[i] = mods[m] or m
		end
		return " " .. table.concat(parts, "+") .. "+" .. key .. " "
	end)
	return vim.trim((s:gsub("%s+", " ")))
end

local function skip(km)
	local desc = km.desc
	return not desc
		or desc == ""
		or desc == "which_key_ignore"
		or km.lhs:find("^<Plug>")
		or km.lhs:find("^<SNR>")
		or km.lhs:find("Mouse>")
		or km.lhs:find("Drag>")
		or km.lhs:find("Release>")
end

--- Construit la liste (dans le buffer courant : ses raccourcis locaux comptent)
function M.items()
	local items, by_desc = {}, {}
	local maps = vim.api.nvim_buf_get_keymap(0, "n")
	vim.list_extend(maps, vim.api.nvim_get_keymap("n"))
	for _, km in ipairs(maps) do
		if not skip(km) then
			local it = by_desc[km.desc]
			local key = M.keyname(km.lhs)
			if it then -- même action sur plusieurs touches : F6 / Espace r
				if not vim.list_contains(it.keys, key) then
					table.insert(it.keys, key)
				end
			else
				it = { kind = "action", label = km.desc, keys = { key }, km = km }
				by_desc[km.desc] = it
				table.insert(items, it)
			end
		end
	end
	local cmds = vim.api.nvim_get_commands({})
	for k, v in pairs(vim.api.nvim_buf_get_commands(0, {})) do
		if type(k) == "string" then
			cmds[k] = v
		end
	end
	local rhs = {} -- commandes déjà accessibles par un raccourci
	for _, km in ipairs(maps) do
		local c = (km.rhs or ""):match("^<[Cc]md>(.-)<[Cc][Rr]>$") or (km.rhs or ""):match("^:(.-)<[Cc][Rr]>$")
		if c then
			rhs[c] = true
		end
	end
	for _, e in ipairs(extra) do
		local name = e[2]:match("^%S+")
		local exists = cmds[name] or vim.fn.exists(":" .. name) == 2
		if exists and not by_desc[e[1]] and not rhs[e[2]] then
			table.insert(items, { kind = "action", label = e[1], keys = { ":" .. e[2] }, cmd = e[2] })
		end
	end
	-- actions par ordre alphabétique, celles de Neovim (« :bnext »…) à la fin
	table.sort(items, function(a, b)
		local na, nb = a.label:sub(1, 1) == ":", b.label:sub(1, 1) == ":"
		if na ~= nb then
			return nb
		end
		return a.label:lower() < b.label:lower()
	end)
	local names = vim.tbl_keys(cmds)
	table.sort(names)
	for _, name in ipairs(names) do
		local c = cmds[name]
		local desc = c.definition ~= "" and c.definition or nil
		table.insert(items, { kind = "user", label = ":" .. name, desc = desc, name = name, nargs = c.nargs })
	end
	for _, name in ipairs(vim.fn.getcompletion("", "command")) do
		if not cmds[name] and name:find("^%l") then
			table.insert(items, { kind = "ex", label = ":" .. name, name = name })
		end
	end
	for i, it in ipairs(items) do
		it.idx = i
		it.key = it.keys and table.concat(it.keys, " / ") or nil
		it.text = table.concat({ it.label, it.key or "", it.desc or "", it.km and it.km.lhs or "" }, " ")
		it.score_add = it.kind == "action" and 40 or it.kind == "user" and 20 or 0
	end
	return items
end

--- Exécute un élément (dans la fenêtre d'origine)
function M.run(it)
	if it.kind == "action" and it.km then
		local km = it.km
		local cmd = (km.rhs or ""):match("^<[Cc]md>([^<]*)<[Cc][Rr]>$")
		if km.callback and km.expr ~= 1 then
			km.callback()
		elseif cmd then
			vim.cmd(cmd)
		else
			vim.api.nvim_feedkeys(vim.keycode(km.lhs), "m", false)
		end
	elseif it.cmd then
		vim.cmd(it.cmd)
	elseif it.kind == "user" and (it.nargs == "0" or it.nargs == "?" or it.nargs == "*") then
		vim.cmd(it.name)
	else
		-- arguments attendus (ou commande Ex) : ligne de commande pré-remplie, Entrée pour valider
		vim.api.nvim_feedkeys(":" .. it.name .. (it.kind == "user" and " " or ""), "n", false)
	end
end

local tags = { action = { "action ", "Function" }, user = { "cmd    ", "Keyword" }, ex = { "ex     ", "Comment" } }

function M.open()
	local items = M.items()
	Snacks.picker({
		title = "Palette de commandes",
		items = items,
		layout = { preset = "vscode" },
		matcher = { sort_empty = false },
		sort = { fields = { "score:desc", "idx" } },
		format = function(item)
			local tag = tags[item.kind]
			local ret = { { tag[1], tag[2] }, { item.label, item.kind == "ex" and "Normal" or "SnacksPickerLabel" } }
			if item.key then
				ret[#ret + 1] = { "  " .. item.key, "SnacksPickerKeymapLhs" }
			elseif item.desc then
				ret[#ret + 1] = { "  " .. item.desc, "Comment" }
			end
			return ret
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				vim.schedule(function()
					local ok, err = pcall(M.run, item)
					if not ok then
						vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Palette" })
					end
				end)
			end
		end,
	})
end

return M
