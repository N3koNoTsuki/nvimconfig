#!/usr/bin/env bash
# Installe tout ce dont nide a besoin. Peut être relancé sans risque.
#   ./install.sh                  menu à cocher des modules (si lancé dans un terminal)
#   ./install.sh --all            tous les modules, sans menu
#   ./install.sh --only c,python  seulement ces modules (+ la base), sans menu
#   ./install.sh --yes            sans menu, garde les choix précédents (tout si aucun)
#   ./install.sh --dry-run        affiche ce qui serait fait, n'écrit et n'installe rien
# Les modules (langages, notebooks, Discord...) sont décrits dans lua/nide/modules.lua.
#
# Variables d'environnement :
#   NIDE_MODULES_FILE            autre fichier de choix (tests ; lu aussi par la config)
#   NIDE_INSTALL_CHOOSE_ONLY=1   (interne, tests) s'arrête juste après l'enregistrement du choix
set -euo pipefail

export NVIM_APPNAME=nvim
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$NVIM_APPNAME"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$NVIM_APPNAME"
BIN_DIR="$HOME/.local/bin"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die() {
	printf '\033[1;31mErreur : %s\033[0m\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage : ./install.sh [--all | --only ID,ID... | --yes] [--dry-run]

Installe nide : plugins, parsers treesitter, serveurs LSP / outils (Mason), etc.
La base (Lua, Bash, JSON, YAML, Markdown, TOML) est toujours installée ; les autres
langages et fonctions sont des modules à choisir.

  (sans option)     menu à cocher si lancé dans un terminal ; sinon garde les choix
                    précédents (ou tous les modules s'il n'y en a pas)
  --all             tous les modules, sans menu
  --only c,python   seulement ces modules (+ la base), sans menu
  --yes, -y         sans menu, garde les choix précédents (ou tous s'il n'y en a pas)
  --dry-run         affiche les modules retenus et les étapes, n'écrit et n'installe rien
  -h, --help        cette aide

Relancer le script permet de changer de modules : ceux qui sont décochés sont
désinstallés (paquets Mason, plugins), sans toucher à ce que la base utilise.
EOF
}

# --- Options ------------------------------------------------------------------
mode=""    # "" (menu si terminal), all, only, yes
only_arg=""
dry_run=0
set_mode() {
	[ -z "$mode" ] || [ "$mode" = "$1" ] || die "--all, --only et --yes ne vont pas ensemble"
	mode=$1
}
while [ $# -gt 0 ]; do
	case $1 in
	--all) set_mode all ;;
	--only)
		[ $# -ge 2 ] || die "--only attend une liste d'ids (ex. --only c,python)"
		set_mode only
		only_arg=$2
		shift
		;;
	--only=*)
		set_mode only
		only_arg=${1#--only=}
		;;
	--yes | -y) set_mode yes ;;
	--dry-run) dry_run=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "option inconnue : $1 (voir ./install.sh --help)" ;;
	esac
	shift
done

# --- Aide Lua : lit lua/nide/modules.lua (source unique des modules) ---------------
# Résultats écrits dans un fichier ($NIDE_INSTALL_OUT) : nvim --headless écrit print()
# sur stderr, et les plugins peuvent écrire sur la sortie standard.
# Action : arg[1] (nvim -l) ou $NIDE_INSTALL_ACTION (:luafile dans la config complète).
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
HELPER="$TMP_DIR/nide-install.lua"
export NIDE_INSTALL_OUT="$TMP_DIR/out"
cat >"$HELPER" <<'LUA'
local action = (_G.arg and _G.arg[1]) or vim.env.NIDE_INSTALL_ACTION
local mods = require("nide.modules")
local lines = {}

-- NIDE_INSTALL_CHOICES="c=1 rust=0 ..." : choix pas (encore) enregistrés (menu, --dry-run)
local function apply_env_choices()
	local env = vim.env.NIDE_INSTALL_CHOICES
	if not env then
		return
	end
	local t = {}
	for id, v in env:gmatch("([%w_-]+)=(%d)") do
		t[id] = v == "1"
	end
	mods.chosen = function(id)
		return t[id] ~= false
	end
	return t
end

-- Paquets Mason (base + modules donnés) ; serveurs : nom lspconfig -> nom de paquet Mason
local function packages(list, to_pkg)
	local set = {}
	local function add(m)
		for _, s in ipairs(m.servers or {}) do
			set[to_pkg and to_pkg[s] or s] = true
		end
		for _, t in ipairs(m.tools or {}) do
			set[t] = true
		end
	end
	add(mods.base)
	for _, m in ipairs(list) do
		add(m)
	end
	return set
end

-- Paquets des modules inactifs que ni la base ni un module actif n'utilisent
local function unused_packages(to_pkg)
	local active = vim.tbl_filter(function(m)
		return mods.enabled(m.id)
	end, mods.list)
	local keep, all = packages(active, to_pkg), packages(mods.list, to_pkg)
	local out = {}
	for name in pairs(all) do
		if not keep[name] then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

if action == "list" then
	-- id, libellé, description, commande requise ("-" si aucune), présente (1/0), choisi (1/0)
	for _, m in ipairs(mods.list) do
		table.insert(lines, table.concat({
			m.id, m.label, m.desc, m.requires or "-",
			(m.requires == nil or vim.fn.executable(m.requires) == 1) and "1" or "0",
			mods.chosen(m.id) and "1" or "0",
		}, "\t"))
	end
elseif action == "save" then
	mods.save(apply_env_choices() or {})
	table.insert(lines, mods.file)
elseif action == "plan" then
	apply_env_choices()
	table.insert(lines, "parsers\t" .. table.concat(mods.parsers(), " "))
	table.insert(lines, "servers\t" .. table.concat(mods.servers(), " "))
	table.insert(lines, "tools\t" .. table.concat(mods.tools(), " "))
	table.insert(lines, "unused\t" .. table.concat(unused_packages(nil), " "))
elseif action == "parsers" then
	-- attend que tous les parsers des modules actifs soient installés (la config les installe)
	local wanted = mods.parsers()
	local function missing()
		local ok, ts = pcall(require, "nvim-treesitter")
		local installed = {}
		if ok and require("lazy.core.config").plugins["nvim-treesitter"] then
			for _, p in ipairs(ts.get_installed()) do
				installed[p] = true
			end
		end
		return vim.tbl_filter(function(p)
			return not installed[p]
		end, wanted)
	end
	vim.wait(tonumber(vim.env.NIDE_INSTALL_TIMEOUT) * 1000, function()
		return #missing() == 0
	end, 1000)
	lines = missing()
elseif action == "mason-clean" then
	-- désinstalle les paquets Mason propres aux modules inactifs
	local registry = require("mason-registry")
	local to_pkg = require("mason-lspconfig").get_mappings().lspconfig_to_package
	local pending = 0
	for _, name in ipairs(unused_packages(to_pkg)) do
		if registry.has_package(name) and registry.is_installed(name) then
			pending = pending + 1
			registry.get_package(name):uninstall({}, function(ok)
				table.insert(lines, (ok and "ok\t" or "échec\t") .. name)
				pending = pending - 1
			end)
		end
	end
	vim.wait(120000, function()
		return pending == 0
	end, 200)
else
	error("action inconnue : " .. tostring(action))
end

vim.fn.writefile(lines, vim.env.NIDE_INSTALL_OUT)
LUA

# Lance l'aide sans la config de l'utilisateur (seulement lua/nide de ce dépôt)
helper() {
	rm -f "$NIDE_INSTALL_OUT"
	nvim --clean --headless --cmd "set rtp^=$CONFIG_DIR" -l "$HELPER" "$1" </dev/null &&
		[ -f "$NIDE_INSTALL_OUT" ]
}

# --- Commandes nécessaires ----------------------------------------------------
step "Commandes nécessaires"
command -v nvim >/dev/null 2>&1 || die "nvim introuvable (sudo pacman -S neovim)"
missing=0
for cmd in nvim git rg fd gcc make tree-sitter curl unzip node npm python3 lazygit; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		warn "$cmd introuvable"
		missing=1
	fi
done
if [ "$missing" = 1 ]; then
	# sans ces outils, la suite échoue (ex. sans tree-sitter, aucun parser ne compile
	# et l'étape treesitter attend pour rien) : on s'arrête tout de suite
	if command -v pacman >/dev/null 2>&1; then
		echo "Sur Arch : sudo pacman -S --needed neovim git ripgrep fd base-devel tree-sitter-cli curl unzip nodejs npm python lazygit ttf-nerd-fonts-symbols"
	fi
	if [ "$dry_run" = 1 ]; then
		warn "(--dry-run) l'installation s'arrêterait ici"
	else
		warn "installe ce qui manque, puis relance ce script"
		exit 1
	fi
fi
if ! nvim --clean --headless "+lua if vim.fn.has('nvim-0.12') == 0 then vim.cmd('cquit') end" +qa 2>/dev/null; then
	warn "Neovim 0.12 ou plus récent est nécessaire ($(nvim --version | head -1))"
	exit 1
fi
[ -f "$CONFIG_DIR/lua/nide/modules.lua" ] || die "$CONFIG_DIR/lua/nide/modules.lua introuvable (la config doit être dans $CONFIG_DIR)"

# --- Modules ------------------------------------------------------------------
step "Modules"
ids=() labels=() descs=() reqs=() req_ok=() chosen=()
helper list || die "lecture de lua/nide/modules.lua impossible"
while IFS=$'\t' read -r id label desc req ok ch; do
	ids+=("$id") labels+=("$label") descs+=("$desc") reqs+=("$req") req_ok+=("$ok") chosen+=("$ch")
done <"$NIDE_INSTALL_OUT"
n=${#ids[@]}
[ "$n" -gt 0 ] || die "aucun module lu dans lua/nide/modules.lua"

index_of() { # index du module $1, ou rien
	local i
	for ((i = 0; i < n; i++)); do
		[ "${ids[i]}" = "$1" ] && echo "$i" && return 0
	done
	return 1
}
set_all() {
	local i
	for ((i = 0; i < n; i++)); do chosen[i]=$1; done
}

show_menu() {
	local i mark pad w=0
	for ((i = 0; i < n; i++)); do
		[ "${#labels[i]}" -gt "$w" ] && w=${#labels[i]}
	done
	echo "Modules à installer (numéro pour cocher/décocher, a = tout, n = rien, Entrée pour valider) :"
	for ((i = 0; i < n; i++)); do
		mark=" "
		[ "${chosen[i]}" = 1 ] && mark=x
		# remplissage à la main : printf compte les octets, pas les caractères
		printf -v pad '%*s' $((w - ${#labels[i]} + 4)) ''
		printf '  %2d [%s] %s%s%s' $((i + 1)) "$mark" "${labels[i]}" "$pad" "${descs[i]}"
		if [ "${req_ok[i]}" = 0 ]; then
			printf ' \033[1;33m(%s absent : sudo pacman -S %s)\033[0m' "${reqs[i]}" "${reqs[i]}"
		fi
		printf '\n'
	done
}

menu() {
	local reply tok i
	local -a toks
	while true; do
		show_menu
		printf '> '
		# fin de l'entrée (Ctrl-D) : on valide comme avec Entrée
		if ! IFS= read -r reply; then
			echo
			break
		fi
		read -r -a toks <<<"${reply//,/ }"
		[ "${#toks[@]}" -eq 0 ] && break
		for tok in "${toks[@]}"; do
			case $tok in
			a | A) set_all 1 ;;
			n | N) set_all 0 ;;
			*)
				if [[ $tok =~ ^[0-9]+$ ]] && [ "$((10#$tok))" -ge 1 ] && [ "$((10#$tok))" -le "$n" ]; then
					i=$((10#$tok - 1))
				elif i=$(index_of "$tok"); then
					:
				else
					warn "« $tok » ignoré (numéro de 1 à $n, a ou n)"
					continue
				fi
				chosen[i]=$((1 - chosen[i]))
				;;
			esac
		done
		echo
	done
}

case $mode in
all) set_all 1 ;;
only)
	set_all 0
	IFS=',' read -r -a wanted <<<"${only_arg// /}"
	for id in "${wanted[@]}"; do
		[ -n "$id" ] || continue
		i=$(index_of "$id") || die "module inconnu « $id » (ids valides : $(
			IFS=,
			echo "${ids[*]}"
		))"
		chosen[i]=1
	done
	;;
yes) ;; # choix précédents (tout si aucun fichier : M.chosen)
"")
	if [ -t 0 ] && [ "$dry_run" = 0 ]; then
		menu
	elif [ -t 0 ]; then
		echo "(--dry-run : pas de menu, choix précédents)"
	else
		echo "Pas de terminal : pas de menu, choix précédents (ou tous les modules)."
	fi
	;;
esac

# choix courant, au format de l'aide Lua, et listes pour le résumé
choices_env=""
active=() inactive=()
for ((i = 0; i < n; i++)); do
	choices_env+="${ids[i]}=${chosen[i]} "
	if [ "${chosen[i]}" = 1 ] && [ "${req_ok[i]}" = 1 ]; then
		active+=("${ids[i]}")
	elif [ "${chosen[i]}" = 1 ]; then
		inactive+=("${ids[i]} (${reqs[i]} absent)")
	else
		inactive+=("${ids[i]}")
	fi
done
export NIDE_INSTALL_CHOICES="$choices_env"
is_active() { [[ " ${active[*]} " == *" $1 "* ]]; }
join() { # join "sep" éléments...
	local sep=$1
	shift
	[ $# -gt 0 ] || {
		echo "aucun"
		return
	}
	local out=$1
	shift
	for x in "$@"; do out+="$sep$x"; done
	echo "$out"
}
echo "Actifs   : $(join ', ' ${active[@]+"${active[@]}"})"
echo "Inactifs : $(join ', ' ${inactive[@]+"${inactive[@]}"})"

# --- Simulation ---------------------------------------------------------------
if [ "$dry_run" = 1 ]; then
	helper plan || die "calcul du plan impossible"
	declare -A plan=()
	while IFS=$'\t' read -r key val; do plan[$key]=$val; done <"$NIDE_INSTALL_OUT"
	step "Simulation (--dry-run) : rien n'est écrit ni installé"
	echo "Étapes qui seraient faites :"
	echo "  - enregistrer le choix dans ${NIDE_MODULES_FILE:-$DATA_DIR/nide-modules.json}"
	echo "  - lanceur $BIN_DIR/nide"
	echo "  - plugins (Lazy sync : seulement ceux de la base et des modules actifs)"
	echo "  - parsers treesitter : ${plan[parsers]:-aucun}"
	echo "  - Mason, serveurs LSP : ${plan[servers]:-aucun}"
	echo "  - Mason, outils : ${plan[tools]:-aucun}"
	echo "  - Mason, désinstaller s'ils sont installés : ${plan[unused]:-rien}"
	is_active discord && echo "  - serveur cord.nvim (activité Discord)"
	echo "  - dictionnaires français / anglais"
	is_active notebook && echo "  - notebooks : venv Python (molten, kernel), jupytext, UpdateRemotePlugins"
	exit 0
fi

# --- Enregistrement du choix (avant les plugins : lazy ne prend que les modules actifs)
helper save || die "enregistrement du choix impossible"
echo "Choix enregistré dans $(cat "$NIDE_INSTALL_OUT")"
# NIDE_INSTALL_CHOOSE_ONLY=1 : pour les tests, on s'arrête ici (rien n'est installé)
[ "${NIDE_INSTALL_CHOOSE_ONLY:-0}" = 1 ] && exit 0
unset NIDE_INSTALL_CHOICES # la suite lit le fichier enregistré

step "Commandes optionnelles"
opt=(chafa)
is_active latex && opt+=(latexmk zathura)
is_active web && opt+=(tsx)
for cmd in "${opt[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || warn "$cmd absent (optionnel)"
done
for ((i = 0; i < n; i++)); do
	[ "${chosen[i]}" = 1 ] && [ "${req_ok[i]}" = 0 ] &&
		warn "${labels[i]} : ${reqs[i]} absent, module inactif (sudo pacman -S --needed ${reqs[i]}, puis relance ce script)"
done
if command -v pacman >/dev/null 2>&1; then
	is_active latex && echo "LaTeX : sudo pacman -S --needed texlive-basic texlive-latexextra texlive-binextra zathura zathura-pdf-mupdf"
	is_active web && echo "TypeScript (F6) : npm i -g tsx"
fi

step "Lanceur $BIN_DIR/nide"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/nide" <<'EOF'
#!/bin/sh
# nide : config Neovim façon IDE (~/.config/nvim)
exec nvim "$@"
EOF
chmod +x "$BIN_DIR/nide"

step "Plugins"
nvim --headless "+Lazy! sync" +qa

step "Parsers treesitter (peut prendre quelques minutes)"
# la config installe les parsers des modules actifs au démarrage : on attend qu'ils y soient
NIDE_INSTALL_TIMEOUT=300 NIDE_INSTALL_ACTION=parsers nvim --headless "+luafile $HELPER" +qa
if [ -s "$NIDE_INSTALL_OUT" ]; then
	warn "parsers pas installés au bout de 5 min : $(paste -sd' ' "$NIDE_INSTALL_OUT")"
	warn "relance ce script, ou :TSInstall <parser> dans nvim (:checkhealth nvim-treesitter)"
fi

step "Serveurs LSP, formateurs, débogueurs (Mason)"
# nvim-lspconfig est chargé à l'ouverture d'un fichier : on le charge à la main avant l'installation
nvim --headless "+Lazy! load nvim-lspconfig nvim-dap" "+MasonToolsInstallSync" +qa
# paquets des modules décochés, que ni la base ni un module actif n'utilisent (ex. codelldb : C et Rust)
rm -f "$NIDE_INSTALL_OUT"
NIDE_INSTALL_ACTION=mason-clean nvim --headless "+Lazy! load mason.nvim mason-lspconfig.nvim" "+luafile $HELPER" +qa ||
	warn "nettoyage Mason impossible"
if [ -s "$NIDE_INSTALL_OUT" ]; then
	while IFS=$'\t' read -r status pkg; do
		if [ "$status" = ok ]; then echo "désinstallé : $pkg"; else warn "$pkg non désinstallé"; fi
	done <"$NIDE_INSTALL_OUT"
fi

if is_active discord; then
	step "Activité Discord (serveur cord.nvim)"
	# exécutable, pas seulement présent : le fichier existe pendant le téléchargement et prend son mode à la fin
	nvim --headless "+Lazy! load cord.nvim" "+Cord update fetch" \
		"+lua vim.wait(120000, function() return vim.fn.executable(vim.fn.stdpath('data') .. '/cord/bin/cord') == 1 end, 500)" +qa ||
		warn "serveur cord non téléchargé (relance ce script, ou :Cord update fetch dans nvim)"
fi

step "Dictionnaires français / anglais (orthographe)"
mkdir -p "$DATA_DIR/site/spell"
for f in fr.utf-8.spl fr.utf-8.sug en.utf-8.spl en.utf-8.sug; do
	[ -f "$DATA_DIR/site/spell/$f" ] || curl -fsSL -o "$DATA_DIR/site/spell/$f" "https://ftp.nluug.nl/pub/vim/runtime/spell/$f" || warn "$f non téléchargé"
done

if is_active notebook; then
	step "Notebooks Jupyter (venv Python : molten + kernel par défaut)"
	VENV="$DATA_DIR/molten-venv"
	if command -v uv >/dev/null 2>&1; then
		[ -x "$VENV/bin/python" ] || uv venv --python 3.13 "$VENV"
		uv pip install --quiet --python "$VENV/bin/python" pynvim jupyter_client nbformat ipykernel cairosvg pyperclip pillow \
			numpy matplotlib pandas scipy sympy
		"$VENV/bin/python" -m ipykernel install --user --name nvim-ide --display-name "Python (nvim-ide)" >/dev/null
		command -v jupytext >/dev/null 2>&1 || uv tool install jupytext
		nvim --headless "+UpdateRemotePlugins" +qa
	else
		warn "uv introuvable : notebooks désactivés (sudo pacman -S uv, puis relance ce script)"
	fi
	command -v magick >/dev/null 2>&1 || warn "imagemagick absent : pas de graphiques dans les notebooks (sudo pacman -S imagemagick)"
elif [ -f "$DATA_DIR/rplugin.vim" ] && grep -q molten "$DATA_DIR/rplugin.vim"; then
	# module notebook décoché : molten a été retiré par Lazy sync, mais ses commandes :Molten*
	# restent déclarées dans le manifeste des plugins distants tant qu'on ne le régénère pas
	nvim --headless "+UpdateRemotePlugins" +qa
fi

step "Terminé"
echo "Modules actifs   : $(join ', ' ${active[@]+"${active[@]}"})"
echo "Modules inactifs : $(join ', ' ${inactive[@]+"${inactive[@]}"})"
echo "Pour changer de modules : relance ./install.sh"
echo "Lance : nide       (puis <Espace>? pour la prise en main)"
