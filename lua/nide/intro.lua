-- Intro animée de nide : collision p⁺/p̄ (Manim) qui se termine sur le logo.
-- Jouée une fois sur l'écran d'accueil (dashboard snacks), dans son en-tête ;
-- le logo final reste ensuite comme en-tête du dashboard (image kitty ou demi-blocs).
--
-- Disposition adaptative (M.layout) : le logo existe en plusieurs tailles
-- (assets/intro/logo_CxR.lua). À chaque rendu du dashboard (redimensionnement
-- compris), on prend la plus grande qui laisse tout le dashboard dans la fenêtre,
-- en resserrant d'abord les espacements, puis en réduisant le logo, puis en
-- masquant la ligne de démarrage et les fichiers récents ; en dernier recours,
-- un simple titre « nide ». L'intro se joue dans la boîte du logo choisi.
--
-- Deux moteurs :
--   kitty  : protocole graphique kitty. Les frames PNG sont envoyées une fois
--            (a=t puis a=f) et c'est le terminal qui joue l'animation (a=a,s=2).
--            Affichage par « placeholders Unicode » (U=1) : l'image suit la grille
--            de nvim. Dans le dashboard, les placeholders sont les lignes mêmes de
--            l'en-tête ; leur couleur (= id d'image) désigne l'animation pendant
--            l'intro, puis le logo final (dernière frame, image LOGO_ID transmise une
--            fois et réutilisée, placement ajusté à la taille choisie par M.layout).
--            Sans réponse du terminal : repli sur le logo demi-blocs.
--            Hors dashboard (:NideIntro ailleurs) : fenêtre flottante.
--   blocks : repli universel, demi-blocs ▀ en couleurs 24 bits (extmarks + timer).
--
-- Options :
--   vim.g.nide_intro = false                       pas d'intro (logo gardé)
--   vim.g.nide_intro_mode = "auto"|"kitty"|"blocks" moteur (défaut auto)
-- Commande : :NideIntro rejoue l'intro.
-- Données : assets/intro/ (intro/install_intro.sh les y recopie après un rendu) :
--   kitty/ (PNG), blocks_CxR.lua (toutes les frames), logo_CxR.lua (dernière frame).
local M = {}
local api, uv = vim.api, vim.uv

M.dir = vim.fn.stdpath("config") .. "/assets/intro"

local UPPER = "▀" -- demi-bloc haut : fg = pixel du haut, bg = pixel du bas (3 octets)
local IMAGE_ID = 0x4E1DE -- < 2^24 : encodable dans la couleur de premier plan
local LOGO_ID = 0x4E1DF -- logo final (dernière frame) de l'en-tête kitty
local PLACEHOLDER = "\u{10EEEE}"
local K = {} -- moteur kitty (plus bas)
M.kitty = K
local HOLD_MS = 100 -- tenue de la dernière frame (kitty)

-- ---------------------------------------------------------------------------
-- Données demi-blocs, une variante par taille CxR : logo_CxR.lua (dernière
-- frame seule, lue au rendu de l'en-tête) et blocks_CxR.lua (toutes les
-- frames, lue au moment de jouer). Frames décodées à la demande.
-- ---------------------------------------------------------------------------
local cache = {} -- nom de fichier -> données (false si absent)
local hls = {} -- groupes de surbrillance créés : nom -> { fg, bg }

---@class nide.intro.Size
---@field cols integer
---@field rows integer
---@field name string "CxR"

local sizes_cache ---@type nide.intro.Size[]?
--- tailles disponibles, de la plus grande à la plus petite
---@return nide.intro.Size[]
function M.sizes()
	if not sizes_cache then
		local seen, list = {}, {}
		for _, f in ipairs(vim.fn.glob(M.dir .. "/*_*x*.lua", false, true)) do
			local kind, c, r = f:match("/(%a+)_(%d+)x(%d+)%.lua$")
			local name = c and ("%sx%s"):format(c, r)
			if (kind == "logo" or kind == "blocks") and not seen[name] then
				seen[name] = true
				list[#list + 1] = { cols = tonumber(c), rows = tonumber(r), name = name }
			end
		end
		table.sort(list, function(a, b)
			return a.cols * a.rows > b.cols * b.rows
		end)
		sizes_cache = list
	end
	return sizes_cache
end

---@param kind "logo"|"blocks"
---@param size nide.intro.Size
local function load(kind, size)
	local name = kind .. "_" .. size.name
	if cache[name] == nil then
		local ok, d = pcall(dofile, M.dir .. "/" .. name .. ".lua")
		cache[name] = ok and type(d) == "table" and d.frames and d or false
		if cache[name] then
			d.decoded = {}
		elseif kind == "logo" then -- logo absent : on prend la fin de blocks_CxR.lua
			local b = load("blocks", size)
			cache[name] = b and vim.tbl_extend("force", b, { frames = { b.frames[#b.frames] }, decoded = {} }) or false
		end
	end
	return cache[name] or nil
end

--- la plus grande taille qui tient dans cols x rows
local function size_within(cols, rows)
	for _, sz in ipairs(M.sizes()) do
		if sz.cols <= cols and sz.rows <= rows then
			return sz
		end
	end
end

local function set_hl(name, c)
	api.nvim_set_hl(0, name, { fg = c[1], bg = c[2] })
end

-- octet encodé -> index de palette (base 35, '\' sauté à l'encodage)
local function dec(byte)
	local v = byte - 35
	return byte > 92 and v - 1 or v
end

--- frame i de d -> par ligne de cellules, des plages { col_début, col_fin, groupe }
local function frame(d, i)
	if d.decoded[i] then
		return d.decoded[i]
	end
	local s, cols, out = d.frames[i], d.cols, {}
	for r = 0, d.rows - 1 do
		local top, bot = r * 2 * cols, (r * 2 + 1) * cols
		local runs, start, cur = {}, 0, nil
		for c = 0, cols - 1 do
			local t, b = dec(s:byte(top + c + 1)), dec(s:byte(bot + c + 1))
			local name = "NideIntro_" .. t .. "_" .. b
			if not hls[name] then
				hls[name] = { d.palette[t + 1], d.palette[b + 1] }
				set_hl(name, hls[name])
			end
			if name ~= cur then
				if cur then
					runs[#runs + 1] = { start, c, cur }
				end
				start, cur = c, name
			end
		end
		runs[#runs + 1] = { start, cols, cur }
		out[r + 1] = runs
	end
	d.decoded[i] = out
	return out
end

-- ---------------------------------------------------------------------------
-- Choix du moteur
-- ---------------------------------------------------------------------------
local function tmux(args)
	local ok, r = pcall(function()
		return vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait(300)
	end)
	return ok and r.code == 0 and vim.trim(r.stdout or "") or ""
end

local function detect_engine()
	local mode = vim.g.nide_intro_mode
	if mode == "kitty" or mode == "blocks" then
		return mode, "forcé par vim.g.nide_intro_mode"
	end
	local env = vim.env
	if env.TMUX then
		-- tmux : seulement si allow-passthrough est actif et que le terminal hôte est kitty
		local pass = tmux({ "show", "-gv", "allow-passthrough" })
		local host = tmux({ "display", "-p", "#{client_termname}" })
		if (pass == "on" or pass == "all") and host:find("kitty") then
			return "kitty", "kitty via tmux (passthrough)"
		end
		return "blocks", "tmux sans passthrough vers kitty"
	end
	local term, prog = env.TERM or "", env.TERM_PROGRAM or ""
	if (env.KITTY_WINDOW_ID or "") ~= "" or term:find("kitty") then
		return "kitty", "kitty"
	end
	if prog == "ghostty" or term == "xterm-ghostty" then
		-- animations kitty prises en charge à partir de ghostty 1.4
		local maj, min = (env.TERM_PROGRAM_VERSION or ""):match("^(%d+)%.(%d+)")
		if maj and (tonumber(maj) > 1 or tonumber(min) >= 4) then
			return "kitty", "ghostty " .. env.TERM_PROGRAM_VERSION
		end
		return "blocks", "ghostty < 1.4 ou version inconnue (pas d'animation kitty)"
	end
	if prog == "WezTerm" then
		return "blocks", "WezTerm : pas de placeholders Unicode kitty"
	end
	return "blocks", "pas de protocole graphique kitty"
end

local engine_cache = {} -- vim.g.nide_intro_mode -> { moteur, raison } (détection faite une fois)
--- moteur qui sera utilisé, et pourquoi
---@return "kitty"|"blocks", string
function M.engine()
	local key = tostring(vim.g.nide_intro_mode)
	engine_cache[key] = engine_cache[key] or { detect_engine() }
	return engine_cache[key][1], engine_cache[key][2]
end

-- ---------------------------------------------------------------------------
-- En-tête et disposition du dashboard selon la taille de la fenêtre
-- ---------------------------------------------------------------------------
local dash -- dashboard snacks courant (passé par M.layout)
local logo_shown = false
local logo_size ---@type nide.intro.Size? taille du logo affiché
M.state = nil -- dernière disposition choisie (tests, :lua =require("nide.intro").state)

-- espacements, du plus aéré au plus serré
local SPACINGS = {
	{ logo_pad = 1, gap = 1, keys_pad = 1, rec_pad = 1 },
	{ logo_pad = 1, gap = 0, keys_pad = 1, rec_pad = 1 },
	{ logo_pad = 1, gap = 0, keys_pad = 1, rec_pad = 0 },
}
local MINIMAL = { logo_pad = 0, gap = 0, keys_pad = 0, rec_pad = 0 }

-- titre texte (fenêtre trop petite pour le moindre logo) : couleurs des lettres du logo
local TITLE = { { "n", "#cba6f7" }, { "i", "#89b4fa" }, { "d", "#a6e3a1" }, { "e", "#fab387" } }
local function title_hl()
	for i, t in ipairs(TITLE) do
		api.nvim_set_hl(0, "NideTitle" .. i, { fg = t[2], bold = true })
	end
end

-- taille réelle de la fenêtre du dashboard (snacks compte une ligne de plus
-- quand la barre d'état globale est active, ce qui ferait défiler le logo)
local function win_size(self)
	if not (self.win and api.nvim_win_is_valid(self.win)) then
		return { width = 0, height = 0 }
	end
	return { width = api.nvim_win_get_width(self.win), height = api.nvim_win_get_height(self.win) }
end

--- lignes de l'en-tête : logo demi-blocs de cette taille
local function logo_items(sz, pad)
	local items = {}
	for _, runs in ipairs(frame(load("logo", sz), 1)) do
		local text = {}
		for _, run in ipairs(runs) do
			text[#text + 1] = { UPPER:rep(run[2] - run[1]), hl = run[3] }
		end
		items[#items + 1] = { text = text, align = "center" }
	end
	items[#items].padding = pad
	return items
end

local function title_item(pad)
	title_hl()
	local text = {}
	for i, t in ipairs(TITLE) do
		text[i] = { t[1], hl = "NideTitle" .. i }
	end
	return { text = text, align = "center", padding = pad }
end

--- Sections du dashboard adaptées à la fenêtre : en-tête (logo de la plus grande
--- taille possible, ou titre texte) suivi de `sections`, dont on règle l'espacement
--- (keys : gap/padding ; recent_files : limit/padding ; startup : affichée ou non).
--- Appelée par snacks à chaque rendu, donc aussi après un redimensionnement.
---@param self snacks.dashboard.Class
---@param sections snacks.dashboard.Section[]
function M.layout(self, sections)
	dash = self
	local win = win_size(self)
	-- touches du dashboard : jamais plus larges que la fenêtre
	M._width = M._width or self.opts.width
	self.opts.width = math.max(20, math.min(M._width, win.width - 2))

	-- hauteur de chaque section sans espacement (1 ligne par élément)
	local function count(sec)
		local s = vim.deepcopy(sec)
		s.gap, s.padding = nil, nil
		local n = 0
		for _, it in ipairs(self:resolve(s)) do
			n = n + (it.hidden and 0 or 1)
		end
		return n
	end
	local n = {}
	for i, sec in ipairs(sections) do
		n[i] = count(sec)
	end

	local function height(c)
		local h = c.size and (c.size.rows + c.sp.logo_pad) or (1 + c.sp.logo_pad)
		for i, sec in ipairs(sections) do
			local k = n[i]
			if sec.section == "recent_files" then
				local files = math.min(math.max(k - (sec.title and 1 or 0), 0), c.recent)
				h = h + (files > 0 and (files + (sec.title and 1 or 0) + c.sp.rec_pad) or 0)
			elseif sec.section == "startup" then
				h = h + (c.startup and k or 0)
			elseif k > 0 then
				h = h + k + (sec.gap and c.sp.gap * (k - 1) or 0) + (sec.padding and c.sp.keys_pad or 0)
			end
		end
		return h
	end

	-- candidats, du plus confortable au plus dépouillé
	local limit = 5
	for _, sec in ipairs(sections) do
		limit = sec.section == "recent_files" and (sec.limit or 5) or limit
	end
	local cands, fitting = {}, {}
	for _, sz in ipairs(M.sizes()) do
		if sz.cols <= win.width - 2 and load("logo", sz) then
			fitting[#fitting + 1] = sz
			for _, sp in ipairs(SPACINGS) do
				cands[#cands + 1] = { size = sz, sp = sp, recent = limit, startup = true }
			end
		end
	end
	-- en dernier recours : sans ligne de démarrage, puis moins de récents, puis aucun
	local tight = SPACINGS[#SPACINGS]
	local function strip(sz)
		cands[#cands + 1] = { size = sz, sp = tight, recent = limit, startup = false }
		cands[#cands + 1] = { size = sz, sp = tight, recent = math.min(2, limit), startup = false }
		cands[#cands + 1] = { size = sz, sp = tight, recent = 0, startup = false }
	end
	if #fitting > 0 then
		strip(fitting[#fitting])
	end
	-- fenêtre minuscule : titre texte
	cands[#cands + 1] = { sp = tight, recent = limit, startup = true }
	strip(nil)
	cands[#cands + 1] = { sp = MINIMAL, recent = 0, startup = false }
	local pick, h
	for _, c in ipairs(cands) do
		h = height(c)
		pick = c
		if h <= win.height then
			break
		end
	end

	logo_shown, logo_size = pick.size ~= nil, pick.size
	M.state = {
		logo = pick.size and pick.size.name or "texte",
		gap = pick.sp.gap,
		recent = pick.recent,
		startup = pick.startup,
		height = h,
		win = { win.width, win.height },
	}
	local kitty = pick.size ~= nil and K.header_on()
	M.state.kitty = kitty
	local ret = {
		not pick.size and title_item(pick.sp.logo_pad)
			or kitty and K.header_items(self, pick.size, pick.sp.logo_pad) -- image kitty (placeholders)
			or logo_items(pick.size, pick.sp.logo_pad),
	}
	for _, sec in ipairs(sections) do
		local s = vim.deepcopy(sec)
		if s.section == "recent_files" then
			s.limit, s.padding = pick.recent, pick.sp.rec_pad
			s = pick.recent > 0 and s or {}
		elseif s.section == "startup" then
			s = pick.startup and s or {}
		else
			s.gap = s.gap and pick.sp.gap or nil
			s.padding = s.padding and pick.sp.keys_pad or nil
		end
		ret[#ret + 1] = s
	end
	return ret
end

-- ---------------------------------------------------------------------------
-- Sortie terminal et fenêtre flottante
-- ---------------------------------------------------------------------------
M._capture = nil -- table : les séquences émises y sont copiées (tests)

local function tsend(s)
	if vim.env.TMUX then -- passthrough tmux : ESC doublés dans un DCS
		s = "\27Ptmux;" .. s:gsub("\27", "\27\27") .. "\27\\"
	end
	if M._capture then
		M._capture[#M._capture + 1] = s
	end
	api.nvim_ui_send(s)
end

-- position écran (0-based) du coin haut-gauche du logo dans le dashboard
local function header_anchor()
	if not (dash and logo_shown and api.nvim_win_is_valid(dash.win) and api.nvim_buf_is_valid(dash.buf)) then
		return
	end
	if api.nvim_win_get_buf(dash.win) ~= dash.buf then
		return
	end
	for i, l in ipairs(api.nvim_buf_get_lines(dash.buf, 0, -1, false)) do
		local b = l:find(UPPER, 1, true) or l:find(PLACEHOLDER, 1, true)
		if b then
			local p = vim.fn.screenpos(dash.win, i, b)
			return p.row > 0 and { row = p.row - 1, col = p.col - 1 } or nil
		end
	end
end

local function float_pos(w, h, anchor)
	if anchor then
		return anchor.row, anchor.col
	end
	return math.max(0, math.floor((vim.o.lines - h) / 2) - 1), math.max(0, math.floor((vim.o.columns - w) / 2))
end

local function open_float(buf, w, h, anchor)
	local row, col = float_pos(w, h, anchor)
	local win = api.nvim_open_win(buf, false, {
		relative = "editor",
		width = w,
		height = h,
		row = row,
		col = col,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 250, -- au-dessus de tout, dashboard compris
		noautocmd = true,
	})
	vim.wo[win].winhighlight = "Normal:Normal,NormalFloat:Normal,EndOfBuffer:Normal"
	vim.wo[win].winblend = 0
	return win
end

-- ---------------------------------------------------------------------------
-- Moteur kitty
-- ---------------------------------------------------------------------------
K.QUERY_ID = 31 -- id de la requête « tout est reçu ? » (a=q : rien n'est stocké)

-- 128 premiers diacritiques de rowcolumn-diacritics.txt (kitty) : n° de ligne / colonne
-- stylua: ignore
local DIAC_HEX = "0305,030D,030E,0310,0312,033D,033E,033F,0346,034A,034B,034C,0350,0351,0352,0357,035B,0363,0364,0365,0366,0367,0368,0369,036A,036B,036C,036D,036E,036F,0483,0484,0485,0486,0487,0592,0593,0594,0595,0597,0598,0599,059C,059D,059E,059F,05A0,05A1,05A8,05A9,05AB,05AC,05AF,05C4,0610,0611,0612,0613,0614,0615,0616,0617,0657,0658,0659,065A,065B,065D,065E,06D6,06D7,06D8,06D9,06DA,06DB,06DC,06DF,06E0,06E1,06E2,06E4,06E7,06E8,06EB,06EC,0730,0732,0733,0735,0736,073A,073D,073F,0740,0741,0743,0745,0747,0749,074A,07EB,07EC,07ED,07EE,07EF,07F0,07F1,07F3,0816,0817,0818,0819,081B,081C,081D,081E,081F,0820,0821,0822,0823,0825,0826,0827,0829,082A,082B,082C"

--- séquence APC kitty ; charge utile découpée en morceaux de 4096 (m=1 … m=0)
function K.cmd(ctrl, payload)
	if not payload or #payload <= 4096 then
		return "\27_G" .. ctrl .. (payload and (";" .. payload) or "") .. "\27\\"
	end
	local out, n = {}, #payload
	-- les morceaux suivants ne portent que m (et q) ; ceux d'une frame (a=f) répètent a=f
	local next_ctrl = (ctrl:find("a=f", 1, true) and "a=f," or "") .. "q=2,"
	for i = 1, n, 4096 do
		local m = i + 4096 > n and 0 or 1
		local c = i == 1 and (ctrl .. ",m=" .. m) or (next_ctrl .. "m=" .. m)
		out[#out + 1] = "\27_G" .. c .. ";" .. payload:sub(i, i + 4095) .. "\27\\"
	end
	return table.concat(out)
end

--- séquences de transmission des frames (rien n'est envoyé : testable en headless)
---@param transfer "file"|"direct" fichier lu par kitty (t=f) ou données en ligne (SSH)
function K.build(transfer)
	local dir = M.dir .. "/kitty/"
	local man = dofile(dir .. "manifest.lua")
	local seqs = {}
	for i, fr in ipairs(man.frames) do
		local path = dir .. fr.file
		local ctrl, payload
		if transfer == "direct" then
			local f = assert(io.open(path, "rb"))
			payload = vim.base64.encode(f:read("*a"))
			f:close()
			ctrl = "f=100,q=2"
		else
			payload = vim.base64.encode(path) -- t=f : chemin absolu
			ctrl = "f=100,t=f,q=2"
		end
		local head = i == 1 and ("a=t,i=%d,"):format(IMAGE_ID) or ("a=f,i=%d,z=%d,"):format(IMAGE_ID, fr.ms)
		seqs[#seqs + 1] = K.cmd(head .. ctrl, payload)
	end
	-- la 1re frame (racine) n'a pas de délai par défaut : on le fixe
	seqs[#seqs + 1] = K.cmd(("a=a,i=%d,r=1,z=%d,q=2"):format(IMAGE_ID, man.frames[1].ms))
	return seqs, man
end

--- lignes de placeholders : U+10EEEE + diacritique(ligne) + diacritique(colonne)
local function placeholder_lines(cols, rows)
	local diac = vim.split(DIAC_HEX, ",")
	local lines = {}
	for r = 1, rows do
		local rd = vim.fn.nr2char(tonumber(diac[r], 16))
		local parts = {}
		for c = 1, cols do
			parts[c] = PLACEHOLDER .. rd .. vim.fn.nr2char(tonumber(diac[c], 16))
		end
		lines[r] = table.concat(parts)
	end
	return lines
end

-- taille d'une cellule en pixels (ioctl TIOCGWINSZ sur le terminal), nil si inconnue
local function cell_px()
	local ok, ffi = pcall(require, "ffi")
	if not ok or ffi.os ~= "Linux" and ffi.os ~= "OSX" and ffi.os ~= "BSD" then
		return
	end
	pcall(ffi.cdef, [[
		typedef struct { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; } nide_winsize;
		int ioctl(int fd, unsigned long request, ...);
	]])
	local req = ffi.os == "Linux" and 0x5413 or 0x40087468 -- TIOCGWINSZ
	local ws = ffi.new("nide_winsize")
	for fd = 0, 2 do -- le serveur nvim hérite du terminal sur ses entrées/sorties
		if ffi.C.ioctl(fd, req, ws) == 0 and ws.ws_xpixel > 0 and ws.ws_col > 0 and ws.ws_row > 0 then
			return ws.ws_xpixel / ws.ws_col, ws.ws_ypixel / ws.ws_row
		end
	end
end
K.cell_px = cell_px

--- boîte du placement kitty dans la boîte du logo (cols x rows) : l'image w x h px
--- y est ajustée en gardant ses proportions, avec la taille réelle des cellules
--- (sinon le ratio par défaut 1:2) ; la boîte est réduite au plus juste et centrée.
--- Les logos demi-blocs ont exactement les proportions de l'image pour des cellules
--- 1:2 : la boîte est alors celle du logo.
---@return { cols: integer, rows: integer, dcol: integer, drow: integer }
function K.box(cols, rows, w, h, cw, ch)
	if not (cw and ch) then
		cw, ch = 1, 2
	end
	local s = math.min(cols * cw / w, rows * ch / h)
	local c = math.max(1, math.min(cols, math.ceil(w * s / cw - 0.05)))
	local r = math.max(1, math.min(rows, math.ceil(h * s / ch - 0.05)))
	return { cols = c, rows = r, dcol = math.floor((cols - c) / 2), drow = math.floor((rows - r) / 2) }
end

-- ---------------------------------------------------------------------------
-- En-tête kitty : logo final (dernière frame) affiché par placeholders dans les
-- lignes de l'en-tête du dashboard
-- ---------------------------------------------------------------------------
K.LOGO_QUERY_ID = 32 -- requête « logo reçu ? »
K.logo_state = nil ---@type nil|"pending"|"ok"|"fail" logo transmis au terminal ?
K.shown = LOGO_ID -- image désignée par la couleur des placeholders de l'en-tête
K.placed = nil ---@type string? boîte « CxR » du placement virtuel du logo
K.header_box = nil -- boîte du logo kitty dans l'en-tête (dernier rendu)

local function is_ssh()
	return vim.env.SSH_CONNECTION or vim.env.SSH_TTY
end

local manifest
function K.manifest()
	if manifest == nil then
		local ok, m = pcall(dofile, M.dir .. "/kitty/manifest.lua")
		manifest = ok and type(m) == "table" and m.frames and #m.frames > 0 and m or false
	end
	return manifest or nil
end

--- l'en-tête du dashboard est-il une image kitty ? (sinon logo demi-blocs)
function K.header_on()
	return M.engine() == "kitty" and K.logo_state ~= "fail" and #api.nvim_list_uis() > 0 and K.manifest() ~= nil
end

--- image affichée par les placeholders de l'en-tête (animation ou logo final) :
--- l'id est porté par la couleur de premier plan
function K.show(id)
	K.shown = id or K.shown
	api.nvim_set_hl(0, "NideKittyLogo", { fg = ("#%06x"):format(K.shown) })
end

--- transmission du logo final (une seule fois), puis requête : sans réponse du
--- terminal, repli sur le logo demi-blocs
function K.send_logo()
	if K.logo_state then
		return
	end
	K.logo_state = "pending"
	local path = M.dir .. "/kitty/" .. K.manifest().frames[#K.manifest().frames].file
	local ctrl, payload = "f=100,t=f,q=2", vim.base64.encode(path)
	if is_ssh() then
		local f = io.open(path, "rb")
		payload = f and vim.base64.encode(f:read("*a")) or ""
		if f then
			f:close()
		end
		ctrl = "f=100,q=2"
	end
	tsend(K.cmd(("a=t,i=%d,"):format(LOGO_ID) .. ctrl, payload))
	local function settle(state)
		if K.logo_state ~= "pending" then
			return
		end
		K.logo_state = state
		if state == "fail" then
			K.placed = nil
			if dash then
				pcall(dash.update, dash) -- en-tête redessiné en demi-blocs
			end
		end
	end
	if vim.env.TMUX then -- les réponses ne reviennent pas par tmux : on suppose que ça marche
		return settle("ok")
	end
	api.nvim_create_autocmd("TermResponse", {
		group = api.nvim_create_augroup("nide_intro_logo", { clear = true }),
		callback = function(ev)
			local seq = ev.data and ev.data.sequence or ""
			if seq:find("Gi=" .. K.LOGO_QUERY_ID .. ";", 1, true) then
				vim.schedule(function()
					settle("ok")
				end)
				return true
			end
		end,
	})
	tsend(K.cmd(("a=q,i=%d,s=1,v=1,t=d,f=24"):format(K.LOGO_QUERY_ID), "AAAA"))
	vim.defer_fn(function()
		settle("fail")
	end, is_ssh() and 15000 or 1500)
end

--- placement virtuel du logo (p=1 : un nouveau placement remplace l'ancien)
function K.place(box)
	local key = box.cols .. "x" .. box.rows
	if K.placed ~= key then
		K.placed = key
		tsend(K.cmd(("a=p,U=1,i=%d,p=1,c=%d,r=%d,q=2"):format(LOGO_ID, box.cols, box.rows)))
	end
end

--- placement supprimé (l'image reste stockée par le terminal pour la prochaine fois)
function K.unplace()
	if K.placed then
		K.placed = nil
		pcall(tsend, K.cmd(("a=d,d=i,i=%d,p=1,q=2"):format(LOGO_ID)))
	end
end

local ph_cache = {}
local watched_buf
--- lignes de l'en-tête kitty pour un logo de taille sz : la boîte du placement
--- (proportions de l'image, cellules réelles) centrée dans celle du logo
function K.header_items(self, sz, pad)
	K.send_logo()
	local man = K.manifest()
	local b = K.box(sz.cols, sz.rows, man.w, man.h, cell_px())
	K.header_box = b
	K.place(b)
	K.show()
	-- dashboard quitté : placement supprimé (plus aucune trace de l'image)
	if self.buf and watched_buf ~= self.buf then
		watched_buf = self.buf
		api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
			buffer = self.buf,
			once = true,
			callback = function()
				watched_buf = nil
				K.unplace()
			end,
		})
	end
	local key = b.cols .. "x" .. b.rows
	ph_cache[key] = ph_cache[key] or placeholder_lines(b.cols, b.rows)
	local items = {}
	for r, l in ipairs(ph_cache[key]) do
		items[r] = { text = { { l, hl = "NideKittyLogo" } }, align = "center" }
	end
	local top, bottom = b.drow, pad + sz.rows - b.drow - b.rows
	items[1].padding = { 0, top }
	items[#items].padding = { bottom, #items == 1 and top or 0 }
	return items
end

function K.play(p)
	local direct = is_ssh()
	local seqs, man = K.build(direct and "direct" or "file")
	-- même boîte que le logo de l'en-tête, proportions de l'image gardées
	local box = p.header and K.header_box or K.box(p.size.cols, p.size.rows, man.w, man.h, cell_px())
	p.box = box
	local cols, rows = box.cols, box.rows
	local total = 0
	for _, fr in ipairs(man.frames) do
		total = total + fr.ms
	end

	-- 2) le terminal a tout reçu : placeholders (en-tête ou fenêtre), puis lecture
	local function start()
		if p.done or p.win or p.started then
			return
		end
		p.started = true
		if p.header then
			-- les placeholders de l'en-tête désignent maintenant l'animation
			K.show(IMAGE_ID)
			vim.cmd.redraw()
		else
			p.buf = api.nvim_create_buf(false, true)
			local lines = placeholder_lines(cols, rows)
			api.nvim_buf_set_lines(p.buf, 0, -1, false, lines)
			-- l'id de l'image est porté par la couleur de premier plan
			api.nvim_set_hl(0, "NideIntroKitty", { fg = ("#%06x"):format(IMAGE_ID) })
			local ns = api.nvim_create_namespace("nide_intro")
			for r = 0, rows - 1 do
				api.nvim_buf_set_extmark(p.buf, ns, r, 0, { end_col = #lines[r + 1], hl_group = "NideIntroKitty" })
			end
			local a = p.anchor and p.anchor()
			p.win = open_float(p.buf, cols, rows, a and { row = a.row + box.drow, col = a.col + box.dcol })
		end
		-- s=2 (« chargement ») : la lecture s'arrête sur la dernière frame
		tsend(K.cmd(("a=a,i=%d,s=2,v=1,q=2"):format(IMAGE_ID)))
		p.timer:stop()
		p.timer:start(total + HOLD_MS, 0, vim.schedule_wrap(function()
			p.stop("done")
		end))
	end

	-- 1) envoi des frames, placement virtuel (U=1 : kitty ajuste l'image à la boîte
	-- en gardant ses proportions), puis une requête dont la réponse arrive quand le
	-- terminal a tout traité (en SSH, ~3 Mo : l'envoi peut prendre du temps)
	p.kitty = true -- image à effacer à l'arrêt
	api.nvim_create_autocmd("TermResponse", {
		group = p.group,
		callback = function(ev)
			local seq = ev.data and ev.data.sequence or ""
			if seq:find("Gi=" .. K.QUERY_ID .. ";", 1, true) then
				vim.schedule(start)
				return true -- autocmd supprimé
			end
		end,
	})
	local function finish_send()
		tsend(K.cmd(("a=p,U=1,i=%d,c=%d,r=%d,q=2"):format(IMAGE_ID, cols, rows)))
		tsend(K.cmd(("a=q,i=%d,s=1,v=1,t=d,f=24"):format(K.QUERY_ID), "AAAA"))
		-- pas de réponse (tmux, terminal muet) : on joue quand même après un délai
		p.timer:start(direct and 30000 or 1000, 0, vim.schedule_wrap(start))
	end
	if not direct then
		for _, s in ipairs(seqs) do
			tsend(s)
		end
		return finish_send()
	end
	-- SSH : envoi par paquets pour garder nvim réactif
	local i = 0
	local function send_batch()
		if p.done then
			return
		end
		for _ = 1, 4 do
			i = i + 1
			if not seqs[i] then
				return finish_send()
			end
			tsend(seqs[i])
		end
		vim.schedule(send_batch)
	end
	send_batch()
end

-- ---------------------------------------------------------------------------
-- Moteur demi-blocs
-- ---------------------------------------------------------------------------
function M.draw_blocks(buf, ns, d, i)
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for r, runs in ipairs(frame(d, i)) do
		for _, run in ipairs(runs) do
			api.nvim_buf_set_extmark(buf, ns, r - 1, run[1] * 3, { end_col = run[2] * 3, hl_group = run[3] })
		end
	end
end

local function blocks_play(p)
	local d = assert(load("blocks", p.size), "blocks_" .. p.size.name .. ".lua absent")
	p.buf = api.nvim_create_buf(false, true)
	local line = UPPER:rep(d.cols)
	local lines = {}
	for r = 1, d.rows do
		lines[r] = line
	end
	api.nvim_buf_set_lines(p.buf, 0, -1, false, lines)
	local ns = api.nvim_create_namespace("nide_intro")
	M.draw_blocks(p.buf, ns, d, 1)
	p.win = open_float(p.buf, d.cols, d.rows, p.anchor and p.anchor())
	-- échéances calculées depuis le début : pas de dérive si un tick est en retard
	local i, due, t0 = 1, d.ms[1], uv.now()
	local function tick()
		if p.done then
			return
		end
		i = i + 1
		if i > #d.frames then
			return p.stop("done") -- la dernière frame = le logo de l'en-tête : relève invisible
		end
		M.draw_blocks(p.buf, ns, d, i)
		due = due + d.ms[i]
		uv.update_time()
		p.timer:start(math.max(0, t0 + due - uv.now()), 0, vim.schedule_wrap(tick))
	end
	p.timer:start(due, 0, vim.schedule_wrap(tick))
end

-- ---------------------------------------------------------------------------
-- Lecture
-- ---------------------------------------------------------------------------
local current -- lecture en cours
M.last = nil -- { mode, reason, ms } de la dernière lecture (tests)

-- touches qui ne passent pas l'intro (événements, pas des actions de l'utilisateur)
local IGNORED = { ["<FocusGained>"] = true, ["<FocusLost>"] = true, ["<MouseMove>"] = true, ["<Ignore>"] = true }

function M.stop(reason)
	if current then
		current.stop(reason or "stop")
	end
end

function M.playing()
	return current ~= nil
end

---@param opts? { dashboard?: boolean, size?: nide.intro.Size, mode?: "kitty"|"blocks", on_done?: fun(reason: string) }
function M.play(opts)
	opts = opts or {}
	M.stop("replay")
	-- taille : celle du logo de l'en-tête (dashboard), sinon la plus grande possible
	local size = opts.size or (opts.dashboard and logo_size) or size_within(vim.o.columns - 2, vim.o.lines - 2)
	if not (size and load("blocks", size)) then
		return false
	end
	local mode = opts.mode or M.engine()
	-- dashboard en kitty : l'intro se joue dans les placeholders de l'en-tête ; si
	-- l'en-tête est en demi-blocs (le terminal n'a pas répondu), intro en demi-blocs
	local header = opts.dashboard and mode == "kitty" and K.header_on() and K.header_box ~= nil
	if opts.dashboard and mode == "kitty" and not header then
		mode = "blocks"
	end
	local t0 = uv.hrtime()
	local p = { timer = uv.new_timer(), mode = mode, size = size, header = header }
	local ns_key = api.nvim_create_namespace("nide_intro_skip")
	local group = api.nvim_create_augroup("nide_intro_play", { clear = true })
	if opts.dashboard then
		p.anchor = header_anchor
	end
	p.group = group

	function p.stop(reason)
		if p.done then
			return
		end
		p.done = true
		current = nil
		vim.on_key(nil, ns_key)
		pcall(api.nvim_del_augroup_by_id, group)
		if not p.timer:is_closing() then
			p.timer:stop()
			p.timer:close()
		end
		if p.win then
			pcall(api.nvim_win_close, p.win, true)
		end
		if p.buf then
			pcall(api.nvim_buf_delete, p.buf, { force = true })
		end
		if p.header then
			-- l'en-tête désigne de nouveau le logo final : même image que la dernière
			-- frame, même boîte, donc aucune transition visible
			K.show(LOGO_ID)
		end
		if p.kitty then
			-- le logo (kitty ou demi-blocs) est redessiné d'abord, puis l'animation est libérée
			if reason ~= "exit" then
				pcall(vim.cmd.redraw)
			end
			pcall(tsend, K.cmd(("a=d,d=I,i=%d,q=2"):format(IMAGE_ID)))
		end
		M.last = { mode = mode, reason = reason, ms = (uv.hrtime() - t0) / 1e6 }
		if opts.on_done then
			opts.on_done(reason)
		end
	end
	current = p

	-- n'importe quelle touche ou clic passe l'intro ; la touche est mangée, y compris
	-- quand elle est remappée (j -> gj : on reçoit « g » tapé « j », puis « j » non tapé)
	local skipping = false
	vim.on_key(function(_, typed)
		if not typed or typed == "" then
			return skipping and "" or nil -- suite d'un remappage de la touche mangée
		end
		if IGNORED[vim.fn.keytrans(typed)] then
			return
		end
		if not skipping then
			skipping = true
			vim.schedule(function()
				p.stop("skip")
			end)
		end
		return ""
	end, ns_key)

	-- redimensionnement, sortie du dashboard ou de nvim : arrêt propre
	local function on(ev, cb, o)
		api.nvim_create_autocmd(ev, vim.tbl_extend("force", { group = group, callback = cb }, o or {}))
	end
	on("VimResized", function()
		p.stop("resize")
	end)
	on("VimLeavePre", function()
		p.stop("exit")
	end)
	if opts.dashboard then
		-- (fenêtre du dashboard redimensionnée, ex. cmdheight changé par noice :
		-- snacks refait le rendu et l'intro suit l'en-tête ci-dessous)
		local win, buf = dash.win, dash.buf
		on({ "BufHidden", "BufWinLeave", "BufWipeout" }, function()
			p.stop("leave")
		end, { buffer = buf })
		on("WinClosed", function()
			p.stop("leave")
		end, { pattern = tostring(win) })
		on("TabLeave", function()
			p.stop("leave")
		end)
		-- nouveau rendu du dashboard : on suit l'en-tête (ou on s'arrête s'il a disparu)
		-- (après le rendu : la position écran n'est fiable qu'une fois la fenêtre remise à jour)
		on("User", function()
			vim.schedule(function()
				if p.done then
					return
				end
				local a = header_anchor()
				-- logo remplacé par le titre texte, d'une autre taille, ou plus entièrement visible
				if not a or logo_size ~= p.size then
					return p.stop("resize")
				end
				if p.header then -- en-tête kitty : rien à déplacer, la boîte doit être la même
					local b = K.header_box
					if not (K.header_on() and b and p.box and b.cols == p.box.cols and b.rows == p.box.rows) then
						return p.stop("resize")
					end
					return
				end
				if p.win and api.nvim_win_is_valid(p.win) then
					local b = p.box or { drow = 0, dcol = 0 }
					api.nvim_win_set_config(p.win, { relative = "editor", row = a.row + b.drow, col = a.col + b.dcol })
				end
				vim.cmd.redraw()
			end)
		end, { pattern = "SnacksDashboardUpdatePost" })
	end

	local ok, err = pcall(mode == "kitty" and K.play or blocks_play, p)
	if not ok then
		p.stop("error")
		vim.notify("intro : " .. tostring(err), vim.log.levels.WARN)
		return false
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Démarrage et commande
-- ---------------------------------------------------------------------------
local function dashboard_ready()
	return dash ~= nil
		and logo_shown
		and api.nvim_buf_is_valid(dash.buf)
		and api.nvim_get_current_buf() == dash.buf
		and vim.bo[dash.buf].filetype == "snacks_dashboard"
		and header_anchor() ~= nil
end

--- :NideIntro : dans le dashboard s'il est affiché, sinon dans une fenêtre centrée
function M.replay()
	if #M.sizes() == 0 then
		return vim.notify("intro : données absentes (" .. M.dir .. ")", vim.log.levels.WARN)
	end
	if dashboard_ready() then
		return M.play({ dashboard = true })
	end
	if not size_within(vim.o.columns - 2, vim.o.lines - 2) then
		return vim.notify("intro : fenêtre trop petite", vim.log.levels.WARN)
	end
	M.play()
end

-- Le dashboard tient dans sa fenêtre, mais celle-ci a pu défiler pendant qu'elle était
-- plus petite (démarrage : barre d'état, ligne de commande, onglets réglés après coup) :
-- on revient en haut, sinon le logo est coupé.
local function fix_view()
	if not (dash and dash.win and api.nvim_win_is_valid(dash.win) and api.nvim_buf_is_valid(dash.buf)) then
		return
	end
	if api.nvim_win_get_buf(dash.win) ~= dash.buf then
		return
	end
	if api.nvim_buf_line_count(dash.buf) <= api.nvim_win_get_height(dash.win) then
		api.nvim_win_call(dash.win, function()
			if vim.fn.line("w0") ~= 1 then
				vim.fn.winrestview({ topline = 1 })
			end
		end)
	end
end
M.fix_view = fix_view

function M.setup()
	local group = api.nvim_create_augroup("nide_intro", { clear = true })
	-- en-tête kitty : si l'intro va se jouer au démarrage, il reste vide jusqu'à
	-- l'animation (pas de logo qui s'afficherait puis disparaîtrait)
	local intro_expected = vim.g.nide_intro ~= false and vim.fn.argc(-1) == 0
	K.show(intro_expected and IMAGE_ID or LOGO_ID)
	-- sortie de nvim : logo kitty effacé du terminal
	api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if K.logo_state then
				pcall(tsend, K.cmd(("a=d,d=I,i=%d,q=2"):format(LOGO_ID)))
			end
		end,
	})
	api.nvim_create_autocmd("User", { group = group, pattern = "SnacksDashboardUpdatePost", callback = fix_view })
	api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = group,
		callback = function()
			vim.schedule(fix_view)
		end,
	})
	-- :colorscheme efface les groupes : on les recrée
	api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			for name, c in pairs(hls) do
				set_hl(name, c)
			end
			title_hl()
			K.show()
		end,
	})
	-- une seule fois, après l'ouverture du dashboard (snacks l'ouvre à UIEnter) et
	-- après VeryLazy (barre d'état, cmdheight… réglées) : jamais sur le chemin du démarrage
	local function autoplay()
		if vim.g.nide_intro == false or #api.nvim_list_uis() == 0 or vim.fn.argc(-1) > 0 then
			return K.show(LOGO_ID)
		end
		-- la fenêtre a pu changer depuis le dernier rendu (barre d'état, cmdheight…) :
		-- nouvelle disposition avant de jouer
		local w = dash and win_size(dash)
		if w and M.state and (w.width ~= M.state.win[1] or w.height ~= M.state.win[2]) then
			pcall(dash.update, dash)
		end
		fix_view()
		-- l'ancien en-tête doit avoir disparu de l'écran avant que la fenêtre de l'intro
		-- ne le recouvre (sinon ses bords peuvent rester affichés à côté)
		vim.cmd.redraw()
		if not (dashboard_ready() and M.play({ dashboard = true })) then
			K.show(LOGO_ID) -- pas d'intro : logo final dans l'en-tête kitty
		end
	end
	api.nvim_create_autocmd("UIEnter", {
		group = group,
		once = true,
		callback = function()
			if vim.g.did_very_lazy or not package.loaded.lazy then
				return vim.schedule(autoplay)
			end
			api.nvim_create_autocmd("User", {
				group = group,
				pattern = "VeryLazy",
				once = true,
				callback = function()
					vim.schedule(autoplay)
				end,
			})
		end,
	})
	api.nvim_create_user_command("NideIntro", M.replay, { desc = "Rejouer l'intro animée" })
end

return M
