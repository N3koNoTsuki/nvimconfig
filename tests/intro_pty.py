#!/usr/bin/env python3
"""Test de l'intro animée (lua/nide/intro.lua) dans un vrai pseudo-terminal.

nide tourne dans un pty (TUI active) ; un pilote Lua injecté par --cmd note ce
qui se passe et écrit un rapport JSON ; pyte (si présent) reconstitue l'écran.

  tests/intro_pty.py [blocks|kitty] [skip_ms]
    skip_ms : touche « j » envoyée à cet instant (passe l'intro), puis une 2e « j »
    500 ms plus tard (elle doit agir dans le dashboard). 0 = lecture complète.
  tests/intro_pty.py sizes [blocks|kitty|all] [dossier]
    matrice de tailles (24/28/30/37/44/55 lignes x 60/80/120/200 colonnes, avec
    et sans fichiers récents) : intro jouée jusqu'au bout et calée sur l'en-tête
    quand un logo tient, dashboard entier dans la fenêtre ; avec un dossier, un
    PNG de l'écran final par taille (rendu pyte en couleurs).
Variables :
  EXPECT=none    l'intro ne doit pas se jouer (fichier ouvert, fenêtre trop petite…)
  EXPECT=resize  terminal redimensionné à 800 ms : arrêt propre attendu, puis dashboard
                 redessiné à la nouvelle taille (RESIZE=LIGNESxCOLONNES, défaut +2 x +4)
  EXPECT=auto    intro attendue si un logo tient dans la fenêtre, sinon aucune
  DEBUG=1        chronologie : rendus du dashboard, début de l'intro, touches reçues
  SSH_TEST=1     session SSH simulée (transfert kitty direct, t=d)
  NOREPLY=1      le « terminal » ne répond pas aux requêtes kitty (repli demi-blocs)
  KEY, REASON    1re touche envoyée (défaut j ; ex. KEY='\\x1b[I' focus), fin attendue
  ROWS, COLS     taille du terminal (défaut 55 x 140) ; SHOW=1 affiche l'écran
  CELL=LxH       taille d'une cellule en pixels annoncée par le pty (défaut 10x20)
  RECENTS=n      n fichiers récents dans le dossier courant (section « Récents »)
  PNG=chemin     écran final rendu en PNG (pyte)
  EXTRA_ARGS     arguments de nvim, séparés par « | »
Code de sortie 0 si tout est conforme. Pyte : ~/.local/share/nvim-ide/manim-venv/bin/python.
"""
import fcntl, json, os, pty, re, select, shutil, struct, sys, tempfile, termios, time

mode = sys.argv[1] if len(sys.argv) > 1 else "blocks"
if mode == "sizes":
    import subprocess
    from concurrent.futures import ThreadPoolExecutor
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    outdir = sys.argv[3] if len(sys.argv) > 3 else ""
    if outdir:
        os.makedirs(outdir, exist_ok=True)
    runs = []
    for m in (["blocks", "kitty"] if which == "all" else [which]):
        for rows in (24, 28, 30, 37, 44, 55):
            for cols in (60, 80, 120, 200):
                for rec in ((0, 2) if m == "blocks" else (0,)):
                    runs.append((m, rows, cols, rec))
    # le moteur kitty avec des cellules qui ne sont pas en 1:2
    if which in ("all", "kitty"):
        runs += [("kitty", 37, 80, 0, {"CELL": "9x20"}), ("kitty", 44, 120, 0, {"CELL": "8x19"})]
    # redimensionnement pendant l'intro : arrêt propre, logo redessiné à la nouvelle taille
    for m in (["blocks", "kitty"] if which == "all" else [which]):
        runs += [(m, 55, 140, 2, {"EXPECT": "resize", "RESIZE": "30x80"}),
                 (m, 30, 80, 0, {"EXPECT": "resize", "RESIZE": "24x60"}),
                 (m, 28, 60, 2, {"EXPECT": "resize", "RESIZE": "55x200"})]
    def one(r):
        m, rows, cols, rec = r[:4]
        e = dict(os.environ, ROWS=str(rows), COLS=str(cols), RECENTS=str(rec), EXPECT="auto")
        if len(r) > 4:
            e.update(r[4])
        if outdir:
            e["PNG"] = os.path.join(outdir, f"{m}_{rows}x{cols}_r{rec}"
                                    + ("".join("_" + v for v in r[4].values()) if len(r) > 4 else "") + ".png")
        res = subprocess.run([sys.executable, os.path.abspath(__file__), m], env=e, capture_output=True, text=True)
        return r, res
    bad = 0
    with ThreadPoolExecutor(max_workers=int(os.environ.get("JOBS", 6))) as ex:
        for r, res in ex.map(one, runs):
            tail = [l for l in res.stdout.splitlines() if l.startswith("disposition")]
            status = "OK   " if res.returncode == 0 else "ÉCHEC"
            print(f"{status} {r[0]:6} {r[1]:3} lignes x {r[2]:3} col. récents={r[3]}"
                  + (" " + " ".join(f"{k}={v}" for k, v in r[4].items()) if len(r) > 4 else "")
                  + " : " + (tail[0] if tail else ""))
            if res.returncode:
                bad += 1
                print("\n".join("      " + l for l in res.stdout.splitlines() if "ÉCHEC" in l or "pas de" in l or "DÉLAI" in l))
                print(res.stderr[-2000:])
    print(f"{len(runs) - bad}/{len(runs)} tailles conformes")
    print("OK" if not bad else "ÉCHEC")
    sys.exit(1 if bad else 0)

skip = int(sys.argv[2]) if len(sys.argv) > 2 else 0
EXPECT = os.environ.get("EXPECT", "")  # « none » : l'intro ne doit pas se jouer ; « resize » ; « auto »
KEY = os.environ.get("KEY", "j").encode().decode("unicode_escape").encode("latin1")  # touche qui passe l'intro
RESIZE_MS = 800  # avec EXPECT=resize : terminal redimensionné à cet instant
ROWS, COLS = int(os.environ.get("ROWS", 55)), int(os.environ.get("COLS", 140))
CW, CH = (int(x) for x in os.environ.get("CELL", "10x20").split("x"))
NEW_SIZE = tuple(int(x) for x in os.environ["RESIZE"].split("x")) if os.environ.get("RESIZE") else (ROWS + 2, COLS + 4)
RECENTS = int(os.environ.get("RECENTS", 0))
config = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp(prefix="nide-intro-")
report = os.path.join(tmp, "report.json")

try:
    import pyte
except ImportError:
    pyte = None

# pilote : capture des séquences, mesures, rapport à la fin de l'intro puis 1,8 s après
driver = os.path.join(tmp, "driver.lua")
with open(driver, "w") as f:
    f.write(r"""
local intro = require("nide.intro")
intro._capture = {}
-- fichiers récents simulés (dossier courant)
local n = tonumber(vim.env.INTRO_RECENTS) or 0
if n > 0 then
	local files = {}
	for i = 1, n do
		files[i] = vim.fn.getcwd() .. "/recent" .. i .. ".txt"
		vim.fn.writefile({ "x" }, files[i])
	end
	vim.v.oldfiles = files
end
local t0 = vim.uv.hrtime()
local hdr_ms, layout = 0, intro.layout
local out
intro.layout = function(self, sections)
	local t = vim.uv.hrtime()
	local r = layout(self, sections)
	out.layouts = out.layouts or {}
	table.insert(out.layouts, { t = math.floor((vim.uv.hrtime() - t0) / 1e6), s = intro.state.logo, h = intro.state.height,
		win = intro.state.win, rec = #vim.v.oldfiles })
	hdr_ms = hdr_ms + (vim.uv.hrtime() - t) / 1e6
	return r
end
local function state()
	local buf = vim.api.nvim_get_current_buf()
	local logo, kitty = 0, 0
	for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if l:find("▀", 1, true) then logo = logo + 1 end
		if l:find("\u{10EEEE}", 1, true) then kitty = kitty + 1 end
	end
	local floats = 0
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(w).zindex == 250 then floats = floats + 1 end
	end
	local win = vim.api.nvim_get_current_win()
	return { ft = vim.bo[buf].filetype, logo_lines = logo, kitty_lines = kitty, intro_floats = floats,
		kitty_hl = (vim.api.nvim_get_hl(0, { name = "NideKittyLogo" }) or {}).fg,
		cursor = vim.api.nvim_win_get_cursor(0), playing = intro.playing(),
		layout = intro.state, win_h = vim.api.nvim_win_get_height(win), win_w = vim.api.nvim_win_get_width(win),
		buf_lines = vim.api.nvim_buf_line_count(buf), topline = vim.fn.line("w0"), botline = vim.fn.line("w$") }
end
out = { header_ms = 0 }
out.keys = {}
local play = intro.play
intro.play = function(...)
	out.play_layout = out.play_layout or intro.state
	return play(...)
end
vim.on_key(function(k, typed)
	table.insert(out.keys, { math.floor((vim.uv.hrtime() - t0) / 1e6), vim.fn.keytrans(k), vim.fn.keytrans(typed or ""), intro.playing() })
end, vim.api.nvim_create_namespace("test_keys"))
vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = function()
	out.uienter_ms = (vim.uv.hrtime() - t0) / 1e6
	vim.defer_fn(function() out.start = state() end, 450) -- avant la 1re touche (700 ms)
	vim.defer_fn(function() -- pas d'intro au bout de 4 s : rapport quand même
		if out.last then return end
		out.final, out.header_ms, out.engine = state(), hdr_ms, { intro.engine() }
		vim.fn.writefile({ vim.json.encode(out) }, vim.env.INTRO_REPORT)
		vim.defer_fn(function() vim.cmd("qa!") end, 300)
	end, 4000)
	local timer = vim.uv.new_timer()
	local playing_since
	timer:start(50, 50, vim.schedule_wrap(function()
		-- intro en cours depuis 600 ms : le script relève l'écran (zone animée)
		if intro.playing() and not out.mid_mark then
			if not playing_since then
				out.play_seen = math.floor((vim.uv.hrtime() - t0) / 1e6)
			end
			playing_since = playing_since or vim.uv.now()
			if vim.uv.now() - playing_since >= 600 then
				out.mid_mark = true
				vim.fn.writefile({}, vim.env.INTRO_REPORT .. ".mid")
			end
		end
		if intro.last and not out.last then
			out.last = intro.last
			out.at_end = state()
			vim.defer_fn(function()
				timer:stop()
				out.final = state()
				out.header_ms = hdr_ms
				out.engine = { intro.engine() }
				out.capture = intro._capture
				vim.fn.writefile({ vim.json.encode(out) }, vim.env.INTRO_REPORT)
				-- laisse au script le temps de relever l'écran, puis quitte le dashboard
				-- (séquences émises à ce moment notées dans report.json.leave) et nvim
				vim.defer_fn(function()
					local n0 = #intro._capture
					pcall(vim.cmd, "enew")
					vim.defer_fn(function()
						vim.fn.writefile({ vim.json.encode({ ft = vim.bo.filetype,
							capture = vim.list_slice(intro._capture, n0 + 1) }) }, vim.env.INTRO_REPORT .. ".leave")
						vim.cmd("qa!")
					end, 150)
				end, 450)
			end, 1800)
		end
	end))
end })
""")

env = dict(os.environ, NVIM_APPNAME=os.path.basename(config), XDG_CONFIG_HOME=os.path.dirname(config),
           XDG_STATE_HOME=os.path.join(tmp, "state"), XDG_CACHE_HOME=os.path.join(tmp, "cache"),
           INTRO_REPORT=report, INTRO_RECENTS=str(RECENTS), TERM="xterm-256color", COLORTERM="truecolor")
for k in ("KITTY_WINDOW_ID", "TMUX", "TERM_PROGRAM", "SSH_CONNECTION", "SSH_TTY"):
    env.pop(k, None)
SSH = os.environ.get("SSH_TEST") == "1"  # simule une session SSH : transfert direct (t=d)
if SSH:
    env["SSH_CONNECTION"] = "10.0.0.1 50000 10.0.0.2 22"
args = ["nvim", "--cmd", f"let g:nide_intro_mode = '{mode}'", "--cmd", f"luafile {driver}"]
args += os.environ.get("EXTRA_ARGS", "").split("|") if os.environ.get("EXTRA_ARGS") else []

def save_png(screen, path):
    """écran pyte -> PNG coloré (▀ dessiné en deux demi-cellules, cellules 10x20)"""
    from PIL import Image, ImageDraw, ImageFont
    W, H = 10, 20
    def font(p, size):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            return ImageFont.load_default()
    reg = font("/usr/share/fonts/TTF/DejaVuSansMono.ttf", 16)
    bold = font("/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf", 16)
    sym = font("/usr/share/fonts/TTF/SymbolsNerdFontMono-Regular.ttf", 16)
    def col(c, dflt):
        if c == "default" or not c:
            return dflt
        if len(c) == 6 and all(ch in "0123456789abcdefABCDEF" for ch in c):
            return "#" + c
        return {"black": "#45475a", "red": "#f38ba8", "green": "#a6e3a1", "brown": "#f9e2af", "blue": "#89b4fa",
                "magenta": "#f5c2e7", "cyan": "#94e2d5", "white": "#bac2de"}.get(c, dflt)
    im = Image.new("RGB", (screen.columns * W, screen.lines * H), "#1e1e2e")
    d = ImageDraw.Draw(im)
    for y in range(screen.lines):
        for x in range(screen.columns):
            ch = screen.buffer[y][x]
            fg, bg = col(ch.fg, "#cdd6f4"), col(ch.bg, "#1e1e2e")
            if ch.reverse:
                fg, bg = bg, fg
            box = (x * W, y * H, x * W + W - 1, y * H + H - 1)
            d.rectangle(box, fill=bg)
            c = ch.data
            if c == "▀":
                d.rectangle((x * W, y * H, x * W + W - 1, y * H + H // 2 - 1), fill=fg)
            elif c == "\U0010EEEE"[0] or (c and ord(c[0]) == 0x10EEEE):
                d.rectangle(box, fill="#3b3f58")  # placeholder kitty (l'image n'est pas rendue)
            elif c and c.strip():
                f = sym if 0xE000 <= ord(c[0]) <= 0xF8FF or ord(c[0]) >= 0xF0000 else (bold if ch.bold else reg)
                d.text((x * W, y * H + 1), c, font=f, fill=fg)
    im.save(path)


t0 = time.perf_counter()
pid, fd = pty.fork()
if pid == 0:
    os.chdir(tmp)
    os.execvpe("nvim", args, env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, COLS * CW, ROWS * CH))
# La sortie est lue au plus vite et horodatée ; pyte (lent) la rejoue après coup jusqu'aux
# instants des relevés. Le décodage en direct ralentissait la lecture du pty : le TUI de
# nvim, bloqué en écriture, ne lisait plus les touches (moteur demi-blocs, ~1,6 Mo).
screen = pyte.Screen(COLS, ROWS) if pyte else None
stream = pyte.ByteStream(screen) if pyte else None
snap = mid = mid_at = report_at = snap_t = None
qtail = b""
QUERIES = [(b"\x1b[c", b"\x1b[?62;22c"), (b"\x1b]11;?", b"\x1b]11;rgb:1e1e/1e1e/2e2e\x1b\\"), (b"\x1b[5n", b"\x1b[0n")]
mid_ts = []  # instants des relevés pendant l'intro
chunks = []  # (instant, octets)
last_rx = 0
answered = set()  # requêtes kitty auxquelles on a répondu (31 : intro, 32 : logo)
out, keys = bytearray(), ([(skip, KEY), (skip + 500, b"j")] if skip else [])
while True:
    el = (time.perf_counter() - t0) * 1000
    if EXPECT == "resize" and RESIZE_MS and el >= RESIZE_MS:
        ROWS, COLS = NEW_SIZE
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, COLS * CW, ROWS * CH))
        chunks.append((el, (ROWS, COLS)))  # pyte redimensionné au même instant du rejeu
        os.kill(pid, 28)  # SIGWINCH
        RESIZE_MS = 0
    if keys and el >= keys[0][0]:
        os.write(fd, keys.pop(0)[1])
    r, _, _ = select.select([fd], [], [], 0.005)
    if r:
        try:
            d = os.read(fd, 1 << 20)
        except OSError:
            break
        if not d:
            break
        # requêtes du TUI au terminal (DA1, couleur de fond, état) : on répond comme un vrai terminal
        win_q = qtail + d
        for q, ans in QUERIES:
            for _ in range(win_q.count(q) - qtail.count(q)):
                os.write(fd, ans)
        # requêtes kitty « tout est reçu ? » (intro, logo) : on répond comme kitty
        for qid in (() if os.environ.get("NOREPLY") == "1" else (b"31", b"32")):
            if qid not in answered and b"a=q,i=" + qid + b"," in qtail[-64:] + d:
                os.write(fd, b"\x1b_Gi=" + qid + b";OK\x1b\\")
                answered.add(qid)
        qtail = (qtail + d)[-64:]
        out += d
        last_rx = (time.perf_counter() - t0) * 1000
        chunks.append((last_rx, d))
    if mid_at is None and not skip and EXPECT in ("", "auto") and os.path.exists(report + ".mid"):
        mid_at = el
    # relevés pendant l'intro, entre deux frames (sortie muette depuis 15 ms), espacés de
    # 100 ms : un relevé peut tomber sur un écran à moitié redessiné, on retiendra la zone
    # animée la plus fréquente
    if mid_at and len(mid_ts) < 8 and el >= mid_at + 150 + 100 * len(mid_ts) and el - last_rx >= 15 \
            and not os.path.exists(report):
        mid_ts.append(el)
    # écran final : rapport écrit et sortie muette depuis 80 ms (le TUI a fini de dessiner)
    if snap_t is None and os.path.exists(report):
        report_at = report_at or el
        if el - last_rx >= 80 or el - report_at >= 250:
            snap_t = el
    if el > 15000:
        print("DÉLAI DÉPASSÉ")
        os.kill(pid, 9)
        break
os.waitpid(pid, 0)

# rejeu dans pyte jusqu'à chaque relevé (APC kitty et DCS retirées : pyte ne les connaît pas)
STRIP = re.compile(rb"\x1b[_P].*?\x1b\\", re.S)
mids = []
if stream:
    def grab():
        return ["".join(screen.buffer[y][x].data for x in range(screen.columns)) for y in range(screen.lines)]
    targets = [(t, "mid") for t in mid_ts] + ([(snap_t, "snap")] if snap_t is not None else [])
    pend, i = b"", 0
    for t, kind in sorted(targets):
        while i < len(chunks) and chunks[i][0] <= t:
            if isinstance(chunks[i][1], tuple):  # redimensionnement
                stream.feed(STRIP.sub(b"", pend))
                pend = b""
                screen.resize(*chunks[i][1])
            else:
                pend += chunks[i][1]
            i += 1
        pend = STRIP.sub(b"", pend)
        cut = max(pend.rfind(b"\x1b_"), pend.rfind(b"\x1bP"))
        if cut < 0 and pend.endswith(b"\x1b"):  # début de séquence coupé en fin de morceau
            cut = len(pend) - 1
        feed, pend = (pend[:cut], pend[cut:]) if cut >= 0 else (pend, b"")
        stream.feed(feed)
        if kind == "mid":
            mids.append(grab())
        else:
            snap = grab()
            if os.environ.get("PNG"):
                save_png(screen, os.environ["PNG"])
    mid = mids[0] if mids else None
wall = (time.perf_counter() - t0) * 1000

ok = True
def check(cond, msg):
    global ok
    print(("  ok   " if cond else "  ÉCHEC ") + msg)
    ok = ok and bool(cond)

if not os.path.exists(report):
    print("pas de rapport (l'intro ne s'est pas terminée ?)")
    sys.exit(1)
R = json.load(open(report))
fin = R["final"]
L = fin.get("layout") or {}
logo_rows = int(re.match(r"\d+x(\d+)$", L["logo"]).group(1)) if re.match(r"\d+x\d+$", L.get("logo") or "") else 0
print(f"disposition : logo {L.get('logo')}, gap {L.get('gap')}, récents {L.get('recent')}, "
      f"démarrage {'oui' if L.get('startup') else 'non'}, hauteur {L.get('height')}/{fin['win_h']} "
      f"(fenêtre {fin['win_w']}x{fin['win_h']})")
if EXPECT == "auto":  # intro attendue si et seulement si un logo tient
    EXPECT = "" if logo_rows else "none"

# boîte du placement kitty : même calcul que K.box (image 720x288, cellules CW x CH)
def kbox(cols, rows, w=720, h=288):
    import math
    sc = min(cols * CW / w, rows * CH / h)
    c = max(1, min(cols, math.ceil(w * sc / CW - 0.05)))
    r = max(1, min(rows, math.ceil(h * sc / CH - 0.05)))
    return c, r, (cols - c) // 2, (rows - r) // 2
KHDR = bool(L.get("kitty"))  # en-tête du dashboard en image kitty (placeholders)
FBOX = kbox(*(int(x) for x in L["logo"].split("x"))) if KHDR else None
PH = "\U0010EEEE"

def check_layout(rows):
    """le dashboard tient en entier dans la fenêtre, et ce qui est annoncé est à l'écran"""
    if fin["ft"] != "snacks_dashboard":
        return
    check(L.get("height", 999) <= fin["win_h"], f"disposition dans la fenêtre ({L.get('height')} <= {fin['win_h']} lignes)")
    check(fin["topline"] == 1 and fin["buf_lines"] <= fin["win_h"],
          f"aucun défilement (1re ligne {fin['topline']}, {fin['buf_lines']} lignes de tampon)")
    if KHDR:
        check(fin["logo_lines"] == 0, f"en-tête kitty : aucune ligne ▀ dans le tampon ({fin['logo_lines']})")
        check(fin["kitty_lines"] == FBOX[1], f"en-tête kitty {L.get('logo')} : {fin['kitty_lines']} lignes de placeholders (attendu {FBOX[1]})")
        check(fin.get("kitty_hl") == 0x4E1DF, f"placeholders de l'en-tête = logo final (id {fin.get('kitty_hl')})")
    else:
        check(fin["logo_lines"] == logo_rows, f"logo {L.get('logo')} : {fin['logo_lines']} lignes ▀")
    if logo_rows == 0:
        check(L.get("logo") == "texte", "en-tête texte « nide »")
    if rows:
        check(any("Quitter" in l for l in rows), "écran : dernière touche (Quitter) visible")
        check(not any("███╗" in l for l in rows), "écran : pas d'ancien en-tête ASCII")
        if L.get("startup"):
            check(any("Neovim loaded" in l for l in rows), "écran : ligne de démarrage visible")
        if RECENTS and L.get("recent"):
            check(any(f"recent{min(RECENTS, L['recent'])}.txt" in l for l in rows), "écran : fichiers récents visibles")
        if logo_rows == 0:
            check(any(l.strip() == "nide" for l in rows), "écran : titre « nide »")

if EXPECT == "none":
    # intro non jouée attendue (fichier ouvert, fenêtre trop petite, intro désactivée)
    print(f"sans intro attendue : terminal {COLS}x{ROWS}, buffer « {fin['ft']} », {fin['logo_lines']} lignes ▀")
    check("last" not in R, "aucune intro jouée")
    check(fin["intro_floats"] == 0, "aucune fenêtre d'intro")
    check_layout(snap)
    if snap and os.environ.get("SHOW"):
        print("\n".join(snap))
    shutil.rmtree(tmp, ignore_errors=True)
    print("OK" if ok else "ÉCHEC")
    sys.exit(0 if ok else 1)
if "last" not in R:
    print("ÉCHEC : l'intro ne s'est pas jouée")
    sys.exit(1)
last = R["last"]
print(f"mode={mode} skip={skip} terminal {COLS}x{ROWS}, durée totale {wall:.0f} ms, sortie TUI {len(out)/1024:.0f} Kio")
print(f"  intro : moteur {last['mode']}, fin « {last['reason']} » après {last['ms']:.0f} ms ; "
      f"UIEnter à {R['uienter_ms']:.0f} ms ; en-tête du dashboard : {R['header_ms']:.1f} ms au total")
if os.environ.get("DEBUG"):  # chronologie : rendus du dashboard, intro, touches reçues
    for k in ("start", "at_end", "final"):
        print(k, R.get(k, {}).get("layout"), R.get(k, {}).get("topline"), R.get(k, {}).get("win_h"))
    print("rendus :", R.get("layouts"), "intro :", R["last"], "vue à", R.get("play_seen"), "touches", R.get("keys"))
check(last["mode"] == mode, f"moteur {mode}")
want = os.environ.get("REASON") or ("resize" if EXPECT == "resize" else "skip" if skip else "done")
check(last["reason"] == want, "fin attendue : " + want)
check(fin["ft"] == "snacks_dashboard", "buffer final = snacks_dashboard")
check(logo_rows >= 7, f"logo en en-tête ({L.get('logo')})")
check(fin["intro_floats"] == 0 and not fin["playing"], "plus de fenêtre d'intro")
check_layout(snap)

# l'intro se joue dans la boîte du logo affiché à son début (avant un redimensionnement)
L0 = R.get("play_layout") or L
if re.match(r"\d+x\d+$", L0.get("logo") or ""):
    lc, lr = (int(x) for x in L0["logo"].split("x"))
    KC, KR, KDC, KDR = kbox(lc, lr) if mode == "kitty" else (lc, lr, 0, 0)
if skip:
    # 1re touche mangée (curseur inchangé), 2e touche active (curseur descendu)
    print(f"  curseur : début {R['start']['cursor']}, fin intro {R['at_end']['cursor']}, final {fin['cursor']}")
    check(R["at_end"]["cursor"] == R["start"]["cursor"], "touche qui passe l'intro mangée")
    check(fin["cursor"][0] > R["start"]["cursor"][0], "touche suivante active dans le dashboard")
if KHDR:  # fin de l'intro : le logo kitty reste, jamais de demi-blocs
    E = R["at_end"]
    check(E["logo_lines"] == 0 and E["kitty_lines"] > 0 and E.get("kitty_hl") == 0x4E1DF,
          f"fin de l'intro : en-tête kitty (logo final), pas de demi-blocs ({E['kitty_lines']} lignes, {E['logo_lines']} ▀)")
if snap:
    rows = snap
    logo = [y for y, l in enumerate(rows) if "▀" in l]
    if KHDR:
        ph = [y for y, l in enumerate(rows) if PH in l]
        check(not logo, f"écran : aucune ligne de logo demi-blocs ({len(logo)})")
        check(len(ph) == FBOX[1] and all(rows[y].count(PH) == FBOX[0] for y in ph),
              f"écran : placeholders du logo kitty {FBOX[0]}x{FBOX[1]} (lignes {ph[0] if ph else '?'}–{ph[-1] if ph else '?'})")
    else:
        check(len(logo) == logo_rows, f"écran : logo affiché (lignes {logo[0] if logo else '?'}–{logo[-1] if logo else '?'})")
    check(any("Chercher un fichier" in l for l in rows), "écran : touches du dashboard visibles")
    if mid:
        # pendant l'intro, la zone animée (▀ ou placeholders kitty) = celle du logo final
        def box(rs, ch):
            ys = [y for y, l in enumerate(rs) if ch in l]
            return ys and (ys[0], ys[-1], rs[ys[0]].index(ch), rs[ys[0]].count(ch))
        from collections import Counter
        boxes = Counter(tuple(box(m, "\U0010EEEE" if mode == "kitty" else "▀") or ()) for m in mids)
        anim = boxes.most_common(1)[0][0]
        if KHDR:  # intro jouée dans l'en-tête même : même zone que le logo final
            want_box = box(rows, PH) or ()
        else:
            fl = box(rows, "▀")
            want_box = fl and (fl[0] + KDR, fl[0] + KDR + KR - 1, fl[2] + KDC, KC) or ()
        check(anim == want_box, f"intro calée sur l'en-tête (lignes, colonne, largeur : {anim}, attendu {want_box})")
    if os.environ.get("SHOW"):
        if mid:
            print("\n".join(mid))
            print("-" * COLS)
        print("\n".join(rows))
if mode == "kitty":
    cap = "".join(R["capture"])
    apc = re.findall(r"\x1b_G([^;\x1b]*)", cap)
    raw = re.findall(rb"\x1b_G([^;\x1b]*)", bytes(out))
    print(f"  kitty : {len(apc)} commandes APC émises, {len(raw)} reçues par le terminal ; "
          f"première {apc[0]!r}, dernières {apc[-3:]!r}")
    check([r.decode() for r in raw[:len(apc)]] == apc, "toutes les séquences arrivent au terminal")
    first = next((a for a in apc if a.startswith("a=t,i=319966,")), "")
    if SSH:
        chunks = [a for a in apc if a.startswith("q=2,m=") or a.startswith("a=f,q=2,m=")]
        check(first == "a=t,i=319966,f=100,q=2,m=1", "1re frame : a=t, données directes en morceaux (m=1)")
        check(len(chunks) > 500, f"morceaux suivants : m= seul, a=f répété pour les frames ({len(chunks)})")
    else:
        check(first.startswith("a=t,i=319966,f=100,t=f,q=2"), "1re frame : a=t, t=f")
    check(sum(a.startswith("a=f,i=319966,z=") for a in apc) >= 78, "frames suivantes a=f avec z=délai")
    place = [a for a in apc if a.startswith("a=p,U=1,i=319966,")]
    check(place == [f"a=p,U=1,i=319966,c={KC},r={KR},q=2"],
          f"placement virtuel U=1 {KC}x{KR} (logo {L0.get('logo')}, cellules {CW}x{CH}) : {place}")
    if EXPECT != "resize":  # (un redimensionnement peut arrêter l'intro avant la lecture)
        check(any(a.startswith("a=a,i=319966,s=2") for a in apc), "lecture a=a,s=2")
    last_play = max([i for i, a in enumerate(apc) if a.startswith("a=a,")] or [0])
    check(any(a.startswith("a=d,d=I,i=319966") for a in apc[last_play:]), "animation effacée à la fin (a=d,d=I)")
    check(b"31" in answered, "requête a=q,i=31 envoyée (réponse simulée)")
    if KHDR:
        lplace = [a for a in apc if a.startswith("a=p,U=1,i=319967,")]
        check(sum(a.startswith("a=t,i=319967,") for a in apc) == 1, "logo final transmis une seule fois (a=t,i=319967)")
        check(lplace and lplace[-1] == f"a=p,U=1,i=319967,p=1,c={FBOX[0]},r={FBOX[1]},q=2",
              f"placement du logo final {FBOX[0]}x{FBOX[1]} : {lplace[-1:] }")
        check(b"38;2;4;225;223" in bytes(out), "couleur de l'id du logo final (#04e1df)")
        lv = report + ".leave"
        LV = json.load(open(lv)) if os.path.exists(lv) else {}
        lapc = re.findall(r"\x1b_G([^;\x1b]*)", "".join(LV.get("capture", [])))
        check(LV.get("ft") != "snacks_dashboard" and any(a.startswith("a=d,d=i,i=319967") for a in lapc),
              f"dashboard quitté : placement du logo effacé ({lapc})")
        check(b"a=d,d=I,i=319967" in bytes(out), "sortie de nvim : logo effacé (a=d,d=I,i=319967)")
    if EXPECT != "resize":
        check("\U0010EEEE".encode() in bytes(out), "placeholders U+10EEEE dessinés")
        check(b"38;2;4;225;222" in bytes(out), "couleur de l'id d'image (#04e1de)")
shutil.rmtree(tmp, ignore_errors=True)
print("OK" if ok else "ÉCHEC")
sys.exit(0 if ok else 1)
