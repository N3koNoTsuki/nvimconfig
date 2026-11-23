#!/usr/bin/env bash
# Test de fumée de nide : démarre en headless, ouvre des fichiers de types variés,
# charge les plugins paresseux, ouvre/ferme le tutoriel, et échoue à la moindre erreur.
# Deux passes, indépendantes des modules choisis par l'utilisateur (NIDE_MODULES_FILE) :
#   1. tous les modules activés (fichier de choix absent) ;
#   2. modules réduits (sans notebook, discord, latex, rust) : les étapes de ces modules
#      sont sautées, et leurs plugins ne doivent pas être chargés.
# Usage : tests/smoke.sh   (ne laisse rien derrière lui : tout passe par un dossier temporaire)
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPNAME="$(basename "$CONFIG_DIR")"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APPNAME"
TUTO_JSON="$DATA_DIR/tuto.json"

TMP="$(mktemp -d)"
TUTO_BAK=""
cleanup() {
	# rend la progression du tutoriel telle qu'elle était
	if [[ -n "$TUTO_BAK" ]]; then
		cp -pf "$TUTO_BAK" "$TUTO_JSON"
	else
		rm -f "$TUTO_JSON"
	fi
	rm -rf "$TMP"
}
[[ -f "$TUTO_JSON" ]] && TUTO_BAK="$TMP/tuto.json.bak" && cp -p "$TUTO_JSON" "$TUTO_BAK"
trap cleanup EXIT

# Config et plugins réels ; état, cache et fichiers Jupyter isolés dans $TMP
export NVIM_APPNAME="$APPNAME"
XDG_CONFIG_HOME="$(dirname "$CONFIG_DIR")"
export XDG_CONFIG_HOME
export XDG_STATE_HOME="$TMP/state" XDG_CACHE_HOME="$TMP/cache"
export TMPDIR="$TMP/tmp" JUPYTER_RUNTIME_DIR="$TMP/jupyter" IPYTHONDIR="$TMP/ipython" MPLCONFIGDIR="$TMP/mpl"
mkdir -p "$TMPDIR"

# --- fichiers d'exemple -------------------------------------------------------
P="$TMP/projet"
mkdir -p "$P"
cat >"$P/main.lua" <<'LUA'
local function add(a, b)
	return a + b
end
print(add(1, 2))
LUA
cat >"$P/main.py" <<'PY'
def add(a: int, b: int) -> int:
    return a + b


print(add(1, 2))
PY
cat >"$P/main.c" <<'C'
#include <stdio.h>

int main(void) {
	printf("%d\n", 1 + 2);
	return 0;
}
C
cat >"$P/main.rs" <<'RS'
fn main() {
    println!("{}", 1 + 2);
}
RS
cat >"$P/doc.tex" <<'TEX'
\documentclass{article}
\begin{document}
Bonjour.
\end{document}
TEX
cat >"$P/notes.md" <<'MD'
# Titre

Du *texte* et du `code` :

```python
print("bonjour")
```
MD
cat >"$P/carnet.ipynb" <<'NB'
{"cells": [
 {"cell_type": "markdown", "metadata": {}, "source": ["# Carnet"]},
 {"cell_type": "code", "metadata": {}, "execution_count": null, "outputs": [], "source": ["x = 1 + 2\n", "x"]}
],
 "metadata": {"kernelspec": {"name": "python3", "display_name": "Python 3", "language": "python"},
  "language_info": {"name": "python"}},
 "nbformat": 4, "nbformat_minor": 5}
NB

# --- pilote Lua exécuté dans nvim --------------------------------------------
cat >"$TMP/driver.lua" <<'LUA'
local out = vim.env.SMOKE_OUT
local errors, steps = {}, {}

local function err(msg)
	table.insert(errors, msg)
end

-- v:errmsg bénins : erreurs déjà attrapées par un pcall de plugin
-- (which-key retire des raccourcis de buffer qui n'existent pas → E31)
local IGNORE = { "^E31: No such mapping" }
local function check_errmsg(where)
	local m = vim.v.errmsg
	vim.v.errmsg = ""
	if m == "" then
		return
	end
	for _, pat in ipairs(IGNORE) do
		if m:match(pat) then
			return
		end
	end
	err(where .. ", v:errmsg : " .. m)
end

-- notifications de niveau ERROR : on intercepte vim.notify jusqu'à ce que noice le remplace
-- (noice refuse d'être recouvert), puis on écoute directement les messages de noice.
local noice_hooked = false
local function hook_notify()
	if package.loaded.noice then
		if not noice_hooked then
			noice_hooked = true
			local manager = require("noice.message.manager")
			local add = manager.add
			manager.add = function(message)
				local lvl = message.level
				if lvl == "error" or lvl == vim.log.levels.ERROR or message.kind == "emsg" or message.kind == "lua_error" then
					err("noice ERROR : " .. message:content())
				end
				return add(message)
			end
		end
		return
	end
	if vim.notify == _G.__smoke_notify then
		return
	end
	local inner = vim.notify
	_G.__smoke_notify = function(msg, level, opts)
		if (level or 0) >= vim.log.levels.ERROR then
			err("notify ERROR : " .. tostring(msg))
		end
		return inner(msg, level, opts)
	end
	vim.notify = _G.__smoke_notify
end
hook_notify()

-- messages surlignés ErrorMsg (nvim_echo avec err = true ou hl ErrorMsg)
local echo = vim.api.nvim_echo
vim.api.nvim_echo = function(chunks, history, opts)
	for _, c in ipairs(chunks) do
		if c[2] == "ErrorMsg" or (opts and opts.err) then
			err("ErrorMsg : " .. tostring(c[1]))
		end
	end
	return echo(chunks, history, opts)
end

local function step(name, fn)
	hook_notify()
	local t = vim.uv.hrtime()
	check_errmsg("avant « " .. name .. " »")
	local ok, e = xpcall(fn, debug.traceback)
	if not ok then
		err(("étape « %s » : %s"):format(name, e))
	end
	vim.wait(150) -- laisse passer les callbacks programmés
	hook_notify()
	check_errmsg(("étape « %s »"):format(name))
	table.insert(steps, ("%-28s %5d ms"):format(name, (vim.uv.hrtime() - t) / 1e6))
end

local mods = require("nide.modules")

-- étape sautée : son module est désactivé (passe « modules réduits »)
local function skipped(name, id)
	if mods.enabled(id) then
		return false
	end
	table.insert(steps, ("%-28s sautée (module %s désactivé)"):format(name, id))
	return true
end

local function open(file, lsp, module)
	local name = "ouvrir " .. vim.fs.basename(file)
	if module and skipped(name, module) then
		return
	end
	step(name, function()
		vim.cmd.edit(vim.fn.fnameescape(file))
		if lsp then
			-- attend un serveur LSP (sans échouer s'il n'y en a pas)
			vim.wait(4000, function()
				return #vim.lsp.get_clients({ bufnr = 0 }) > 0
			end, 50)
		end
	end)
end

local function finish()
	hook_notify()
	vim.wait(500)
	-- erreurs restées dans v:errmsg ou :messages
	check_errmsg("fin")
	local msgs = vim.api.nvim_exec2("messages", { output = true }).output
	for line in vim.gsplit(msgs, "\n") do
		if line:match("^E%d+:") or line:match("^Error") or line:match("[Ee]rror executing") then
			err("message : " .. line)
		end
	end
	local stats = require("lazy").stats()
	local lsp = {}
	for _, c in ipairs(vim.lsp.get_clients()) do
		table.insert(lsp, c.name)
	end
	table.sort(lsp)
	local report = vim.list_extend({}, steps)
	local off = {}
	for _, m in ipairs(mods.list) do
		if not mods.enabled(m.id) then
			table.insert(off, m.id)
		end
	end
	table.insert(report, "modules désactivés : " .. (#off > 0 and table.concat(off, ", ") or "aucun"))
	table.insert(report, ("plugins chargés : %d / %d"):format(stats.loaded, stats.count))
	table.insert(report, "serveurs LSP : " .. (#lsp > 0 and table.concat(lsp, ", ") or "aucun"))
	for _, e in ipairs(errors) do
		table.insert(report, "ERREUR " .. e:gsub("\n", "\n       "))
	end
	vim.fn.writefile(vim.split(table.concat(report, "\n"), "\n"), out)
	vim.cmd("qa!")
end

vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = vim.schedule_wrap(function()
		local dir = vim.env.SMOKE_DIR
		-- erreurs du démarrage lui-même
		check_errmsg("démarrage")
		step("UIEnter + VeryLazy", function()
			-- sans interface, UIEnter n'arrive jamais : lazy (VeryLazy) et snacks l'attendent
			local fired = false
			vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", once = true, callback = function() fired = true end })
			vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
			if not vim.wait(5000, function() return fired end, 20) then
				error("VeryLazy jamais déclenché")
			end
			assert(vim.ui.select == Snacks.picker.select, "vim.ui.select n'est pas Snacks.picker.select")
			assert(vim.ui.input == Snacks.input.input, "vim.ui.input n'est pas Snacks.input")
		end)
		open(dir .. "/main.lua", true)
		open(dir .. "/main.py", true)
		open(dir .. "/main.c", true)
		open(dir .. "/notes.md", false)
		if vim.env.SMOKE_REDUCED then -- fichiers des modules désactivés : sans LSP ni plugin, mais sans erreur
			open(dir .. "/main.rs", false)
			open(dir .. "/doc.tex", false)
		end
		open(dir .. "/carnet.ipynb", false, "notebook")
		if not skipped("notebook prêt", "notebook") then
			step("notebook prêt", function()
				if not vim.wait(3000, function() return vim.b.nb_attached == true end, 20) then
					error("notebook non attaché (util.notebook.attach)")
				end
				local cells = require("util.notebook").cells(0)
				assert(#cells == 1, "attendu 1 cellule de code, trouvé " .. #cells)
			end)
		end
		step(":Tuto puis :Tuto quit", function()
			vim.cmd("Tuto")
			vim.wait(300)
			if not mods.enabled("notebook") then
				-- leçon d'un module désactivé : simple lecture, avec la note « module désactivé »
				local tuto, L = require("tuto"), require("tuto.lessons")
				for ci, ch in ipairs(L) do
					if ch.id == "notebook" then
						tuto.jump(ci, 1)
					end
				end
				for _, b in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_get_name(b):match("notebook%.ipynb$") then
						error("la leçon Notebooks a ouvert un notebook alors que le module est désactivé")
					end
				end
				local found = false
				for _, b in ipairs(vim.api.nvim_list_bufs()) do
					local t = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
					found = found or t:find("MODULE DÉSACTIVÉ", 1, true) ~= nil
				end
				assert(found, "note « module désactivé » absente du panneau du tutoriel")
			end
			vim.cmd("Tuto quit")
		end)
		step("charger tous les plugins", function()
			vim.cmd("Lazy! load all")
		end)
		step("plugins des modules inactifs", function()
			local plugins = require("lazy.core.config").plugins
			local bad = {}
			for _, m in ipairs(mods.list) do
				if not mods.enabled(m.id) then
					for _, name in ipairs(m.plugins or {}) do
						local p = plugins[vim.fs.basename(name)]
						if p and p._.loaded then
							table.insert(bad, name .. " (" .. m.id .. ")")
						end
					end
				end
			end
			assert(#bad == 0, "chargés malgré leur module désactivé : " .. table.concat(bad, ", "))
		end)
		if vim.env.SMOKE_INJECT then -- auto-vérification : SMOKE_INJECT=1 tests/smoke.sh doit échouer
			step("erreur injectée", function()
				vim.notify("erreur de test", vim.log.levels.ERROR)
				vim.schedule(function() error("erreur Lua de test") end)
			end)
		end
		finish()
	end),
})
LUA

# --- modules : tout activé, sans dépendre du choix réel de l'utilisateur ---------
# Un module dont les plugins / outils Mason / parsers ne sont pas sur le disque (décoché dans
# install.sh) reste désactivé : sinon la config les installerait au démarrage, hors de $TMP.
cat >"$TMP/modules-check.lua" <<'LUA'
local mods = require("nide.modules")
local data = vim.fn.stdpath("data")
local absent = {}
for _, m in ipairs(mods.list) do
	-- module inactif faute de sa commande (ex. go) : la config n'installera rien pour lui
	if m.requires == nil or vim.fn.executable(m.requires) == 1 then
		local ok = true
		for _, name in ipairs(m.plugins or {}) do
			ok = ok and vim.uv.fs_stat(data .. "/lazy/" .. vim.fs.basename(name)) ~= nil
		end
		for _, t in ipairs(m.tools or {}) do
			ok = ok and vim.uv.fs_stat(data .. "/mason/packages/" .. t) ~= nil
		end
		for _, p in ipairs(m.parsers or {}) do
			ok = ok and vim.uv.fs_stat(data .. "/site/parser/" .. p .. ".so") ~= nil
		end
		if not ok then
			table.insert(absent, m.id)
		end
	end
end
io.stdout:write(table.concat(absent, " "))
LUA
not_installed="$(NIDE_MODULES_FILE="$TMP/absent.json" nvim --clean --headless \
	--cmd "set rtp^=$CONFIG_DIR" -l "$TMP/modules-check.lua" 2>/dev/null || true)"
# modules_json <id désactivé>... : fichier de choix (tous les autres activés)
modules_json() {
	local id sep="" out='{"modules": {'
	for id in "$@"; do
		out+="$sep\"$id\": false"
		sep=", "
	done
	echo "$out}}"
}
export NIDE_MODULES_FILE="$TMP/modules-complet.json"
# shellcheck disable=SC2086
modules_json $not_installed >"$NIDE_MODULES_FILE"
REDUCED="$TMP/modules-reduit.json"
# shellcheck disable=SC2086
modules_json notebook discord latex rust $not_installed >"$REDUCED"
if [[ -n "$not_installed" ]]; then
	echo "Modules non installés, désactivés dans les deux passes : $not_installed"
	echo "  (pour les tester aussi : ~/.config/nvim/install.sh --all)"
fi

# --- temps de démarrage (2e lancement : cache Lua chaud) ---------------------
nvim --headless +qa >/dev/null 2>&1 || true
(cd "$P" && nvim --headless --startuptime "$TMP/startup.log" +qa >/dev/null 2>&1) || true
startup="$(awk '/--- NVIM STARTED ---/ { print $1 }' "$TMP/startup.log" | tail -1)"
echo "Démarrage : $(printf '%.0f' "${startup:-0}") ms (headless, sans fichier)"

# --- test --------------------------------------------------------------------
fail=0
# run_pass <titre> <fichier de choix> [SMOKE_REDUCED]
run_pass() {
	local title="$1" out="$TMP/report-$2.txt" code start
	echo
	echo "== $title =="
	start=$(date +%s)
	set +e
	(cd "$P" && SMOKE_OUT="$out" SMOKE_DIR="$P" timeout 40 nvim --headless --cmd "luafile $TMP/driver.lua" \
		-c "lua vim.defer_fn(function() vim.cmd('cquit 3') end, 30000)" >"$TMP/stdout.log" 2>"$TMP/stderr.log")
	code=$?
	set -e
	echo "Test : $(($(date +%s) - start)) s"

	if [[ $code -ne 0 ]]; then
		echo "nvim a quitté avec le code $code (3 ou 124 : délai dépassé)"
		fail=1
	fi
	if [[ -f "$out" ]]; then
		sed 's/^/  /' "$out"
		grep -q '^ERREUR' "$out" && fail=1
	else
		echo "Pas de rapport : le pilote n'est pas allé au bout."
		fail=1
	fi
	# erreurs Lua imprimées hors des messages (headless : sur stderr)
	if grep -Eqi 'E[0-9]+:|error|stack traceback' "$TMP/stderr.log" "$TMP/stdout.log"; then
		echo "Sortie d'erreur de nvim :"
		sed 's/^/  /' "$TMP/stderr.log" "$TMP/stdout.log" | head -40
		fail=1
	fi
	return 0
}

run_pass "Passe 1 : tous les modules" complet
NIDE_MODULES_FILE="$REDUCED" SMOKE_REDUCED=1 run_pass "Passe 2 : sans notebook, discord, latex, rust" reduit

if [[ $fail -ne 0 ]]; then
	echo "ÉCHEC"
	exit 1
fi
echo "OK"
