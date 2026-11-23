-- ============================================================================
--  Tutoriel interactif de nvim-ide
--  :Tuto  ou  <Espace>?
--
--  Un onglet dédié : à gauche le panneau de leçon, à droite un vrai fichier
--  d'entraînement (dans stdpath("cache")/tuto). Chaque étape peut avoir :
--    setup(ctx)  prépare le fichier / l'état
--    check(ctx)  renvoie true quand la mission est réussie (vérifié toutes
--                les 250 ms, avec les touches tapées et les filetypes vus)
--    module      id d'un module de nide (lua/nide/modules.lua) dont dépend
--                l'étape (ou tout le chapitre) : s'il est désactivé, l'étape
--                devient une simple lecture (ni setup, ni mission)
-- ============================================================================
local M = {}

local api = vim.api
local W = 54 -- largeur du panneau
local DIR = vim.fn.stdpath("cache") .. "/tuto"
local PROGRESS = vim.fn.stdpath("data") .. "/tuto.json"
local ns = api.nvim_create_namespace("tuto")
local key_ns = api.nvim_create_namespace("tuto_keys")

local S = nil -- état de la session ouverte
local P = { done = {}, last = { 1, 1 } } -- progression sauvegardée

local function lessons()
	return require("tuto.lessons")
end

-- ---------------------------------------------------------------------------
-- Progression
-- ---------------------------------------------------------------------------
local function load_progress()
	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(PROGRESS), "\n"))
	end)
	if ok and type(data) == "table" then
		P.done = type(data.done) == "table" and data.done or {}
		P.last = type(data.last) == "table" and data.last or { 1, 1 }
	end
end

local function save_progress()
	pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(PROGRESS, ":h"), "p")
		vim.fn.writefile({ vim.json.encode(P) }, PROGRESS)
	end)
end

local function step_id(ci, si)
	return lessons()[ci].id .. "/" .. si
end

local function is_done(ci, si)
	return P.done[step_id(ci, si)] == true
end

--- Module désactivé dont dépend l'étape (son libellé), sinon nil
local function step_off(ci, si)
	local ch = lessons()[ci]
	local id = ch.steps[si].module or ch.module
	if not id then
		return nil
	end
	local ok, mods = pcall(require, "nide.modules")
	if not ok or not mods.by_id[id] or mods.enabled(id) then
		return nil
	end
	return mods.by_id[id].label
end

local function chapter_progress(ci)
	local ch, n = lessons()[ci], 0
	for si = 1, #ch.steps do
		n = n + (is_done(ci, si) and 1 or 0)
	end
	return n, #ch.steps
end

local function total_progress()
	local done, total = 0, 0
	for ci = 1, #lessons() do
		local d, t = chapter_progress(ci)
		done, total = done + d, total + t
	end
	return done, total
end

-- ---------------------------------------------------------------------------
-- Couleurs
-- ---------------------------------------------------------------------------
local function set_hl()
	local links = {
		TutoHeader = "Title",
		TutoChapter = "Function",
		TutoStepTitle = "Title",
		TutoKey = "Special",
		TutoDone = "DiagnosticOk",
		TutoTodo = "DiagnosticWarn",
		TutoMuted = "Comment",
		TutoMission = "DiagnosticInfo",
		TutoSection = "Statement",
		TutoBarEmpty = "NonText",
	}
	for group, target in pairs(links) do
		api.nvim_set_hl(0, group, { link = target, default = true })
	end
end
set_hl()
api.nvim_create_autocmd("ColorScheme", {
	group = api.nvim_create_augroup("tuto_hl", { clear = true }),
	callback = set_hl,
})

-- ---------------------------------------------------------------------------
-- Fenêtres
-- ---------------------------------------------------------------------------
local function tab_valid()
	return S and S.tab and api.nvim_tabpage_is_valid(S.tab)
end

local function is_float(win)
	return api.nvim_win_get_config(win).relative ~= ""
end

local function panel_valid()
	return S and S.panel and api.nvim_win_is_valid(S.panel) and api.nvim_win_get_buf(S.panel) == S.pbuf
end

-- fenêtres "normales" de l'onglet, sans le panneau ni les flottantes
local function normal_wins()
	if not tab_valid() then
		return {}
	end
	return vim.tbl_filter(function(w)
		return w ~= S.panel and not is_float(w)
	end, api.nvim_tabpage_list_wins(S.tab))
end

-- la fenêtre d'entraînement (retrouvée si l'utilisateur l'a fermée)
local function practice_win()
	if S.pwin and api.nvim_win_is_valid(S.pwin) and not is_float(S.pwin) and S.pwin ~= S.panel then
		if api.nvim_win_get_tabpage(S.pwin) == S.tab then
			return S.pwin
		end
	end
	local wins = normal_wins()
	-- de préférence une fenêtre qui n'est pas un panneau de plugin
	for _, w in ipairs(wins) do
		local ft = vim.bo[api.nvim_win_get_buf(w)].filetype
		if not ft:match("^snacks_") and ft ~= "trouble" and ft ~= "aerial" and vim.bo[api.nvim_win_get_buf(w)].buftype == "" then
			S.pwin = w
			return w
		end
	end
	if wins[1] then
		S.pwin = wins[1]
		return wins[1]
	end
	-- plus aucune fenêtre : on en recrée une à droite du panneau
	if api.nvim_get_current_tabpage() == S.tab and panel_valid() then
		S.pwin = api.nvim_open_win(api.nvim_create_buf(true, false), false, { split = "right", win = S.panel })
		pcall(api.nvim_win_set_width, S.panel, W)
		return S.pwin
	end
	return nil
end

local function set_panel_opts(win)
	local wo = vim.wo[win]
	wo.number = false
	wo.relativenumber = false
	wo.signcolumn = "no"
	wo.foldcolumn = "0"
	wo.statuscolumn = ""
	wo.cursorline = false
	wo.wrap = true
	wo.linebreak = true
	wo.breakindent = true
	wo.list = false
	wo.spell = false
	wo.winfixwidth = true
	wo.colorcolumn = ""
	pcall(function()
		wo.winbar = ""
	end)
end

local function ensure_panel()
	if panel_valid() or api.nvim_get_current_tabpage() ~= S.tab then
		return
	end
	local anchor = normal_wins()[1]
	local cfg = { split = "left", width = W }
	if anchor then
		cfg.win = anchor
	end
	local ok, win = pcall(api.nvim_open_win, S.pbuf, false, cfg)
	if ok then
		S.panel = win
		set_panel_opts(win)
		M.render()
	end
end

-- ---------------------------------------------------------------------------
-- Touches tapées (pour vérifier les missions)
-- ---------------------------------------------------------------------------
-- <C-N> et <c-n> sont la même touche, mais K et k non : on ne met en minuscule
-- que ce qui est entre < >
local function norm(s)
	return (s:gsub("<[^>]+>", string.lower))
end

local function on_key(_, typed)
	if not S or not typed or typed == "" then
		return
	end
	local ok, k = pcall(vim.fn.keytrans, typed)
	if ok and k then
		S.keys = S.keys .. norm(k)
		if #S.keys > 4000 then
			S.keys = S.keys:sub(-2000)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Contexte passé aux étapes
-- ---------------------------------------------------------------------------
local function practice_maps(buf)
	if not api.nvim_buf_is_valid(buf) or vim.b[buf].tuto_maps then
		return
	end
	vim.b[buf].tuto_maps = true
	local o = function(desc)
		return { buffer = buf, desc = "Tutoriel : " .. desc }
	end
	vim.keymap.set("n", "<M-n>", function() M.next() end, o("étape suivante"))
	vim.keymap.set("n", "<M-p>", function() M.prev() end, o("étape précédente"))
	vim.keymap.set("n", "<M-m>", function() M.menu() end, o("carte"))
	vim.keymap.set("n", "<M-r>", function() M.reset_step() end, o("recommencer l'étape"))
end

local function make_ctx()
	local ctx = { dir = DIR, state = {} }

	function ctx.path(name)
		return DIR .. "/" .. name
	end

	-- écrit `lines` dans un fichier et l'ouvre dans la fenêtre d'entraînement
	function ctx.open(name, lines, opts)
		opts = opts or {}
		local path = ctx.path(name)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		if lines then
			vim.fn.writefile(lines, path)
		end
		local win = practice_win()
		if not win then
			return nil
		end
		api.nvim_win_call(win, function()
			-- opts.keep : réutilise le buffer déjà chargé (garde le kernel et les sorties d'un notebook)
			if opts.keep and not lines and vim.fn.bufloaded(path) == 1 then
				vim.cmd("silent! keepalt buffer " .. vim.fn.bufnr(path))
			else
				vim.cmd("silent! keepalt edit! " .. vim.fn.fnameescape(path))
			end
		end)
		local buf = api.nvim_win_get_buf(win)
		ctx.buf = buf
		vim.b[buf].disable_autoformat = true
		practice_maps(buf)
		local pos = opts.cursor or { 1, 0 }
		if opts.at then
			pos = ctx.find(opts.at, opts.nth) or pos
		end
		pcall(api.nvim_win_set_cursor, win, pos)
		return buf
	end

	-- ajoute un fichier aux buffers ouverts sans l'afficher
	function ctx.badd(name)
		local path = ctx.path(name)
		vim.cmd("badd " .. vim.fn.fnameescape(path))
		ctx.keep = ctx.keep or {}
		ctx.keep[vim.fn.bufnr(path)] = true
	end

	function ctx.cd(sub)
		local d = sub and ctx.path(sub) or DIR
		vim.fn.mkdir(d, "p")
		local win = practice_win()
		if win then
			api.nvim_win_call(win, function()
				vim.cmd("tcd " .. vim.fn.fnameescape(d))
			end)
		end
	end

	function ctx.lines()
		if ctx.buf and api.nvim_buf_is_valid(ctx.buf) then
			return api.nvim_buf_get_lines(ctx.buf, 0, -1, false)
		end
		return {}
	end

	-- lignes sans les espaces de début / fin
	function ctx.tlines()
		return vim.tbl_map(vim.trim, ctx.lines())
	end

	function ctx.text()
		return table.concat(ctx.lines(), "\n")
	end

	function ctx.has(s)
		return ctx.text():find(s, 1, true) ~= nil
	end

	function ctx.count(s)
		local n, i, text = 0, 1, ctx.text()
		while true do
			local a, b = text:find(s, i, true)
			if not a then
				return n
			end
			n, i = n + 1, b + 1
		end
	end

	-- position {ligne, colonne} de la nième occurrence de `s`
	function ctx.find(s, nth)
		nth = nth or 1
		for row, line in ipairs(ctx.lines()) do
			local i = 1
			while true do
				local a = line:find(s, i, true)
				if not a then
					break
				end
				nth = nth - 1
				if nth == 0 then
					return { row, a - 1 }
				end
				i = a + 1
			end
		end
	end

	-- fenêtre "active" : la courante si c'est une fenêtre normale, sinon celle d'entraînement
	function ctx.win()
		local cur = api.nvim_get_current_win()
		if cur ~= S.panel and not is_float(cur) and api.nvim_win_get_tabpage(cur) == S.tab then
			return cur
		end
		return practice_win()
	end

	-- fenêtre active si elle affiche le fichier de l'étape, sinon une autre qui l'affiche
	local function buf_win()
		local win = ctx.win()
		if not ctx.buf or (win and api.nvim_win_get_buf(win) == ctx.buf) then
			return win
		end
		for _, w in ipairs(normal_wins()) do
			if api.nvim_win_get_buf(w) == ctx.buf then
				return w
			end
		end
		return nil
	end

	function ctx.cursor()
		local win = buf_win()
		return win and api.nvim_win_get_cursor(win) or { 0, 0 }
	end

	function ctx.row()
		return ctx.cursor()[1]
	end

	function ctx.word()
		local win = buf_win()
		if not win then
			return ""
		end
		return api.nvim_win_call(win, function()
			return vim.fn.expand("<cword>")
		end)
	end

	function ctx.cur_name()
		local win = ctx.win()
		return win and api.nvim_buf_get_name(api.nvim_win_get_buf(win)) or ""
	end

	-- un fichier finissant par `suffix` est affiché dans une fenêtre normale
	function ctx.visible(suffix)
		for _, w in ipairs(normal_wins()) do
			if vim.endswith(api.nvim_buf_get_name(api.nvim_win_get_buf(w)), suffix) then
				return true
			end
		end
		return false
	end

	function ctx.visible_ft(ft)
		if not tab_valid() then
			return false
		end
		for _, w in ipairs(api.nvim_tabpage_list_wins(S.tab)) do
			if vim.bo[api.nvim_win_get_buf(w)].filetype == ft then
				return true
			end
		end
		return false
	end

	-- ce filetype a été ouvert depuis le début de l'étape (ou est affiché)
	function ctx.seen(ft)
		return S.seen[ft] == true or ctx.visible_ft(ft)
	end

	-- une fenêtre flottante de documentation est ouverte
	function ctx.has_float()
		if not tab_valid() then
			return false
		end
		for _, w in ipairs(api.nvim_tabpage_list_wins(S.tab)) do
			if is_float(w) then
				local ft = vim.bo[api.nvim_win_get_buf(w)].filetype
				if ft == "markdown" or ft == "noice" or ft == "lsp_markdown" then
					return true
				end
			end
		end
		return false
	end

	-- `keys` a été tapé depuis le début de l'étape (ex: "<Space>ff", "<C-n>", "gd")
	function ctx.typed(keys)
		return S.keys:find(norm(keys), 1, true) ~= nil
	end

	function ctx.typed_count(keys)
		local n, i, k = 0, 1, norm(keys)
		while true do
			local a, b = S.keys:find(k, i, true)
			if not a then
				return n
			end
			n, i = n + 1, b + 1
		end
	end

	function ctx.mode()
		return api.nvim_get_mode().mode
	end

	function ctx.in_panel()
		return api.nvim_get_current_win() == S.panel
	end

	function ctx.in_practice()
		local cur = api.nvim_get_current_win()
		return cur ~= S.panel and not is_float(cur) and api.nvim_win_get_tabpage(cur) == S.tab
	end

	function ctx.focus_panel()
		if panel_valid() then
			api.nvim_set_current_win(S.panel)
		end
	end

	function ctx.wins()
		return normal_wins()
	end

	function ctx.sh(cmd)
		return vim.fn.system(cmd), vim.v.shell_error
	end

	return ctx
end

-- ---------------------------------------------------------------------------
-- Rendu du panneau
-- ---------------------------------------------------------------------------
local function split_text(t)
	if t == nil then
		return {}
	end
	if type(t) == "table" then
		local out = {}
		for _, l in ipairs(t) do
			vim.list_extend(out, vim.split(l, "\n", { plain = true }))
		end
		return out
	end
	return vim.split(t, "\n", { plain = true })
end

function M.render()
	if not S or not api.nvim_buf_is_valid(S.pbuf) then
		return
	end
	local L = lessons()
	local ch = L[S.ci]
	local st = ch.steps[S.si]
	local lines, hls = {}, {}

	local function push(text, group)
		lines[#lines + 1] = text
		if group then
			hls[#hls + 1] = { #lines - 1, 0, #text, group }
		end
	end
	-- les `morceaux entre accents graves` sont mis en couleur de touche
	local function rich(prefix, text, group)
		local out, ranges, i = prefix, {}, 1
		while true do
			local a, b, inner = text:find("`([^`]+)`", i)
			if not a then
				out = out .. text:sub(i)
				break
			end
			out = out .. text:sub(i, a - 1)
			local start = #out
			out = out .. inner
			ranges[#ranges + 1] = { start, #out }
			i = b + 1
		end
		push(out, group)
		for _, r in ipairs(ranges) do
			hls[#hls + 1] = { #lines - 1, r[1], r[2], "TutoKey" }
		end
	end
	local function hl(row, a, b, group)
		hls[#hls + 1] = { row, a, b, group }
	end

	-- En-tête
	push(" NVIM-IDE · Prise en main", "TutoHeader")
	local done, total = total_progress()
	local barw = 28
	local filled = math.floor(barw * done / math.max(total, 1) + 0.5)
	local bar_done, bar_rest = string.rep("█", filled), string.rep("░", barw - filled)
	push(" " .. bar_done .. bar_rest .. string.format("  %d/%d", done, total))
	hl(#lines - 1, 1, 1 + #bar_done, "TutoDone")
	hl(#lines - 1, 1 + #bar_done, 1 + #bar_done + #bar_rest, "TutoBarEmpty")
	push("")

	push(string.format(" ▶ Chapitre %d/%d · %s", S.ci - 1, #L - 1, ch.title), "TutoChapter")
	-- pastilles des étapes
	local dots, ranges = "   étape " .. S.si .. "/" .. #ch.steps .. "  ", {}
	for si = 1, #ch.steps do
		local d = (si == S.si) and "◆" or (is_done(S.ci, si) and "●" or "○")
		local a = #dots
		dots = dots .. d
		ranges[#ranges + 1] = { a, #dots, is_done(S.ci, si) and "TutoDone" or (si == S.si and "TutoTodo" or "TutoMuted") }
	end
	push(dots, "TutoMuted")
	for _, r in ipairs(ranges) do
		hl(#lines - 1, r[1], r[2], r[3])
	end
	push(" " .. string.rep("─", W - 3), "TutoMuted")
	push("")

	-- Étape
	push(" " .. st.title, "TutoStepTitle")
	push("")
	for _, l in ipairs(split_text(st.text)) do
		rich(" ", l)
	end

	if st.keys and #st.keys > 0 then
		push("")
		push(" RACCOURCIS", "TutoSection")
		for _, kv in ipairs(st.keys) do
			local k = kv[1]
			local pad = string.rep(" ", math.max(1, 14 - vim.fn.strdisplaywidth(k)))
			push("   " .. k .. pad .. kv[2])
			hl(#lines - 1, 3, 3 + #k, "TutoKey")
		end
	end

	push("")
	local off = step_off(S.ci, S.si)
	if off then
		push(" MODULE DÉSACTIVÉ", "TutoSection")
		rich("   ", "Le module " .. off .. " n'est pas installé : cette étape se lit seulement.", "TutoMuted")
		rich("   ", "Pour l'activer : relance ~/.config/nvim/install.sh", "TutoMuted")
		push("")
	end
	if st.mission and not off then
		push(" MISSION", "TutoSection")
		for _, l in ipairs(split_text(st.mission)) do
			rich("   ", l, "TutoMission")
		end
		push("")
		if is_done(S.ci, S.si) then
			push("   ✓ Réussi !", "TutoDone")
		else
			push("   … à toi de jouer", "TutoTodo")
		end
	else
		if is_done(S.ci, S.si) then
			push("   ✓ Lu", "TutoDone")
		else
			rich("   ", "▸ Essaie si tu veux, puis `n` (ou `Alt-n`) pour continuer.", "TutoMuted")
		end
	end
	if st.hint then
		push("")
		for _, l in ipairs(split_text(st.hint)) do
			rich(" ", "Astuce : " .. l, "TutoMuted")
		end
	end

	-- Pied de page, collé en bas si la place le permet
	local footer = {
		" " .. string.rep("─", W - 3),
		" `n`/`→` suivant  `p`/`←` précédent  `m` carte",
		" `r` recommencer  `<Tab>` pratique  `q` quitter",
		" Depuis la pratique : `Alt-n` `Alt-p` `Alt-m` `Alt-r`",
	}
	local height = panel_valid() and api.nvim_win_get_height(S.panel) or 0
	local need = height - #lines - #footer
	-- les lignes longues prennent plusieurs lignes d'écran : estimation large
	for _, l in ipairs(lines) do
		need = need - math.floor(vim.fn.strdisplaywidth(l) / (W - 1))
	end
	push("")
	for _ = 1, math.max(0, need - 1) do
		push("")
	end
	for _, l in ipairs(footer) do
		rich("", l, "TutoMuted")
	end

	vim.bo[S.pbuf].modifiable = true
	api.nvim_buf_set_lines(S.pbuf, 0, -1, false, lines)
	vim.bo[S.pbuf].modifiable = false
	vim.bo[S.pbuf].modified = false
	api.nvim_buf_clear_namespace(S.pbuf, ns, 0, -1)
	for _, h in ipairs(hls) do
		pcall(api.nvim_buf_set_extmark, S.pbuf, ns, h[1], h[2], {
			end_col = h[3],
			hl_group = h[4],
			priority = h[4] == "TutoKey" and 200 or 100,
		})
	end
	if panel_valid() then
		pcall(api.nvim_win_set_cursor, S.panel, { 1, 0 })
	end
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

-- Ferme les fichiers d'exercice des étapes précédentes : seuls restent ceux
-- affichés dans une fenêtre et ceux que l'étape courante a ajoutés (ctx.badd).
local function close_old_practice_buffers(keep)
	local visible = {}
	for _, w in ipairs(api.nvim_list_wins()) do
		visible[api.nvim_win_get_buf(w)] = true
	end
	for _, b in ipairs(api.nvim_list_bufs()) do
		-- un buffer supprimé peut en emporter d'autres (notebook → son buffer otter)
		local name = api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) or ""
		if name:sub(1, #DIR + 1) == DIR .. "/" and not visible[b] and not keep[b] then
			pcall(api.nvim_buf_delete, b, { force = true })
		end
	end
end

local function goto_step(ci, si)
	local L = lessons()
	if not L[ci] or not L[ci].steps[si] then
		return
	end
	S.ci, S.si = ci, si
	S.keys, S.seen, S.pending = "", {}, false
	S.token = (S.token or 0) + 1
	S.ctx.state = {}
	P.last = { ci, si }
	save_progress()
	local st = L[ci].steps[si]
	S.ctx.keep = {}
	if st.setup and not step_off(ci, si) then
		local ok, err = pcall(st.setup, S.ctx)
		if not ok then
			vim.notify("Tutoriel : préparation de l'étape impossible\n" .. tostring(err), vim.log.levels.WARN)
		end
	end
	close_old_practice_buffers(S.ctx.keep)
	M.render()
end

function M.jump(ci, si)
	if S then
		goto_step(ci, si or 1)
	end
end

function M.next(auto)
	if not S then
		return
	end
	local L = lessons()
	local st = L[S.ci].steps[S.si]
	if (not st.check or step_off(S.ci, S.si)) and not auto then
		P.done[step_id(S.ci, S.si)] = true -- étape de lecture : lue
	end
	if S.si < #L[S.ci].steps then
		goto_step(S.ci, S.si + 1)
	elseif S.ci < #L then
		goto_step(S.ci + 1, 1)
	else
		save_progress()
		M.render()
		vim.notify("Tu as fini le tutoriel ! Tout est dans <Espace> (attends le menu) et <Espace>sk.", vim.log.levels.INFO, { title = "Tutoriel" })
	end
end

function M.prev()
	if not S then
		return
	end
	local L = lessons()
	if S.si > 1 then
		goto_step(S.ci, S.si - 1)
	elseif S.ci > 1 then
		goto_step(S.ci - 1, #L[S.ci - 1].steps)
	end
end

function M.reset_step()
	if not S then
		return
	end
	P.done[step_id(S.ci, S.si)] = nil
	goto_step(S.ci, S.si)
end

-- ---------------------------------------------------------------------------
-- Vérification périodique
-- ---------------------------------------------------------------------------
local cleanup

local function advance_later(token)
	vim.defer_fn(function()
		if not S or S.token ~= token then
			return
		end
		local mode = api.nvim_get_mode().mode
		if mode:find("^[ic]") or mode == "t" then -- on attend la fin de la saisie
			return advance_later(token)
		end
		S.pending = false
		M.next(true)
	end, 1200)
end

local function poll()
	if not S then
		return
	end
	if not tab_valid() then
		return cleanup()
	end
	if api.nvim_get_current_tabpage() == S.tab then
		ensure_panel()
	end
	local ch = lessons()[S.ci]
	local st = ch and ch.steps[S.si]
	if not st or not st.check or S.pending or is_done(S.ci, S.si) or step_off(S.ci, S.si) then
		return
	end
	local ok, res = pcall(st.check, S.ctx)
	if ok and res then
		P.done[step_id(S.ci, S.si)] = true
		save_progress()
		M.render()
		vim.notify("Bravo ! ✓ " .. st.title, vim.log.levels.INFO, { title = "Tutoriel" })
		S.pending = true
		advance_later(S.token)
	end
end

-- ---------------------------------------------------------------------------
-- Carte des chapitres
-- ---------------------------------------------------------------------------
function M.menu()
	if not S then
		return
	end
	local L = lessons()
	local buf = api.nvim_create_buf(false, true)
	local lines, hls = {}, {}
	local width = 52
	for ci, ch in ipairs(L) do
		local d, t = chapter_progress(ci)
		local mark = d == t and "✓" or (d > 0 and "◐" or "○")
		local cur = ci == S.ci and "▶" or " "
		local left = string.format(" %s %s %2d. %s", cur, mark, ci - 1, ch.title)
		local right = string.format("%d/%d ", d, t)
		local pad = string.rep(" ", math.max(1, width - vim.fn.strdisplaywidth(left) - #right))
		lines[#lines + 1] = left .. pad .. right
		local group = d == t and "TutoDone" or (ci == S.ci and "TutoTodo" or nil)
		if group then
			hls[#hls + 1] = { #lines - 1, group }
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  Entrée aller · q fermer · X tout remettre à zéro"
	hls[#hls + 1] = { #lines - 1, "TutoMuted" }
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	for _, h in ipairs(hls) do
		pcall(api.nvim_buf_set_extmark, buf, ns, h[1], 0, { end_col = #lines[h[1] + 1], hl_group = h[2] })
	end

	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = #lines,
		row = math.floor((vim.o.lines - #lines) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Carte du tutoriel ",
		title_pos = "center",
	})
	vim.wo[win].cursorline = true
	pcall(api.nvim_win_set_cursor, win, { S.ci, 0 })
	vim.bo[buf].filetype = "tuto_menu" -- déclenche FileType : vu par la mission du chapitre 0

	local function close()
		if api.nvim_win_is_valid(win) then
			api.nvim_win_close(win, true)
		end
	end
	local o = { buffer = buf, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		local ci = api.nvim_win_get_cursor(win)[1]
		close()
		if L[ci] then
			local target = 1
			for si = 1, #L[ci].steps do
				if not is_done(ci, si) then
					target = si
					break
				end
			end
			goto_step(ci, target)
		end
	end, o)
	vim.keymap.set("n", "q", close, o)
	vim.keymap.set("n", "<Esc>", close, o)
	vim.keymap.set("n", "X", function()
		if vim.fn.confirm("Effacer toute la progression du tutoriel ?", "&Oui\n&Non", 2) == 1 then
			P.done = {}
			save_progress()
			close()
			goto_step(1, 1)
		end
	end, o)
	api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
end

-- ---------------------------------------------------------------------------
-- Ouverture / fermeture
-- ---------------------------------------------------------------------------
local function wipe_practice_buffers()
	for _, b in ipairs(api.nvim_list_bufs()) do
		local name = api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) or ""
		if name:sub(1, #DIR + 1) == DIR .. "/" then
			pcall(api.nvim_buf_delete, b, { force = true })
		end
	end
end

cleanup = function()
	if not S then
		return
	end
	local s = S
	S = nil
	if s.timer then
		pcall(function()
			s.timer:stop()
			s.timer:close()
		end)
	end
	vim.on_key(nil, key_ns)
	pcall(api.nvim_del_augroup_by_id, s.group)
	vim.schedule(function()
		wipe_practice_buffers()
		if api.nvim_buf_is_valid(s.pbuf) then
			pcall(api.nvim_buf_delete, s.pbuf, { force = true })
		end
	end)
end

function M.quit()
	if not S then
		return
	end
	local tab = S.tab
	cleanup()
	if api.nvim_tabpage_is_valid(tab) then
		if #api.nvim_list_tabpages() == 1 then
			vim.cmd("tabnew")
		end
		pcall(vim.cmd, "tabclose " .. api.nvim_tabpage_get_number(tab))
	end
end

function M.is_open()
	return tab_valid() and true or false
end

function M.open()
	if tab_valid() then
		api.nvim_set_current_tabpage(S.tab)
		ensure_panel()
		return
	end
	load_progress()
	set_hl()
	vim.fn.mkdir(DIR, "p")

	vim.cmd("tabnew")
	S = {
		tab = api.nvim_get_current_tabpage(),
		pwin = api.nvim_get_current_win(),
		keys = "",
		seen = {},
	}
	vim.cmd("tcd " .. vim.fn.fnameescape(DIR))

	-- Panneau
	S.pbuf = api.nvim_create_buf(false, true)
	vim.bo[S.pbuf].bufhidden = "hide"
	vim.bo[S.pbuf].filetype = "tuto"
	S.panel = api.nvim_open_win(S.pbuf, false, { split = "left", win = S.pwin, width = W })
	set_panel_opts(S.panel)
	local o = function(desc)
		return { buffer = S.pbuf, nowait = true, desc = desc }
	end
	local map = vim.keymap.set
	map("n", "n", function() M.next() end, o("Étape suivante"))
	map("n", "<Right>", function() M.next() end, o("Étape suivante"))
	map("n", "p", function() M.prev() end, o("Étape précédente"))
	map("n", "<Left>", function() M.prev() end, o("Étape précédente"))
	map("n", "m", function() M.menu() end, o("Carte des chapitres"))
	map("n", "r", function() M.reset_step() end, o("Recommencer l'étape"))
	map("n", "q", function() M.quit() end, o("Quitter le tutoriel"))
	map("n", "<Tab>", function()
		local w = practice_win()
		if w then
			api.nvim_set_current_win(w)
		end
	end, o("Aller dans le fichier d'entraînement"))
	map("n", "<M-n>", function() M.next() end, o("Étape suivante"))
	map("n", "<M-p>", function() M.prev() end, o("Étape précédente"))
	map("n", "<M-m>", function() M.menu() end, o("Carte des chapitres"))
	map("n", "<M-r>", function() M.reset_step() end, o("Recommencer l'étape"))

	S.ctx = make_ctx()

	-- Événements
	S.group = api.nvim_create_augroup("tuto_run", { clear = true })
	api.nvim_create_autocmd("FileType", {
		group = S.group,
		callback = function(args)
			if S then
				S.seen[args.match] = true
			end
		end,
	})
	api.nvim_create_autocmd("BufEnter", {
		group = S.group,
		callback = function(args)
			if S and args.file ~= "" and vim.fn.fnamemodify(args.file, ":p"):sub(1, #DIR + 1) == DIR .. "/" then
				practice_maps(args.buf)
			end
		end,
	})
	api.nvim_create_autocmd("TabClosed", {
		group = S.group,
		callback = function()
			vim.schedule(function()
				if S and not tab_valid() then
					cleanup()
				end
			end)
		end,
	})
	api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = S.group,
		callback = function()
			if S then
				M.render()
			end
		end,
	})
	vim.on_key(on_key, key_ns)
	S.timer = vim.uv.new_timer()
	S.timer:start(250, 250, vim.schedule_wrap(function()
		local ok, err = pcall(poll)
		if not ok and S and not S.reported then
			S.reported = true
			vim.notify("Tutoriel : " .. tostring(err), vim.log.levels.WARN)
		end
	end))

	local L = lessons()
	local ci, si = tonumber(P.last[1]) or 1, tonumber(P.last[2]) or 1
	if not L[ci] or not L[ci].steps[si] then
		ci, si = 1, 1
	end
	goto_step(ci, si)
	if ci == 1 then
		api.nvim_set_current_win(S.panel)
	else
		local w = practice_win()
		if w then
			api.nvim_set_current_win(w)
		end
	end
end

function M.reset()
	P = { done = {}, last = { 1, 1 } }
	save_progress()
	if S then
		goto_step(1, 1)
	end
	vim.notify("Progression du tutoriel remise à zéro.", vim.log.levels.INFO, { title = "Tutoriel" })
end

-- pour les tests
M._state = function()
	return S
end
M._progress = function()
	return P
end
M._poll = function()
	return poll()
end

return M
