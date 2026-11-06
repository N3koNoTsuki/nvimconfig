#!/usr/bin/env bash
# Installs this nvim config and everything it needs. Safe to run again : what is already there is kept.
#   ./install.sh [--no-system] [--no-notebook]
#     --no-system    don't install system packages (no sudo), only report the missing ones
#     --no-notebook  skip the Jupyter part (octave, imagemagick, jupytext, molten venv)
# Only Arch (pacman) gets its packages installed, other distros get the list of missing commands.
set -euo pipefail

REPO_URL="${NVIMCONFIG_REPO:-https://github.com/N3koNoTsuki/nvimconfig.git}"
PUSH_URL="git@github.com:N3koNoTsuki/nvimconfig.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
MOLTEN_VENV="$DATA_HOME/nvim/molten-venv"

# command|Arch package|what breaks without it
# a dependency is looked up by command : it can come from anywhere (~/.local/bin, cargo, another package)
CORE_DEPS=(
	"nvim|neovim|required"
	"git|git|required"
	"make|base-devel|telescope-fzf-native and LuaSnip's jsregexp don't build"
	"gcc|base-devel|treesitter parsers don't build"
	"tree-sitter|tree-sitter-cli|treesitter parsers don't build"
	"rg|ripgrep|telescope live grep doesn't work"
	"fd|fd|optional, file search tools fall back on something else"
	"unzip|unzip|mason can't unpack its tools"
	"curl|curl|mason can't download its tools"
	"node|nodejs|mason's npm tools don't work (pyright, bash, json and yaml servers, prettierd)"
	"npm|npm|mason can't install its npm tools"
	"python3|python|mason can't install its python tools (black, flake8)"
	"wl-copy|wl-clipboard|no system clipboard on Wayland"
	"cargo|rust|Rust projects don't build from nvim"
)
NOTEBOOK_DEPS=(
	"uv|uv|notebooks skipped"
	"magick|imagemagick|notebook plots aren't displayed"
	"octave|octave|no Octave kernel"
)
ABSENT_DEPS=()

system=1
notebook=1
for arg in "$@"; do
	case "$arg" in
	--no-system) system=0 ;;
	--no-notebook) notebook=0 ;;
	-h | --help)
		sed -n '2,6p' "$0" | cut -c3-
		exit 0
		;;
	*)
		echo "unknown option: $arg" >&2
		exit 2
		;;
	esac
done

step() { printf '\n==> %s\n' "$1"; }
warn() { printf 'warning: %s\n' "$1" >&2; }
die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

export PATH="$HOME/.local/bin:$PATH"

missing_deps() {
	local dep
	for dep in "$@"; do
		command -v "${dep%%|*}" >/dev/null || printf '%s\n' "$dep"
	done
}

report_absent_deps() {
	local dep cmd package impact
	for dep in "${ABSENT_DEPS[@]}"; do
		IFS='|' read -r cmd package impact <<<"$dep"
		warn "$cmd not found (Arch package: $package) : $impact"
	done
}

install_system() {
	step "System packages"
	local deps=("${CORE_DEPS[@]}")
	if ((notebook)); then
		deps+=("${NOTEBOOK_DEPS[@]}")
	fi
	mapfile -t ABSENT_DEPS < <(missing_deps "${deps[@]}")

	if ((system && ${#ABSENT_DEPS[@]})) && command -v pacman >/dev/null; then
		local packages
		mapfile -t packages < <(printf '%s\n' "${ABSENT_DEPS[@]}" | cut -d'|' -f2 | sort -u)
		echo "to install: ${packages[*]}"
		# not fatal : what is missing gets reported below, and most of the config works without it
		if ! sudo pacman -S --needed --noconfirm "${packages[@]}"; then
			warn "pacman failed. A 404 means the package database is outdated : run 'sudo pacman -Syu', then this script again"
		fi
		mapfile -t ABSENT_DEPS < <(missing_deps "${deps[@]}")
	fi

	if ((${#ABSENT_DEPS[@]})); then
		report_absent_deps
	else
		echo "all commands found"
	fi
	command -v git >/dev/null || die "git is required"
	command -v nvim >/dev/null || die "nvim is required"
	# exit code 1 when the version is recent enough
	nvim -u NONE --headless "+lua os.exit(vim.fn.has('nvim-0.12'))" +qa && die "nvim 0.12 or newer is required"
	return 0
}

install_config() {
	step "Config in $CONFIG_DIR"
	local origin script_dir
	origin="$(git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null || true)"
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
	if [[ "$script_dir" == "$(cd "$CONFIG_DIR" 2>/dev/null && pwd -P)" || "$origin" == *nvimconfig* || "$origin" == "$REPO_URL" ]]; then
		echo "already cloned, run 'git pull' there to update"
		return
	fi
	if [[ -e "$CONFIG_DIR" ]]; then
		local backup
		backup="$CONFIG_DIR.bak-$(date +%Y%m%d-%H%M%S)"
		mv "$CONFIG_DIR" "$backup"
		echo "previous config moved to $backup"
	fi
	mkdir -p "$(dirname "$CONFIG_DIR")"
	git clone "$REPO_URL" "$CONFIG_DIR"
	# pull without any key, push through ssh
	git -C "$CONFIG_DIR" remote set-url --push origin "$PUSH_URL"
}

install_notebook() {
	step "Notebooks (jupytext, molten venv)"
	if ! command -v uv >/dev/null; then
		warn "uv not found, notebooks skipped"
		notebook=0
		return
	fi
	uv tool install jupytext
	mkdir -p "$HOME/.config/jupytext"
	if [[ ! -e "$HOME/.config/jupytext/jupytext.toml" ]]; then
		printf 'notebook_metadata_filter = "-all"\ncell_metadata_filter = "-all"\n' >"$HOME/.config/jupytext/jupytext.toml"
	fi
	mkdir -p "$DATA_HOME/nvim"
	[[ -x "$MOLTEN_VENV/bin/python" ]] || uv venv --python 3.13 "$MOLTEN_VENV"
	uv pip install --quiet --python "$MOLTEN_VENV/bin/python" \
		pynvim jupyter_client nbformat ipykernel cairosvg pyperclip octave_kernel
	# molten writes the connection file of its kernels there, without creating the directory
	mkdir -p "$DATA_HOME/jupyter/runtime"
}

# the plugins install their own things asynchronously : each step waits for them before leaving nvim
install_plugins() {
	step "Plugins (versions of lazy-lock.json)"
	nvim --headless "+Lazy! restore" +qa

	step "Treesitter parsers"
	if command -v tree-sitter >/dev/null && command -v gcc >/dev/null; then
		nvim --headless "+lua vim.wait(300000, function() local installed = require('nvim-treesitter.config').get_installed() return vim.iter(vim.g.treesitter_parsers):all(function(p) return vim.list_contains(installed, p) end) end, 500)" +qa
	else
		# they can't build : don't wait for them until the timeout
		warn "tree-sitter or gcc not found, parsers skipped"
	fi

	step "LSP servers, formatters and debuggers (mason)"
	nvim --headless "+MasonToolsInstallSync" +qa

	step "Discord server (cord.nvim)"
	# executable, not just present : the file exists during the download and gets its mode at the end
	nvim --headless "+Lazy! load cord.nvim" "+Cord update fetch" \
		"+lua vim.wait(120000, function() return vim.fn.executable(vim.fn.stdpath('data') .. '/cord/bin/cord') == 1 end, 500)" +qa

	if ((notebook)); then
		step "Molten remote plugin"
		# molten is lazy-loaded : :UpdateRemotePlugins alone doesn't see it
		nvim --headless "+Lazy! load molten-nvim" "+UpdateRemotePlugins" +qa
	fi
}

verify() {
	step "Check"
	local report failed=0
	report="$(mktemp)"
	nvim --headless "+lua require('utils.install_check').write_report('$report')" +qa 2>&1 | tail -5
	cat "$report"
	grep -qx 'theme: dms' "$report" || failed=1
	grep -qx 'cord: true' "$report" || failed=1
	grep -q '^missing ' "$report" && failed=1
	rm -f "$report"
	if ((notebook)); then
		if grep -qi molten "$DATA_HOME/nvim/rplugin.vim" 2>/dev/null; then
			echo "molten: true"
		else
			echo "molten: false"
			failed=1
		fi
		# importing them also catches a missing system library (cairo for cairosvg)
		if "$MOLTEN_VENV/bin/python" -c 'import pynvim, jupyter_client, nbformat, ipykernel, cairosvg, pyperclip, octave_kernel' 2>/dev/null; then
			echo "molten python packages: true"
		else
			echo "molten python packages: false"
			failed=1
		fi
		if command -v jupytext >/dev/null; then
			echo "jupytext: true"
		else
			echo "jupytext: false"
			failed=1
		fi
	fi
	# the plugin logs have scrolled them away since the first step
	report_absent_deps
	case ":$ORIGINAL_PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) warn "$HOME/.local/bin is not in your PATH : nvim won't find jupytext" ;;
	esac
	((failed == 0)) || die "the install is incomplete, see above"
	printf '\nDone. On the next machine : git clone %s %s && %s/install.sh\n' "$REPO_URL" "$CONFIG_DIR" "$CONFIG_DIR"
}

ORIGINAL_PATH="${PATH#"$HOME/.local/bin:"}"

install_system
install_config
((notebook)) && install_notebook
install_plugins
verify
