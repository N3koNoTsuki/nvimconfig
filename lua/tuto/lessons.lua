-- ============================================================================
--  Contenu du tutoriel. Chaque chapitre : { id, title, steps = { ... } }
--  Chaque étape : title, text, keys = { {touche, description} }, mission,
--  hint, setup(ctx), check(ctx), module (id du module requis, cf. lua/nide/modules.lua).
--  Les `accents graves` colorent les touches.
--  Le contexte `ctx` est décrit dans lua/tuto/init.lua (make_ctx).
-- ============================================================================

local function eq(a, b)
	return vim.deep_equal(a, b)
end

-- ---------------------------------------------------------------------------
-- Fichiers d'exemple
-- ---------------------------------------------------------------------------
local LSP_CODE = {
	"local M = {}",
	"",
	"--- Calcule l'aire d'un rectangle",
	"---@param largeur number",
	"---@param hauteur number",
	"---@return number",
	"local function aire(largeur, hauteur)",
	"    return largeur * hauteur",
	"end",
	"",
	"local function perimetre(largeur, hauteur)",
	"    return 2 * (largeur + hauteur)",
	"end",
	"",
	"function M.resume(l, h)",
	"    local a = aire(l, h)",
	"    local p = perimetre(l, h)",
	"    print(\"aire\", a, \"perimetre\", p)",
	"    return a + p",
	"end",
	"",
	"return M",
}

local DIAG_CODE = {
	"local nom = \"monde\"",
	"prnt(\"bonjour \" .. nom)",
	"local inutile = 42",
	"return nom",
}

local function lsp_file(ctx, at, nth)
	return ctx.open("lsp.lua", LSP_CODE, { at = at, nth = nth })
end

-- petit projet pour le chapitre Fichiers
local function project(ctx)
	local files = {
		["projet/src/main.lua"] = {
			"local utils = require(\"utils\")",
			"",
			"print(utils.bonjour(\"monde\"))",
		},
		["projet/src/utils.lua"] = {
			"local M = {}",
			"",
			"function M.bonjour(nom)",
			"    return \"bonjour \" .. nom",
			"end",
			"",
			"return M",
		},
		["projet/tests/test_utils.lua"] = {
			"local utils = require(\"utils\")",
			"assert(utils.bonjour(\"a\") == \"bonjour a\")",
		},
		["projet/README.md"] = {
			"# Projet de démonstration",
			"",
			"Un tout petit projet pour apprendre à naviguer.",
		},
		["projet/notes.txt"] = {
			"Liste de courses :",
			"- du pain",
			"- une licorne (si possible)",
		},
	}
	for name, lines in pairs(files) do
		local path = ctx.path(name)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		vim.fn.writefile(lines, path)
	end
	ctx.cd("projet")
end

-- dépôt git jetable pour le chapitre Git
local GIT_ORIG = {
	"local M = {}",
	"M.nom = \"demo\"",
	"",
	"function M.saluer()",
	"    print(\"Bonjour\")",
	"end",
	"",
	"function M.ajouter(a, b)",
	"    return a + b",
	"end",
	"",
	"function M.vieux()",
	"    return \"à supprimer\"",
	"end",
	"",
	"return M",
}
local GIT_NEW = {
	"local M = {}",
	"M.nom = \"démo git\"",
	"",
	"function M.saluer()",
	"    print(\"Bonjour\")",
	"end",
	"",
	"function M.ajouter(a, b)",
	"    return a + b",
	"end",
	"",
	"function M.multiplier(a, b)",
	"    return a * b",
	"end",
	"",
	"return M",
}

local function git_repo(ctx)
	local repo = ctx.path("git-demo")
	vim.fn.delete(repo, "rf")
	vim.fn.mkdir(repo, "p")
	vim.fn.writefile(GIT_ORIG, repo .. "/app.lua")
	local git = { "git", "-C", repo, "-c", "user.name=Tuto", "-c", "user.email=tuto@example.invalid", "-c", "commit.gpgsign=false" }
	vim.fn.system({ "git", "init", "-q", repo })
	vim.fn.system(vim.list_extend(vim.deepcopy(git), { "add", "app.lua" }))
	vim.fn.system(vim.list_extend(vim.deepcopy(git), { "commit", "-q", "-m", "Premier commit" }))
	ctx.cd("git-demo")
	return ctx.open("git-demo/app.lua", GIT_NEW)
end

local function git_hunks(ctx)
	local ok, gs = pcall(require, "gitsigns")
	if not ok or not ctx.buf then
		return {}
	end
	local ok2, hunks = pcall(gs.get_hunks, ctx.buf)
	return ok2 and hunks or {}
end

local DEBUG_PY = {
	"def somme(liste):",
	"    total = 0",
	"    for x in liste:",
	"        total += x",
	"    return total",
	"",
	"",
	"print(somme([1, 2, 3]))",
}

local function breakpoints(ctx)
	local ok, bps = pcall(require, "dap.breakpoints")
	if not ok or not ctx.buf then
		return 0
	end
	local list = bps.get(ctx.buf)[ctx.buf] or {}
	return #list
end

-- ---------------------------------------------------------------------------
-- Notebook d'exemple (format .ipynb)
-- ---------------------------------------------------------------------------
local NOTEBOOK = {
	vim.json.encode({
		cells = {
			{ cell_type = "markdown", metadata = vim.empty_dict(), source = { "# Mon premier notebook\n", "\n", "Du texte, puis des cellules de code." } },
			{ cell_type = "code", metadata = vim.empty_dict(), execution_count = vim.NIL, outputs = {}, source = { "a = 6 * 7\n", "print(\"La réponse :\", a)" } },
			{ cell_type = "markdown", metadata = vim.empty_dict(), source = { "## Un graphique" } },
			{ cell_type = "code", metadata = vim.empty_dict(), execution_count = vim.NIL, outputs = {}, source = { "import numpy as np\n", "import matplotlib.pyplot as plt\n", "x = np.linspace(0, 6, 100)\n", "plt.plot(x, np.sin(x))\n", "plt.show()" } },
			{ cell_type = "code", metadata = vim.empty_dict(), execution_count = vim.NIL, outputs = {}, source = { "a * 2" } },
		},
		metadata = { kernelspec = { name = "nvim-ide", display_name = "Python (nvim-ide)", language = "python" } },
		nbformat = 4,
		nbformat_minor = 5,
	}),
}

local function notebook_open(ctx, at)
	local exists = vim.uv.fs_stat(ctx.path("notebook.ipynb")) ~= nil
	return ctx.open("notebook.ipynb", (not exists) and NOTEBOOK or nil, at and { at = at, keep = true } or { cursor = { 1, 0 }, keep = true })
end

local function notebook_cells(ctx)
	if not ctx.buf or not vim.api.nvim_buf_is_valid(ctx.buf) then
		return {}
	end
	local ok, cells = pcall(function()
		return require("util.notebook").cells(ctx.buf)
	end)
	return ok and cells or {}
end

-- nombre de cellules exécutées (sorties molten « Out[n] » affichées)
local function notebook_ran(ctx)
	if not ctx.buf or not vim.api.nvim_buf_is_valid(ctx.buf) then
		return 0
	end
	local n = 0
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(ctx.buf, -1, 0, -1, { details = true })) do
		local vl = m[4].virt_lines
		if vl and vl[1] then
			local first = ""
			for _, chunk in ipairs(vl[1]) do
				first = first .. chunk[1]
			end
			if first:match("Out%[%d+%]") then
				n = n + 1
			end
		end
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Exécuter et compiler
-- ---------------------------------------------------------------------------
local RUN_PY = {
	"def carre(n):",
	"    return n * n",
	"",
	"",
	"for i in range(1, 6):",
	"    print(i, \"au carré =\", carre(i))",
	"",
	"print(\"Fini !\")",
}

-- il manque un point-virgule ligne 10
local RUN_C = {
	"#include <stdio.h>",
	"",
	"int carre(int n) {",
	"    return n * n;",
	"}",
	"",
	"int main(void) {",
	"    int total = 0;",
	"    for (int i = 1; i <= 5; i++) {",
	"        total += carre(i)",
	"    }",
	"    printf(\"Somme des carrés : %d\\n\", total);",
	"    return 0;",
	"}",
}

-- erreurs (type E) de la dernière compilation F6 de `name`, ou nil si la quickfix vient d'ailleurs
local function compile_errors(name)
	local qf = vim.fn.getqflist({ title = 0, items = 0 })
	if not (qf.title or ""):match("^Compilation") or not qf.title:find(name, 1, true) then
		return nil
	end
	local n = 0
	for _, item in ipairs(qf.items or {}) do
		if item.valid == 1 and (item.type == "E" or item.type == "e") then
			n = n + 1
		end
	end
	return n
end

-- cache les terminaux visibles (F6, Espace t t…) pour repartir d'un écran propre
local function hide_terminals()
	pcall(function()
		for _, t in ipairs(Snacks.terminal.list()) do
			if t:win_valid() then
				t:hide()
			end
		end
	end)
end

-- ferme les panneaux (explorateur, plan, problèmes, tâches…) pour que Espace u I les ouvre
local function close_panels()
	hide_terminals()
	pcall(function()
		for _, p in ipairs(Snacks.picker.get({ source = "explorer" })) do
			p:close()
		end
	end)
	pcall(function()
		if package.loaded.edgy then
			require("edgy").close()
		end
	end)
end

-- petit projet avec un Makefile pour les tâches
local function make_project(ctx)
	local files = {
		["taches/Makefile"] = {
			"bonjour: bonjour.c",
			"\tgcc -Wall -o bonjour bonjour.c",
			"",
			"clean:",
			"\trm -f bonjour",
		},
		["taches/bonjour.c"] = {
			"#include <stdio.h>",
			"",
			"int main(void) {",
			"    printf(\"Bonjour depuis make !\\n\");",
			"    return 0;",
			"}",
		},
	}
	for name, lines in pairs(files) do
		local path = ctx.path(name)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		vim.fn.writefile(lines, path)
	end
	vim.fn.delete(ctx.path("taches/bonjour"))
	ctx.cd("taches")
	return ctx.open("taches/bonjour.c")
end

local function overseer_tasks()
	if not package.loaded.overseer then
		return {}
	end
	local ok, tasks = pcall(function()
		return require("overseer").list_tasks()
	end)
	return ok and tasks or {}
end

-- ---------------------------------------------------------------------------
-- Compiler le projet (Espace k)
-- ---------------------------------------------------------------------------
-- il manque la déclaration de `resultat` dans moyenne()
local COMPIL_MAIN = {
	"#include <stdio.h>",
	"",
	"#include \"stats.h\"",
	"",
	"int main(void) {",
	"    int notes[] = { 12, 15, 9, 18 };",
	"    printf(\"Moyenne : %.2f\\n\", moyenne(notes, 4));",
	"    return 0;",
	"}",
}

local COMPIL_STATS_H = {
	"#ifndef STATS_H",
	"#define STATS_H",
	"",
	"double moyenne(const int *t, int n);",
	"",
	"#endif",
}

local COMPIL_STATS_C = {
	"#include \"stats.h\"",
	"",
	"double moyenne(const int *t, int n) {",
	"    int somme = 0;",
	"    for (int i = 0; i < n; i++) {",
	"        somme += t[i];",
	"    }",
	"    resultat = (double)somme / n;",
	"    return resultat;",
	"}",
}

-- petit projet C à plusieurs fichiers, avec une erreur dans stats.c
local function compil_project(ctx, fresh)
	local files = {
		["compil/Makefile"] = {
			"moyenne: main.c stats.c stats.h",
			"\tgcc -Wall -g -o moyenne main.c stats.c",
			"",
			"clean:",
			"\trm -f moyenne",
		},
		["compil/main.c"] = COMPIL_MAIN,
		["compil/stats.h"] = COMPIL_STATS_H,
		["compil/stats.c"] = COMPIL_STATS_C,
	}
	for name, lines in pairs(files) do
		local path = ctx.path(name)
		if fresh or not vim.uv.fs_stat(path) then
			vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
			vim.fn.writefile(lines, path)
		end
	end
	if fresh then
		vim.fn.delete(ctx.path("compil/moyenne"))
	end
	ctx.cd("compil")
end

-- module util.compile (chargé à la demande) et dernière compilation du projet d'exercice
local function compile_mod()
	local ok, c = pcall(require, "util.compile")
	return ok and c or nil
end

local function compiled_here(c)
	return c and c.last and c.result and vim.endswith(c.last.root or "", "/tuto/compil")
end

-- ---------------------------------------------------------------------------
-- Débogueur : F5 sur un programme C
-- ---------------------------------------------------------------------------
local DEBUG_C = {
	"#include <stdio.h>",
	"",
	"int factorielle(int n) {",
	"    int resultat = 1;",
	"    for (int i = 2; i <= n; i++) {",
	"        resultat *= i;",
	"    }",
	"    return resultat;",
	"}",
	"",
	"int main(void) {",
	"    int n = 5;",
	"    printf(\"%d! = %d\\n\", n, factorielle(n));",
	"    return 0;",
	"}",
}

local DEBUG_SCANF = {
	"#include <stdio.h>",
	"",
	"int main(void) {",
	"    int n;",
	"    printf(\"Entre un nombre : \");",
	"    fflush(stdout);",
	"    if (scanf(\"%d\", &n) != 1) {",
	"        printf(\"Ce n'est pas un nombre.\\n\");",
	"        return 1;",
	"    }",
	"    printf(\"Le double de %d est %d\\n\", n, 2 * n);",
	"    return 0;",
	"}",
}

local function dap_session()
	if not package.loaded.dap then
		return nil
	end
	return require("dap").session()
end

-- arrête une session restée ouverte (étape précédente) et ferme l'interface
local function dap_reset()
	pcall(function()
		if dap_session() then
			require("dap").terminate()
		end
	end)
	pcall(function()
		if package.loaded.dapui then
			require("dapui").close()
		end
	end)
end

-- un terminal de l'onglet contient `pat` (console du programme débogué)
local function console_has(pat)
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "terminal" then
			for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
				if l:find(pat) then
					return true
				end
			end
		end
	end
	return false
end

-- efface `pat` des consoles terminées (une étape recommencée repart de zéro)
local function console_clear(pat)
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "terminal" then
			local id = vim.b[b].terminal_job_id
			local done = not id or vim.fn.jobwait({ id }, 0)[1] ~= -1
			local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
			for i, l in ipairs(lines) do
				if done and l:find(pat) then
					pcall(function()
						local mod = vim.bo[b].modifiable
						vim.bo[b].modifiable = true
						vim.api.nvim_buf_set_lines(b, i - 1, i, false, { "" })
						vim.bo[b].modifiable = mod
						vim.bo[b].modified = false
					end)
				end
			end
		end
	end
end

local function dapui_visible(ctx)
	return ctx.visible_ft("dapui_scopes") or ctx.visible_ft("dapui_console")
end

-- ---------------------------------------------------------------------------
-- Outils de nide
-- ---------------------------------------------------------------------------
local function close_doctor()
	pcall(function()
		local d = package.loaded["util.doctor"]
		if d and d.state and d.state.win and d.state.win:valid() then
			d.state.win:close()
		end
	end)
end

-- sous-dossiers du dossier d'exercices
local function subdirs(dir)
	local out = {}
	for name, t in vim.fs.dir(dir) do
		if t == "directory" then
			out[name] = true
		end
	end
	return out
end

local FILLER = {
	"Le vent souffle sur la colline et les arbres dansent doucement.",
	"Un renard traverse le chemin sans se presser du tout.",
	"La riviere coule vers la mer en chantant sur les cailloux.",
	"Les nuages passent, lents et gris, au-dessus du village.",
	"Une cloche sonne au loin pour annoncer midi.",
}

-- ---------------------------------------------------------------------------
-- Chapitres
-- ---------------------------------------------------------------------------
return {
	-- =======================================================================
	{
		id = "bienvenue",
		title = "Bienvenue",
		steps = {
			{
				title = "Comment marche ce tutoriel",
				text = {
					"Bienvenue dans nvim-ide ! Ici on apprend en pratiquant.",
					"",
					"À gauche : ce panneau, avec l'explication et une mission.",
					"À droite : un vrai fichier d'entraînement. Tu ne peux rien casser : il est recréé à chaque étape.",
					"",
					"Quand une mission est réussie, l'étape se valide toute seule (✓) et on passe à la suivante.",
				},
				keys = {
					{ "n / →", "étape suivante" },
					{ "p / ←", "étape précédente" },
					{ "m", "carte de tous les chapitres" },
					{ "r", "recommencer l'étape" },
					{ "<Tab>", "aller dans le fichier à droite" },
					{ "q", "quitter le tutoriel" },
				},
				setup = function(ctx)
					ctx.open("bienvenue.txt", {
						"Ceci est le fichier d'entraînement.",
						"",
						"Les missions se passent ici, à droite.",
					})
				end,
			},
			{
				title = "Aller dans le fichier",
				text = "Le curseur est soit dans ce panneau, soit dans le fichier à droite.",
				mission = "Appuie sur `<Tab>` pour passer dans le fichier à droite.",
				setup = function(ctx)
					ctx.open("bienvenue.txt", { "Te voilà dans le fichier d'entraînement !" })
				end,
				check = function(ctx)
					return ctx.in_practice()
				end,
			},
			{
				title = "Changer de fenêtre",
				text = {
					"Dans tout l'IDE, `Ctrl` + une direction passe d'une fenêtre à l'autre :",
					"`<C-h>` gauche, `<C-j>` bas, `<C-k>` haut, `<C-l>` droite.",
				},
				mission = "Reviens dans ce panneau avec `<C-h>`, puis retourne à droite avec `<C-l>`.",
				check = function(ctx)
					if ctx.in_panel() then
						ctx.state.left = true
					end
					return ctx.state.left and ctx.in_practice()
				end,
			},
			{
				title = "Avancer depuis le fichier",
				text = {
					"Pas besoin de revenir ici pour avancer. Depuis le fichier d'entraînement :",
					"`Alt-n` / `Alt-p` étape suivante / précédente, `Alt-r` recommencer, `Alt-m` la carte.",
					"",
					"La carte liste tous les chapitres avec ta progression : tu peux te balader et sauter où tu veux.",
				},
				mission = "Ouvre la carte avec `Alt-m` (ou `m` ici). Promène-toi avec `j`/`k`, puis `Échap` pour la fermer.",
				check = function(ctx)
					return ctx.seen("tuto_menu")
				end,
			},
			{
				title = "La touche Leader : Espace",
				text = {
					"Presque tous les raccourcis de l'IDE commencent par `Espace` (le « leader »).",
					"Dans ce tuto, `<Space>ff` veut dire : Espace, puis f, puis f.",
					"",
					"Si tu appuies sur `Espace` et que tu attends, un menu affiche toutes les suites possibles, rangées par thème. C'est LA façon de découvrir l'IDE.",
				},
				keys = {
					{ "<Space>", "menu de tous les raccourcis" },
					{ "<Space>?", "rouvrir ce tutoriel" },
				},
				mission = "Dans le fichier à droite, appuie sur `Espace` et attends une demi-seconde. Regarde le menu, puis `Échap`.",
				check = function(ctx)
					return ctx.seen("wk") or ctx.typed("<Space><Esc>")
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "survie",
		title = "Survie : les modes",
		steps = {
			{
				title = "Les modes",
				text = {
					"Vim a plusieurs modes. C'est LA chose à comprendre :",
					"• Normal : on se déplace et on lance des commandes. C'est le mode par défaut.",
					"• Insertion : on tape du texte, comme partout ailleurs.",
					"• Visuel : on sélectionne du texte.",
					"• Commande : on tape une commande après `:`.",
					"",
					"Le mode actuel est affiché en bas à gauche.",
				},
				keys = {
					{ "i", "insérer avant le curseur" },
					{ "a", "insérer après le curseur" },
					{ "o / O", "nouvelle ligne dessous / dessus" },
					{ "<Esc>", "revenir en mode Normal" },
					{ "v / V", "sélectionner (caractères / lignes)" },
					{ ":", "taper une commande" },
				},
				setup = function(ctx)
					ctx.open("survie.txt", { "Essaie i, tape du texte, puis Échap.", "" })
				end,
			},
			{
				title = "Écrire du texte",
				mission = "Descends sur la ligne vide (`j`), appuie sur `i`, tape  vim c'est cool  puis `Échap`.",
				setup = function(ctx)
					ctx.open("survie.txt", {
						"Ceci est ton fichier d'entraînement.",
						"Écris sur la ligne vide ci-dessous :",
						"",
						"Fin du fichier.",
					})
				end,
				check = function(ctx)
					return ctx.text():lower():find("vim c.est cool") ~= nil and ctx.mode() == "n"
				end,
			},
			{
				title = "Sauvegarder",
				text = "Un fichier modifié a un ● dans son onglet en haut.",
				keys = {
					{ "<C-s>", "sauvegarder (même en insertion)" },
					{ ":w", "sauvegarder (façon Vim)" },
					{ ":wa", "tout sauvegarder" },
				},
				mission = "Ce fichier vient d'être modifié. Sauvegarde-le avec `<C-s>` (ou `:w` puis Entrée).",
				setup = function(ctx)
					local buf = ctx.open("survie.txt", { "Ligne d'origine." })
					if buf then
						vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Texte pas encore sauvegardé !" })
					end
				end,
				check = function(ctx)
					return ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) and not vim.bo[ctx.buf].modified
				end,
			},
			{
				title = "Annuler / refaire",
				keys = {
					{ "u", "annuler" },
					{ "<C-r>", "refaire" },
					{ "<Space>su", "historique complet des annulations" },
				},
				mission = "Supprime la ligne SUPPRIME-MOI avec `dd`, annule avec `u`, puis refais la suppression avec `<C-r>`.",
				setup = function(ctx)
					ctx.open("survie.txt", { "ligne 1", "SUPPRIME-MOI", "ligne 3" }, { cursor = { 2, 0 } })
				end,
				check = function(ctx)
					local has = ctx.has("SUPPRIME-MOI")
					local s = ctx.state
					s.phase = s.phase or 0
					if s.phase == 0 and not has then
						s.phase = 1
					elseif s.phase == 1 and has then
						s.phase = 2
					elseif s.phase == 2 and not has then
						return true
					end
					return false
				end,
			},
			{
				title = "Quitter",
				text = "Si tu quittes avec des modifications non sauvegardées, nvim te demande quoi faire : pas de perte surprise.",
				keys = {
					{ ":q", "fermer la fenêtre" },
					{ ":q!", "fermer sans sauvegarder" },
					{ ":wq", "sauvegarder et fermer" },
					{ "<Space>qq", "tout quitter" },
					{ "<Space>bd", "fermer le fichier (l'onglet)" },
				},
			},
		},
	},

	-- =======================================================================
	{
		id = "move",
		title = "Se déplacer",
		steps = {
			{
				title = "Les bases",
				text = "En mode Normal, les lettres déplacent le curseur. La souris marche aussi, mais le clavier est bien plus rapide.",
				keys = {
					{ "h j k l", "← ↓ ↑ →" },
					{ "w / b", "mot suivant / précédent" },
					{ "e", "fin du mot" },
					{ "0 / $", "début / fin de ligne" },
					{ "^", "premier caractère non blanc" },
					{ "3w, 5j…", "un nombre répète le mouvement" },
				},
				mission = "Place le curseur sur le mot CIBLE.",
				setup = function(ctx)
					ctx.open("deplacement.txt", {
						"Le curseur est en haut à gauche.",
						"Descends avec j et avance de mot en mot avec w.",
						"",
						"un deux trois quatre cinq",
						"six sept huit neuf dix",
						"onze douze CIBLE treize quatorze",
						"quinze seize dix-sept",
					})
				end,
				check = function(ctx)
					return ctx.word() == "CIBLE"
				end,
			},
			{
				title = "Les grands sauts",
				keys = {
					{ "gg / G", "début / fin du fichier" },
					{ "42G", "aller à la ligne 42" },
					{ "{ / }", "paragraphe précédent / suivant" },
					{ "<C-d>/<C-u>", "descendre / monter d'une demi-page" },
					{ "%", "parenthèse correspondante" },
				},
				mission = "Va tout en bas du fichier avec `G`, puis remonte en haut avec `gg`.",
				setup = function(ctx)
					local lines = {}
					for i = 1, 80 do
						lines[i] = (i % 6 == 0) and "" or string.format("ligne %d : %s", i, FILLER[i % #FILLER + 1])
					end
					lines[#lines + 1] = "FIN"
					ctx.open("sauts.txt", lines, { cursor = { 10, 0 } })
				end,
				check = function(ctx)
					local last = #ctx.lines()
					if ctx.row() == last then
						ctx.state.bottom = true
					end
					return ctx.state.bottom and ctx.row() == 1
				end,
			},
			{
				title = "Sauter n'importe où (flash)",
				text = {
					"`s` puis 2 lettres : des étiquettes apparaissent sur toutes les correspondances visibles. Tape l'étiquette pour y sauter.",
					"`S` sélectionne un bloc de code entier (fonction, if, argument…).",
					"`f` + lettre saute sur la ligne ; `f` encore → occurrence suivante. `t` s'arrête juste avant.",
				},
				keys = {
					{ "s", "sauter (flash)" },
					{ "S", "sélectionner un bloc (flash)" },
					{ "f / t", "sauter sur / avant une lettre" },
					{ "F / T", "pareil, vers la gauche" },
				},
				mission = "Saute sur TRESOR : `s`, tape `tr`, puis la lettre de l'étiquette.",
				setup = function(ctx)
					local lines = {}
					for i = 1, 24 do
						lines[i] = FILLER[i % #FILLER + 1]
					end
					lines[17] = "Sous le vieux chene se cache un TRESOR enfoui depuis longtemps."
					ctx.open("flash.txt", lines)
				end,
				check = function(ctx)
					return ctx.word() == "TRESOR"
				end,
			},
			{
				title = "Rechercher",
				keys = {
					{ "/texte", "chercher vers le bas (Entrée)" },
					{ "?texte", "chercher vers le haut" },
					{ "n / N", "résultat suivant / précédent" },
					{ "*", "chercher le mot sous le curseur" },
					{ "<Esc>", "effacer le surlignage" },
				},
				mission = "Tape `/aiguille` puis Entrée, puis `n` jusqu'à la 3e aiguille.",
				setup = function(ctx)
					ctx.open("recherche.txt", {
						"Une botte de foin.",
						"Une aiguille numero un.",
						"Encore du foin.",
						"Du foin, du foin.",
						"Une aiguille numero deux.",
						"Toujours du foin.",
						"La troisieme aiguille est ici.",
						"Et une quatrieme aiguille.",
					})
				end,
				check = function(ctx)
					local pos = ctx.find("aiguille", 3)
					return pos and ctx.row() == pos[1] and ctx.word() == "aiguille"
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "edit",
		title = "Éditer vite",
		steps = {
			{
				title = "Verbe + objet",
				text = {
					"Les commandes se combinent comme une phrase : verbe + objet.",
					"`ciw` = change inner word = remplace le mot sous le curseur.",
					"`di(` = supprime le contenu des parenthèses, `ya\"` = copie la chaîne avec ses guillemets…",
				},
				keys = {
					{ "d", "supprimer (delete)" },
					{ "c", "changer (supprime + insertion)" },
					{ "y", "copier (yank)" },
					{ "iw / aw", "le mot (sans / avec l'espace)" },
					{ "i\" / a\"", "entre guillemets" },
					{ "i( / a(", "entre parenthèses" },
				},
				mission = "Remplace rouge par bleu : le curseur est sur rouge, fais `ciw`, tape bleu, puis `Échap`.",
				setup = function(ctx)
					ctx.open("edition.txt", { "couleur = \"rouge\"", "taille = \"petite\"" }, { at = "rouge" })
				end,
				check = function(ctx)
					return (ctx.lines()[1] or ""):find("\"bleu\"", 1, true) ~= nil and ctx.mode() == "n"
				end,
			},
			{
				title = "Lignes entières",
				keys = {
					{ "dd", "supprimer la ligne" },
					{ "yy", "copier la ligne" },
					{ "p / P", "coller dessous / dessus" },
					{ "x", "supprimer un caractère" },
					{ "J", "joindre la ligne suivante" },
				},
				mission = "Supprime la ligne supprime-moi (`dd`), puis duplique la ligne duplique-moi (`yy` puis `p`).",
				setup = function(ctx)
					ctx.open("lignes.txt", { "garde-moi", "supprime-moi", "duplique-moi", "garde-moi aussi" })
				end,
				check = function(ctx)
					local n = { del = 0, dup = 0 }
					for _, l in ipairs(ctx.tlines()) do
						if l == "supprime-moi" then
							n.del = n.del + 1
						elseif l == "duplique-moi" then
							n.dup = n.dup + 1
						end
					end
					return n.del == 0 and n.dup == 2 and ctx.has("garde-moi aussi")
				end,
			},
			{
				title = "Répéter avec le point",
				text = "`.` rejoue la dernière modification. C'est un des raccourcis les plus puissants de Vim.",
				keys = {
					{ "A", "insérer à la fin de la ligne" },
					{ "I", "insérer au début de la ligne" },
					{ ".", "répéter la dernière modification" },
				},
				mission = "Ajoute ; à la fin des 4 lignes : `A;` puis `Échap` sur la 1re, puis `j.` trois fois.",
				setup = function(ctx)
					ctx.open("point.txt", { "a = 1", "b = 2", "c = 3", "d = 4" })
				end,
				check = function(ctx)
					local l = ctx.tlines()
					for i = 1, 4 do
						if not (l[i] or ""):find(";$") then
							return false
						end
					end
					return true
				end,
			},
			{
				title = "Objets texte avancés",
				text = "mini.ai ajoute des objets « intelligents » : arguments, appels de fonction, n'importe quels guillemets ou parenthèses.",
				keys = {
					{ "ci\"", "changer le texte entre guillemets" },
					{ "daa", "supprimer un argument (+ la virgule)" },
					{ "cia", "changer un argument" },
					{ "cif", "changer les arguments d'un appel" },
					{ "ciq / cib", "n'importe quels guillemets / parenthèses" },
				},
				mission = {
					"1) Curseur dans les guillemets, `ci\"`, tape nouveau, `Échap`.",
					"2) Curseur sur le 2 de autre(1, 2), puis `daa`.",
				},
				setup = function(ctx)
					ctx.open("objets.txt", { "print(\"ancien texte\", autre(1, 2))" }, { at = "ancien" })
				end,
				check = function(ctx)
					local l = ctx.lines()[1] or ""
					return l:find("\"nouveau\"", 1, true) ~= nil and l:find("autre(1)", 1, true) ~= nil
				end,
			},
			{
				title = "Entourer (surround)",
				keys = {
					{ "gsaiw\"", "entourer le mot de \"" },
					{ "gsd'", "supprimer les ' autour" },
					{ "gsr)]", "remplacer ( ) par [ ]" },
					{ "gsa (visuel)", "entourer la sélection" },
				},
				mission = {
					"Ligne 1 : `gsaiw\"`",
					"Ligne 2 : `gsr)]` (curseur dans les parenthèses)",
					"Ligne 3 : `gsd'`",
				},
				setup = function(ctx)
					ctx.open("surround.txt", { "mot", "(a + b)", "'supprime'" })
				end,
				check = function(ctx)
					local l = ctx.tlines()
					return l[1] == "\"mot\"" and (l[2] or ""):find("^%[%s*a %+ b%s*%]$") ~= nil and l[3] == "supprime"
				end,
			},
			{
				title = "Commenter",
				keys = {
					{ "gcc", "commenter / décommenter la ligne" },
					{ "gcip", "commenter le paragraphe" },
					{ "gc (visuel)", "commenter la sélection" },
				},
				mission = "Commente la ligne 2 avec `gcc`.",
				setup = function(ctx)
					ctx.open("commentaire.lua", { "local a = 1", "local b = 2", "print(a + b)" }, { cursor = { 2, 0 } })
				end,
				check = function(ctx)
					local l = ctx.tlines()
					return (l[2] or ""):find("^%-%-") ~= nil and not (l[1] or ""):find("^%-%-")
				end,
			},
			{
				title = "Déplacer des lignes",
				keys = {
					{ "Alt-j / Alt-k", "descendre / monter la ligne" },
					{ "Alt-h / Alt-l", "désindenter / indenter" },
					{ "> / <", "indenter (en visuel)" },
				},
				hint = "Ça marche aussi sur une sélection (`V` puis `Alt-j`).",
				mission = "Remets les lignes dans l'ordre 1, 2, 3 avec `Alt-k` / `Alt-j`.",
				setup = function(ctx)
					ctx.open("ordre.txt", { "2. deux", "3. trois", "1. un" }, { cursor = { 3, 0 } })
				end,
				check = function(ctx)
					return eq(ctx.tlines(), { "1. un", "2. deux", "3. trois" })
				end,
			},
			{
				title = "Le mode visuel",
				keys = {
					{ "v", "sélection de caractères" },
					{ "V", "sélection de lignes" },
					{ "<C-v>", "sélection en bloc (colonnes)" },
					{ "o", "aller à l'autre bout" },
					{ "gv", "resélectionner" },
				},
				mission = "Sélectionne les 3 lignes efface avec `V` puis `jj`, et supprime-les avec `d`.",
				setup = function(ctx)
					ctx.open("visuel.txt", { "garde", "efface", "efface", "efface", "garde" }, { cursor = { 2, 0 } })
				end,
				check = function(ctx)
					return eq(ctx.tlines(), { "garde", "garde" })
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "multi",
		title = "Multi-curseurs",
		steps = {
			{
				title = "Plusieurs occurrences",
				text = {
					"Comme Ctrl+D dans VS Code : chaque `<C-n>` ajoute un curseur sur l'occurrence suivante du mot.",
					"Ensuite, tout ce que tu tapes s'applique à tous les curseurs. `Échap` les retire.",
				},
				keys = {
					{ "<C-n>", "curseur sur l'occurrence suivante" },
					{ "<C-S-n>", "sauter cette occurrence" },
					{ "<Space>cM", "curseurs sur TOUTES les occurrences" },
					{ "← / →", "passer d'un curseur à l'autre" },
					{ "<Esc>", "retirer les curseurs" },
				},
				mission = "Renomme total en somme partout : `<C-n>` 5 fois, puis `ciw` somme `Échap`, puis `Échap` encore.",
				setup = function(ctx)
					ctx.open("multi.lua", {
						"local total = 0",
						"total = total + 1",
						"total = total * 2",
						"print(total)",
					}, { at = "total" })
				end,
				check = function(ctx)
					return ctx.count("total") == 0 and ctx.count("somme") >= 6
				end,
			},
			{
				title = "Curseurs en colonne",
				keys = {
					{ "Alt-↓ / Alt-↑", "curseur en dessous / au-dessus" },
					{ "<C-clic>", "ajouter un curseur à la souris" },
				},
				mission = "Ajoute « - » devant chaque fruit : `Alt-↓` trois fois, puis `I- ` et `Échap` deux fois.",
				setup = function(ctx)
					ctx.open("fruits.txt", { "pomme", "poire", "cerise", "fraise" })
				end,
				check = function(ctx)
					local l = ctx.tlines()
					for i = 1, 4 do
						if not (l[i] or ""):find("^%-") then
							return false
						end
					end
					return true
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "files",
		title = "Fichiers & projet",
		steps = {
			{
				title = "Trouver un fichier",
				text = "Le dossier du tutoriel contient un petit projet (src/, tests/, README…).",
				keys = {
					{ "<Space><Space>", "recherche intelligente" },
					{ "<Space>ff", "tous les fichiers" },
					{ "<C-p>", "idem (comme VS Code)" },
					{ "<Space>fr", "fichiers récents" },
					{ "<C-j>/<C-k>", "naviguer dans la liste" },
					{ "<C-v>", "ouvrir à côté (split)" },
				},
				mission = "Ouvre utils.lua : `<Space><Space>`, tape uti, puis Entrée.",
				setup = function(ctx)
					project(ctx)
					ctx.open("projet/src/main.lua")
				end,
				check = function(ctx)
					return vim.endswith(ctx.cur_name(), "utils.lua")
				end,
			},
			{
				title = "Chercher du texte dans le projet",
				keys = {
					{ "<Space>/", "chercher du texte (tout le projet)" },
					{ "<Space>sw", "le mot sous le curseur" },
					{ "<Space>sb", "les lignes du fichier courant" },
					{ "<Space>sR", "reprendre la dernière recherche" },
				},
				mission = "Un seul fichier contient le mot licorne. Trouve-le avec `<Space>/`, tape licorne, Entrée.",
				setup = function(ctx)
					project(ctx)
					ctx.open("projet/src/main.lua")
				end,
				check = function(ctx)
					return vim.endswith(ctx.cur_name(), "notes.txt")
				end,
			},
			{
				title = "L'explorateur de fichiers",
				keys = {
					{ "<Space>e", "ouvrir / fermer l'explorateur" },
					{ "Entrée", "ouvrir / déplier" },
					{ "a", "créer (finir par / = dossier)" },
					{ "d / r", "supprimer / renommer" },
					{ "c / m", "copier / déplacer" },
					{ "H", "afficher les fichiers cachés" },
					{ "?", "aide de l'explorateur" },
				},
				mission = "Ouvre l'explorateur avec `<Space>e`, puis ouvre README.md avec Entrée.",
				setup = function(ctx)
					project(ctx)
					ctx.open("projet/src/main.lua")
				end,
				check = function(ctx)
					local ok, open = pcall(function()
						return #Snacks.picker.get({ source = "explorer" }) > 0
					end)
					if ok and open then
						ctx.state.explorer = true
					end
					return ctx.state.explorer and ctx.visible("README.md")
				end,
			},
			{
				title = "Les onglets",
				text = "Chaque fichier ouvert apparaît en haut, comme les onglets d'un IDE.",
				keys = {
					{ "Shift-h / Shift-l", "onglet précédent / suivant" },
					{ "<Space>,", "liste des fichiers ouverts" },
					{ "<Space>bd", "fermer l'onglet" },
					{ "<Space>bo", "fermer tous les autres" },
					{ "<Space>bp", "épingler" },
					{ "<Space>bj", "choisir un onglet par lettre" },
				},
				mission = "Va sur notes.txt avec `Shift-l` / `Shift-h`, puis ferme-le avec `<Space>bd`.",
				setup = function(ctx)
					project(ctx)
					ctx.badd("projet/src/utils.lua")
					ctx.badd("projet/notes.txt")
					ctx.badd("projet/README.md")
					ctx.open("projet/src/main.lua")
				end,
				check = function(ctx)
					local b = vim.fn.bufnr(ctx.path("projet/notes.txt"))
					return b == -1 or vim.fn.buflisted(b) == 0
				end,
			},
			{
				title = "Autres outils fichiers",
				keys = {
					{ "<Space>fn", "nouveau fichier" },
					{ "<Space>fR", "renommer le fichier" },
					{ "<Space>fp", "projets récents" },
					{ "<Space>fc", "fichiers de config de l'IDE" },
					{ "<Space>gs", "fichiers modifiés (git)" },
				},
				setup = function(ctx)
					project(ctx)
					ctx.open("projet/src/main.lua")
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "win",
		title = "Fenêtres & terminal",
		steps = {
			{
				title = "Découper l'écran",
				keys = {
					{ "<Space>wv", "découper verticalement" },
					{ "<Space>ws", "découper horizontalement" },
					{ "<C-h/j/k/l>", "aller à gauche / bas / haut / droite" },
					{ "<C-flèches>", "redimensionner" },
					{ "<Space>w=", "égaliser les tailles" },
				},
				mission = "Découpe deux fois (`<Space>wv` puis `<Space>ws`) pour avoir 3 fenêtres à droite.",
				setup = function(ctx)
					ctx.open("fenetres.txt", { "Découpe-moi !" })
				end,
				check = function(ctx)
					return #ctx.wins() >= 3
				end,
			},
			{
				title = "Zoom et fermeture",
				keys = {
					{ "<Space>wm", "agrandir / restaurer (zoom)" },
					{ "<Space>wd", "fermer la fenêtre" },
					{ "<Space>wo", "ne garder que celle-ci" },
				},
				hint = "Si tu fermes ce panneau par erreur, il revient tout seul.",
				mission = "Zoome avec `<Space>wm` (et encore pour revenir), puis ferme les fenêtres en trop avec `<Space>wd` jusqu'à n'en avoir qu'une à droite.",
				setup = function(ctx)
					ctx.open("fenetres.txt", { "Zoome-moi !" })
				end,
				check = function(ctx)
					return ctx.typed("<Space>wm") and #ctx.wins() == 1
				end,
			},
			{
				title = "Le terminal intégré",
				text = {
					"`<C-/>` ouvre un terminal en bas et le cache. Il garde sa session : les commandes continuent en arrière-plan.",
					"Sur un clavier AZERTY, si `<C-/>` est difficile, utilise `<Space>tt`.",
				},
				keys = {
					{ "<C-/>", "ouvrir / cacher le terminal" },
					{ "<Space>tt", "terminal en bas" },
					{ "<Space>tf", "terminal flottant" },
					{ "<C-q>", "terminal → mode Normal (copier, défiler)" },
					{ "i", "revenir à la saisie" },
				},
				mission = "Ouvre le terminal, tape ls puis Entrée, puis cache-le (`<C-/>`, ou `<C-q>` puis `<Space>tt`).",
				setup = function(ctx)
					ctx.open("fenetres.txt", { "Le terminal s'ouvre en bas." })
				end,
				check = function(ctx)
					if ctx.seen("snacks_terminal") then
						ctx.state.opened = true
					end
					return ctx.state.opened and not ctx.visible_ft("snacks_terminal")
				end,
			},
			{
				title = "Espaces de travail (tabs)",
				text = "Un « espace » (tab Vim) est un ensemble de fenêtres. Ce tutoriel tourne dans son propre espace : tes fichiers à toi restent dans l'autre.",
				keys = {
					{ "<Space><Tab><Tab>", "nouvel espace" },
					{ "<Space><Tab>]", "espace suivant" },
					{ "<Space><Tab>[", "espace précédent" },
					{ "<Space><Tab>d", "fermer l'espace" },
				},
			},
			{
				title = "Le mode IDE",
				text = {
					"`<Space>uI` ouvre tous les panneaux d'un coup, comme dans VS Code : l'explorateur à gauche, le plan du fichier à droite, le terminal en bas. Le même raccourci les referme.",
					"Chaque panneau garde toujours sa place, même ouvert séparément (`<Space>e`, `<Space>co`, `<Space>xx`…).",
				},
				keys = {
					{ "<Space>uI", "mode IDE (ouvrir / fermer)" },
				},
				mission = "Ouvre le mode IDE avec `<Space>uI`, regarde, puis referme tout avec `<Space>uI`.",
				setup = function(ctx)
					close_panels()
					lsp_file(ctx)
				end,
				check = function(ctx)
					-- explorateur ou plan : l'un des deux suffit (le plan peut attendre le LSP)
					if ctx.typed("<Space>uI") and (ctx.seen("aerial") or ctx.seen("snacks_picker_list")) then
						ctx.state.opened = true
					end
					return ctx.state.opened
						and ctx.typed_count("<Space>uI") >= 2
						and not ctx.visible_ft("aerial")
						and not ctx.visible_ft("snacks_picker_list")
				end,
			},
			{
				title = "Se déplacer entre les panneaux",
				text = {
					"`<C-h/j/k/l>` marchent aussi pour entrer dans un panneau, et `<Space>uE` propose la liste des panneaux ouverts.",
					"Dans un panneau, `]w` / `[w` passent au suivant / précédent et `q` le ferme.",
					"Depuis le terminal : `nide mon-dossier` se place dans ce dossier et ouvre l'écran d'accueil ; `<Space>uI` affiche ensuite les panneaux.",
				},
				keys = {
					{ "<Space>uE", "choisir un panneau où aller" },
					{ "]w / [w", "panneau suivant / précédent" },
					{ "q", "fermer le panneau" },
				},
				setup = function(ctx)
					lsp_file(ctx)
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "lsp",
		title = "Intelligence du code (LSP)",
		steps = {
			{
				title = "Documentation au survol",
				text = {
					"Le serveur de langage (LSP) comprend ton code : types, définitions, erreurs… Il démarre tout seul (son nom s'affiche en bas à droite).",
					"Installés : Lua, Python, C/C++, Rust, JS/TS, Bash, JSON, YAML, HTML, CSS, Markdown, TOML, LaTeX, Docker, SQL (et Go si go est installé).",
				},
				keys = {
					{ "K", "documentation (K deux fois : y entrer)" },
					{ "gK", "signature de la fonction" },
				},
				hint = "Si rien ne s'affiche, attends 2-3 secondes que lua_ls démarre.",
				mission = "Le curseur est sur aire : appuie sur `K`.",
				setup = function(ctx)
					lsp_file(ctx, "aire(l, h)")
				end,
				check = function(ctx)
					return ctx.typed("K") and ctx.has_float()
				end,
			},
			{
				title = "Aller à la définition",
				keys = {
					{ "gd", "aller à la définition" },
					{ "gD", "aller à la déclaration" },
					{ "gy", "définition du type" },
					{ "gI", "implémentations" },
					{ "<C-o>", "revenir en arrière" },
					{ "<C-i>", "repartir en avant" },
				},
				mission = "Appuie sur `gd` pour sauter à la définition de aire, puis `<C-o>` pour revenir.",
				setup = function(ctx)
					lsp_file(ctx, "aire(l, h)")
				end,
				check = function(ctx)
					local def = ctx.find("local function aire")
					if def and ctx.row() == def[1] then
						ctx.state.def = true
					end
					return ctx.state.def and def and ctx.row() ~= def[1] and ctx.typed("<C-o>")
				end,
			},
			{
				title = "Trouver les références",
				keys = {
					{ "gr", "toutes les références" },
					{ "]] / [[", "occurrence suivante / précédente" },
					{ "<Space>cR", "références dans un panneau" },
				},
				mission = "Sur perimetre, appuie sur `gr` : la liste montre toutes ses utilisations.",
				setup = function(ctx)
					lsp_file(ctx, "perimetre")
				end,
				check = function(ctx)
					return ctx.typed("gr")
				end,
			},
			{
				title = "Renommer partout",
				keys = {
					{ "<Space>cr", "renommer le symbole" },
					{ "F2", "idem (comme VS Code)" },
				},
				mission = "Renomme aire en surface avec `<Space>cr` (ou `F2`) : tape surface puis Entrée. Tous les appels suivent.",
				setup = function(ctx)
					lsp_file(ctx, "aire(largeur") -- curseur sur le nom de la fonction
				end,
				check = function(ctx)
					return ctx.has("function surface(") and ctx.has("= surface(")
						and not ctx.has("function aire(") and not ctx.has("= aire(")
				end,
			},
			{
				title = "Erreurs et corrections",
				keys = {
					{ "]d / [d", "diagnostic suivant / précédent" },
					{ "]e / [e", "erreur suivante / précédente" },
					{ "<Space>cd", "lire le diagnostic de la ligne" },
					{ "<Space>ca", "actions de code (corrections)" },
					{ "<Space>sd", "chercher dans les diagnostics" },
				},
				mission = "lua_ls souligne prnt (faute de frappe). Va dessus avec `]d`, lis avec `<Space>cd`, puis corrige en print.",
				setup = function(ctx)
					ctx.open("diag.lua", DIAG_CODE)
				end,
				check = function(ctx)
					return ctx.has("print(\"bonjour") and not ctx.has("prnt(")
				end,
			},
			{
				title = "Le panneau des problèmes",
				keys = {
					{ "<Space>xx", "problèmes du projet" },
					{ "<Space>xX", "problèmes du fichier" },
					{ "Entrée / q", "y aller / fermer (dans le panneau)" },
				},
				mission = "Ouvre le panneau avec `<Space>xx`, regarde, puis ferme-le avec `q`.",
				setup = function(ctx)
					ctx.open("diag.lua", DIAG_CODE)
				end,
				check = function(ctx)
					return ctx.seen("trouble")
				end,
			},
			{
				title = "Le plan du fichier",
				keys = {
					{ "<Space>co", "plan (outline) à droite" },
					{ "<Space>ss", "chercher un symbole du fichier" },
					{ "<Space>sS", "chercher un symbole du projet" },
					{ "<Space>cb", "fil d'Ariane (en haut)" },
					{ "[u", "remonter au début du bloc" },
				},
				mission = "Ouvre le plan avec `<Space>co`, puis referme-le (même raccourci).",
				setup = function(ctx)
					lsp_file(ctx)
				end,
				check = function(ctx)
					return ctx.seen("aerial")
				end,
			},
			{
				title = "Bonus code",
				keys = {
					{ "<Space>cf", "formater (auto à la sauvegarde)" },
					{ "<Space>uf", "formatage auto on/off" },
					{ "<Space>uh", "indices de type (inlay hints)" },
					{ "<Space>cm", "Mason : installer d'autres langages" },
					{ "<Space>ci", "infos sur le LSP" },
				},
			},
		},
	},

	-- =======================================================================
	{
		id = "cmp",
		title = "Complétion & snippets",
		steps = {
			{
				title = "L'autocomplétion",
				text = "Le menu apparaît tout seul pendant la frappe. Le texte grisé montre ce qui sera inséré.",
				keys = {
					{ "Tab / S-Tab", "suivant / précédent" },
					{ "Entrée", "valider" },
					{ "<C-Space>", "ouvrir le menu" },
					{ "<C-e>", "fermer le menu" },
					{ "<C-b>/<C-f>", "défiler la documentation" },
				},
				mission = "Ligne 2 : passe en insertion (`i`), tape  local maj = mot:up  puis choisis upper (`Tab`) et valide (Entrée).",
				setup = function(ctx)
					ctx.open("completion.lua", { "local mot = \"bonjour\"", "", "return mot" }, { cursor = { 2, 0 } })
				end,
				check = function(ctx)
					return ctx.has("mot:upper")
				end,
			},
			{
				title = "Les snippets",
				text = "Les snippets sont des modèles de code. Une fois insérés, `Tab` saute au champ suivant.",
				mission = "En insertion, tape fun et choisis le snippet function (Entrée). Remplis le nom, puis `Tab` pour passer à la suite.",
				setup = function(ctx)
					ctx.open("snippets.lua", { "", "" })
				end,
				check = function(ctx)
					return ctx.has("function") and ctx.has("end")
				end,
			},
			{
				title = "Dans la ligne de commande",
				text = "La complétion marche aussi après `:`. Essaie : `:Laz` puis `Tab`.",
				keys = {
					{ "<Space>:", "historique des commandes" },
					{ "<Space>sc", "liste de toutes les commandes" },
				},
			},
		},
	},

	-- =======================================================================
	{
		id = "search",
		title = "Rechercher & remplacer",
		steps = {
			{
				title = "Le mot sous le curseur",
				keys = {
					{ "*", "occurrence suivante du mot" },
					{ "#", "occurrence précédente" },
					{ "n / N", "suivante / précédente" },
				},
				mission = "Le curseur est sur chat. Appuie sur `*` puis `n` pour aller au chat de la ligne 4.",
				setup = function(ctx)
					ctx.open("chats.txt", { "Le chat dort.", "Un chien aboie.", "Le chat mange.", "Encore un chat ici.", "Fin." }, { at = "chat" })
				end,
				check = function(ctx)
					return ctx.row() == 4 and ctx.word() == "chat"
				end,
			},
			{
				title = "Remplacer dans le fichier",
				text = "Pendant que tu tapes la commande, un aperçu montre le résultat en direct.",
				keys = {
					{ ":%s/a/b/g", "remplacer partout" },
					{ ":%s/a/b/gc", "avec confirmation (y/n/a/q)" },
					{ ":s/a/b/g", "dans la sélection (visuel)" },
				},
				mission = "Remplace tous les chat par lapin : `:%s/chat/lapin/g` puis Entrée.",
				setup = function(ctx)
					ctx.open("chats.txt", { "Le chat dort.", "Un chien aboie.", "Le chat mange.", "Encore un chat ici.", "Fin." })
				end,
				check = function(ctx)
					return ctx.count("chat") == 0 and ctx.count("lapin") == 3
				end,
			},
			{
				title = "Remplacer dans tout le projet",
				text = "grug-far : un champ chercher, un champ remplacer, des filtres de fichiers, et l'aperçu de chaque changement.",
				keys = {
					{ "<Space>sr", "chercher / remplacer (projet)" },
					{ "<Space>sW", "avec le mot sous le curseur" },
					{ "\\r", "appliquer (dans grug-far)" },
					{ "g?", "aide de grug-far" },
				},
				mission = "Ouvre-le avec `<Space>sr`, tape bonjour dans Search pour voir les résultats, puis `q` pour fermer.",
				setup = function(ctx)
					project(ctx)
					ctx.open("projet/src/main.lua")
				end,
				check = function(ctx)
					return ctx.seen("grug-far")
				end,
			},
			{
				title = "TODO, FIXME et compagnie",
				text = "Les commentaires TODO, FIXME, HACK, NOTE… sont colorés et listables.",
				keys = {
					{ "]t / [t", "TODO suivant / précédent" },
					{ "<Space>st", "tous les TODO du projet" },
				},
				mission = "Saute au FIXME avec `]t` (deux fois).",
				setup = function(ctx)
					ctx.open("todo.lua", {
						"local x = 1",
						"-- TODO: gérer le cas négatif",
						"local y = 2",
						"-- FIXME: ce calcul est faux",
						"local z = x + y",
						"-- NOTE: rien d'urgent",
						"return z",
					})
				end,
				check = function(ctx)
					return ctx.row() == 4
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "git",
		title = "Git",
		steps = {
			{
				title = "Les signes dans la marge",
				text = {
					"Un dépôt git de démonstration vient d'être créé, et le fichier a été modifié depuis le dernier commit.",
					"Dans la marge : barre verte = ajout, orange = modification, rouge = suppression.",
				},
				keys = {
					{ "]h / [h", "bloc modifié suivant / précédent" },
					{ "<Space>gb", "qui a écrit cette ligne (blame)" },
					{ "<Space>ub", "blame en continu (on/off)" },
				},
				mission = "Va sur le 2e bloc modifié avec `]h` (deux fois depuis le haut).",
				setup = git_repo,
				check = function(ctx)
					local h = git_hunks(ctx)[2]
					if not h then
						return false
					end
					local start = h.added.start
					local stop = start + math.max(h.added.count, 1) - 1
					local row = ctx.row()
					return row >= start and row <= stop
				end,
			},
			{
				title = "Voir et annuler un bloc",
				keys = {
					{ "<Space>ghp", "aperçu de l'ancien contenu" },
					{ "<Space>ghr", "annuler le bloc" },
					{ "<Space>ghR", "annuler tout le fichier" },
				},
				mission = "Va sur un bloc (`]h`) et affiche l'ancien contenu avec `<Space>ghp`.",
				setup = git_repo,
				check = function(ctx)
					return ctx.typed("<Space>ghp")
				end,
			},
			{
				title = "Préparer un commit (stager)",
				keys = {
					{ "<Space>ghs", "stager le bloc (ou la sélection)" },
					{ "<Space>ghS", "stager tout le fichier" },
					{ "<Space>gs", "fichiers modifiés" },
				},
				mission = "Stage un bloc avec `<Space>ghs`.",
				setup = git_repo,
				check = function(ctx)
					local now = vim.uv.now()
					if ctx.state.t and now - ctx.state.t < 1000 then
						return false
					end
					ctx.state.t = now
					local _, code = ctx.sh({ "git", "-C", ctx.path("git-demo"), "diff", "--cached", "--quiet" })
					return code == 1
				end,
			},
			{
				title = "Lazygit",
				text = "Lazygit est une interface git complète : stager, committer, pousser, branches, historique, conflits…",
				keys = {
					{ "<Space>gg", "ouvrir lazygit" },
					{ "Espace", "stager (dans lazygit)" },
					{ "c", "committer" },
					{ "P / p", "pousser / tirer" },
					{ "?", "aide" },
					{ "q", "quitter lazygit" },
				},
				mission = "Ouvre lazygit avec `<Space>gg`, fais un commit si tu veux (Espace puis c), et quitte avec `q`.",
				setup = git_repo,
				check = function(ctx)
					return ctx.typed("<Space>gg")
				end,
			},
			{
				title = "Comparer et historique",
				keys = {
					{ "<Space>gd", "diff de tout le projet" },
					{ "<Space>gD", "fermer le diff" },
					{ "<Space>gH", "historique du fichier (diff)" },
					{ "<Space>gl", "historique (log)" },
					{ "<Space>gf", "commits du fichier" },
					{ "<Space>gB", "ouvrir sur GitHub / GitLab" },
				},
			},
		},
	},

	-- =======================================================================
	{
		id = "run",
		title = "Exécuter et compiler",
		steps = {
			{
				title = "Lancer le fichier",
				text = {
					"`F6` sauvegarde et lance le fichier courant dans un terminal en bas, comme le bouton ▶ de VS Code.",
					"Python (avec le .venv du projet s'il y en a un), C et C++ (compilés avec gcc), Rust, Lua, JS/TS, shell, Go.",
					"Le programme peut lire au clavier (input, scanf…). À la fin, `q` ferme la sortie.",
				},
				keys = {
					{ "F6", "lancer le fichier" },
					{ "<Space>r", "idem" },
					{ "<Space>R", "lancer avec des arguments" },
					{ ":Run args", "idem, en commande" },
					{ "<Space>or", "revoir la sortie du dernier F6" },
				},
				mission = "Lance ce programme Python avec `F6` (ou `<Space>r`), lis la sortie, puis ferme-la avec `q`.",
				setup = function(ctx)
					hide_terminals()
					ctx.open("lancer.py", RUN_PY)
				end,
				check = function(ctx)
					if (ctx.typed("<F6>") or ctx.typed("<Space>r")) and ctx.seen("snacks_terminal") then
						ctx.state.ran = true
					end
					return ctx.state.ran and not ctx.visible_ft("snacks_terminal")
				end,
			},
			{
				title = "Une erreur de compilation",
				text = {
					"Pour le C, `F6` compile d'abord (gcc -Wall -g). S'il y a des erreurs, rien n'est lancé : le panneau Problèmes s'ouvre avec la liste, fichier et ligne.",
					"`Entrée` sur une erreur y emmène le curseur. Une fois corrigé, `F6` recompile et lance.",
				},
				keys = {
					{ "Entrée", "aller à l'erreur (dans le panneau)" },
					{ "]q / [q", "erreur suivante / précédente" },
					{ "<Space>oq", "rouvrir la liste des erreurs" },
					{ "q", "fermer le panneau" },
				},
				hint = "Le soulignement rouge de clangd montre déjà l'erreur, avant même de compiler.",
				mission = {
					"Appuie sur `F6` : la compilation échoue (il manque un ;).",
					"Va sur l'erreur, ajoute le ; puis relance avec `F6` jusqu'à voir la somme.",
				},
				setup = function(ctx)
					hide_terminals()
					vim.fn.setqflist({}, " ", { title = "Tutoriel" }) -- repart d'une liste vide
					ctx.open("erreur.c", RUN_C, { at = "total += carre" })
				end,
				check = function(ctx)
					local n = compile_errors("erreur.c")
					if n and n > 0 then
						ctx.state.failed = true
					end
					return ctx.state.failed and n == 0
				end,
			},
			{
				title = "Les tâches du projet",
				text = {
					"Pour un vrai projet (make, cargo, npm, just…), les tâches se lancent avec `<Space>o`. Elles tournent en arrière-plan, la sortie s'affiche en bas et les erreurs vont dans le panneau Problèmes.",
					"Ici, un petit projet avec un Makefile. `<Space>ob` propose la commande de compilation (Entrée pour lancer) : c'est `<Space>k`, vu au chapitre suivant.",
				},
				keys = {
					{ "<Space>ob", "compiler le projet (= <Space>k)" },
					{ "<Space>oo", "choisir une tâche à lancer" },
					{ "<Space>ol", "relancer la dernière tâche" },
					{ "<Space>ot", "panneau des tâches" },
					{ "<Space>os", "commande shell en tâche" },
					{ "<Space>oa", "action sur une tâche (arrêter…)" },
					{ "<Space>oq", "erreurs de compilation" },
				},
				mission = "Compile le projet avec `<Space>ob` (ou `<Space>oo` puis make), puis ouvre le panneau des tâches avec `<Space>ot`.",
				setup = function(ctx)
					hide_terminals()
					make_project(ctx)
				end,
				check = function(ctx)
					if vim.uv.fs_stat(ctx.path("taches/bonjour")) then
						ctx.state.built = true
					end
					return ctx.state.built and (ctx.typed("<Space>ot") or ctx.seen("OverseerList"))
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "compile",
		title = "Compiler le projet",
		steps = {
			{
				title = "Compiler avec Espace k",
				text = {
					"`<Space>k` compile le projet entier, comme « M-x compile » d'Emacs. nide détecte le système de build le plus proche (make, cargo, cmake, just, npm, latexmk…) et pré-remplit la commande : `Entrée` pour la lancer, ou modifie-la avant.",
					"La commande est retenue pour ce projet ; `↑` / `↓` dans la saisie parcourent l'historique.",
					"La sortie s'affiche en bas, et chaque erreur devient un diagnostic souligné dans le fichier concerné, même s'il n'est pas ouvert.",
				},
				keys = {
					{ "<Space>k", "compiler (commande modifiable)" },
					{ "]e / [e", "erreur suivante / précédente" },
					{ "<Space>ko", "afficher / cacher la sortie" },
					{ "<Space>xx", "panneau Problèmes" },
				},
				mission = {
					"Lance `<Space>k` puis `Entrée` (make -k) : stats.c ne compile pas.",
					"Va sur l'erreur avec `]e`.",
				},
				hint = "Entrée sur une ligne d'erreur de la sortie y emmène aussi.",
				setup = function(ctx)
					hide_terminals()
					compil_project(ctx, true)
					local c = compile_mod()
					ctx.state.prev = c and c.result
					ctx.open("compil/stats.c")
				end,
				check = function(ctx)
					local c = compile_mod()
					if compiled_here(c) and c.result ~= ctx.state.prev and c.result.errors > 0 then
						ctx.state.failed = true
					end
					return ctx.state.failed and ctx.typed("]e") and ctx.row() == 8
				end,
			},
			{
				title = "Corriger et recompiler",
				text = {
					"`<Space>K` relance la dernière compilation sans rien demander. Tout est enregistré avant de compiler.",
					"`F6` reste là pour lancer un fichier seul ; dans un projet dont le Makefile a une cible run, `F6` fait `make run`.",
				},
				keys = {
					{ "<Space>K", "recompiler (sans question)" },
					{ ":Compile cmd", "compiler avec cette commande" },
					{ "<Space>kc", "arrêter la compilation" },
				},
				mission = {
					"Déclare la variable : écris double devant resultat ligne 8.",
					"Recompile avec `<Space>K` jusqu'à « ✓ Compilé ».",
				},
				setup = function(ctx)
					hide_terminals()
					compil_project(ctx, false)
					local c = compile_mod()
					ctx.state.prev = c and c.result
					ctx.open("compil/stats.c", nil, { at = "resultat =" })
				end,
				check = function(ctx)
					local c = compile_mod()
					return compiled_here(c) and c.result ~= ctx.state.prev and c.result.ok
						and vim.uv.fs_stat(ctx.path("compil/moyenne")) ~= nil
				end,
			},
			{
				title = "Surveillance et cibles",
				text = {
					"Le mode surveillance recompile en silence à chaque enregistrement d'un fichier du projet : les erreurs apparaissent dans le code dès que tu sauves. L'état s'affiche dans la barre du bas.",
					"`<Space>kt` liste les cibles du projet (cibles du Makefile, binaires cargo, scripts npm…).",
				},
				keys = {
					{ "<Space>kw", "surveillance on / off" },
					{ "<Space>kt", "choisir une cible" },
					{ "<Space>kh", "historique des commandes" },
					{ "<Space>kc", "arrêter" },
					{ "<Space>ob", "même chose que <Space>k" },
				},
				hint = "Essaie `<Space>kw`, casse le code, `:w` : l'erreur revient toute seule. `<Space>kw` à nouveau pour arrêter.",
				setup = function(ctx)
					compil_project(ctx, false)
					ctx.open("compil/stats.c")
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "debug",
		title = "Débogueur & tests",
		steps = {
			{
				title = "Point d'arrêt",
				module = "python",
				text = "Le débogueur marche sans configuration pour Python (debugpy, avec le .venv du projet), C, C++ et Rust (codelldb), et Go (delve) si go est installé. Les touches F sont celles de VS Code.",
				keys = {
					{ "F9", "point d'arrêt (on/off)" },
					{ "<Space>db", "idem" },
					{ "<Space>dB", "point d'arrêt conditionnel" },
				},
				mission = "Pose un point d'arrêt sur la ligne total += x avec `F9` (ou `<Space>db`).",
				setup = function(ctx)
					ctx.open("debug.py", DEBUG_PY, { at = "total += x" })
				end,
				check = function(ctx)
					return breakpoints(ctx) > 0
				end,
			},
			{
				title = "Lancer et avancer",
				module = "python",
				keys = {
					{ "F5", "lancer / continuer" },
					{ "F10", "ligne suivante" },
					{ "F11", "entrer dans la fonction" },
					{ "Shift-F11", "sortir de la fonction" },
					{ "<Space>du", "interface (variables, pile…)" },
					{ "<Space>de", "évaluer l'expression" },
					{ "<Space>dt", "arrêter" },
				},
				mission = "Lance avec `F5`. Ça s'arrête sur le point d'arrêt : avance avec `F10`, puis `<Space>dt` pour arrêter.",
				setup = function(ctx)
					local buf = ctx.open("debug.py", DEBUG_PY, { at = "total += x" })
					if buf and breakpoints(ctx) == 0 then
						pcall(function()
							local pos = ctx.find("total += x")
							require("dap.breakpoints").set({}, buf, pos[1])
						end)
					end
				end,
				check = function(ctx)
					return ctx.typed("<F5>") or ctx.typed("<Space>dc")
				end,
			},
			{
				title = "Les tests",
				text = "neotest lance les tests (pytest pour Python, cargo test pour Rust, go test pour Go) et affiche ✓ / ✗ dans la marge.",
				keys = {
					{ "<Space>tr", "lancer le test sous le curseur" },
					{ "<Space>tF", "tests du fichier" },
					{ "<Space>tA", "tous les tests" },
					{ "<Space>ts", "panneau des tests" },
					{ "<Space>to", "sortie du test" },
					{ "<Space>td", "déboguer le test" },
				},
			},
			{
				title = "F5 sur un programme C",
				module = "c",
				text = {
					"Pas de launch.json à écrire : sur un fichier C ou C++, `F5` compile avec -g puis lance codelldb. Avec un Makefile, nide propose make (`<Space>dM` oublie ce choix) ; un projet Rust passe par cargo build.",
					"Arrêté sur un point d'arrêt, les variables s'affichent dans le panneau de gauche et en gris dans le code.",
				},
				keys = {
					{ "F5", "compiler + déboguer / continuer" },
					{ "F10", "ligne suivante" },
					{ "<Space>de", "valeur sous le curseur" },
					{ "<Space>dA", "déboguer avec des arguments" },
					{ "<Space>dl", "relancer la dernière session" },
					{ "<Space>dt", "arrêter" },
				},
				mission = {
					"Pose un point d'arrêt (`F9`) sur resultat *= i;, lance `F5`.",
					"Arrêté : avance de deux lignes avec `F10`, puis curseur sur resultat et `<Space>de` pour voir sa valeur.",
				},
				hint = "La première fois, codelldb met quelques secondes à démarrer.",
				setup = function(ctx)
					dap_reset()
					ctx.open("debug.c", DEBUG_C, { at = "resultat *= i" })
				end,
				check = function(ctx)
					local s = dap_session()
					if not ctx.state.f10 and s and s.stopped_thread_id then
						-- arrêté : on compte les F10 et Espace d e tapés à partir de maintenant
						ctx.state.f10 = ctx.typed_count("<F10>")
						ctx.state.eval = ctx.typed_count("<Space>de")
					end
					return ctx.state.f10 ~= nil
						and ctx.typed_count("<F10>") >= ctx.state.f10 + 2
						and ctx.typed_count("<Space>de") > ctx.state.eval
				end,
			},
			{
				title = "Taper l'entrée (scanf)",
				module = "c",
				text = {
					"Le programme tourne dans la console du débogueur (en bas) : c'est là qu'il lit le clavier (scanf, input…). `<Space>dT` y place le curseur en mode insertion.",
					"À la fin, l'interface reste ouverte pour lire la sortie, et une notification donne le code de sortie. `q` dans le débogueur (ou `<Space>du`) la ferme.",
				},
				keys = {
					{ "<Space>dT", "aller dans la console (saisie)" },
					{ "Ctrl-q", "console → mode normal" },
					{ "q / <Space>du", "fermer le débogueur" },
				},
				mission = {
					"Lance `F5` : le programme attend un nombre.",
					"`<Space>dT`, tape 21 puis `Entrée`, lis la réponse, puis ferme le débogueur (`<Space>du`).",
				},
				setup = function(ctx)
					dap_reset()
					console_clear("Le double de %-?%d+ est")
					ctx.open("lire.c", DEBUG_SCANF, { at = "scanf" })
				end,
				check = function(ctx)
					-- une session a démarré depuis le début de l'étape (la console d'avant ne compte pas)
					if dap_session() then
						ctx.state.started = true
					end
					if ctx.state.started and console_has("Le double de %-?%d+ est") then
						ctx.state.read = true
					end
					return ctx.state.read and not dapui_visible(ctx)
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "notebook",
		title = "Notebooks Jupyter & Markdown",
		steps = {
			{
				title = "Un notebook, comme dans VS Code",
				module = "notebook",
				text = "Un .ipynb s'ouvre comme un document : le texte est mis en forme, chaque cellule de code est un bloc ```python. Le kernel Python démarre tout seul (celui du .venv du projet s'il existe, sinon un Python avec numpy, matplotlib, pandas, scipy). Les sorties et les graphiques s'affichent sous la cellule, et :w les enregistre dans le .ipynb.",
				keys = {
					{ "]j", "cellule suivante" },
					{ "[j", "cellule précédente" },
					{ "<Space>jN", "nouveau notebook" },
				},
				mission = "Va dans la deuxième cellule de code avec `]j` (deux fois).",
				setup = function(ctx)
					ctx.open("notebook.ipynb", NOTEBOOK, { cursor = { 1, 0 } }) -- repart d'un notebook neuf
				end,
				check = function(ctx)
					local c = notebook_cells(ctx)
					local row = ctx.row()
					return c[2] ~= nil and row > c[2].start and row < c[2].stop
				end,
			},
			{
				title = "Exécuter une cellule",
				module = "notebook",
				text = "Les mêmes touches que VS Code, en mode normal comme en insertion. La première exécution peut prendre une seconde, le temps que le kernel démarre.",
				keys = {
					{ "<C-CR>", "exécuter la cellule (Ctrl+Entrée)" },
					{ "<S-CR>", "exécuter et passer à la suivante (Maj+Entrée)" },
					{ "<M-CR>", "exécuter et insérer une cellule (Alt+Entrée)" },
					{ "<Space>jj", "exécuter la cellule (si ton terminal ne passe pas Ctrl+Entrée)" },
				},
				mission = "Le curseur est dans la première cellule : exécute-la avec `Ctrl+Entrée` (ou `<Space>jj`). Le résultat apparaît en dessous.",
				setup = function(ctx)
					notebook_open(ctx, "a = 6 * 7")
				end,
				check = function(ctx)
					return notebook_ran(ctx) > 0
				end,
			},
			{
				title = "Exécuter et avancer",
				module = "notebook",
				text = "Maj+Entrée exécute la cellule et descend à la suivante : on enchaîne tout le notebook comme ça. La deuxième cellule trace un graphique (affiché dans kitty).",
				keys = {
					{ "<S-CR>", "exécuter → suivante" },
					{ "<Space>jn", "idem" },
					{ "<Space>ja", "tout exécuter" },
					{ "<Space>jA", "exécuter jusqu'ici" },
				},
				mission = "Exécute les deux autres cellules avec `Maj+Entrée` (ou `<Space>ja` pour tout exécuter).",
				check = function(ctx)
					return notebook_ran(ctx) >= 3
				end,
			},
			{
				title = "Ajouter des cellules",
				module = "notebook",
				keys = {
					{ "<Space>jb", "nouvelle cellule de code dessous" },
					{ "<Space>jB", "nouvelle cellule de code dessus" },
					{ "<Space>jm", "nouveau texte (Markdown) dessous" },
					{ "<Space>jd", "supprimer la cellule" },
					{ "<M-CR>", "exécuter + nouvelle cellule" },
				},
				text = "Le texte entre deux cellules de code est une cellule Markdown : écris-le simplement, avec # pour les titres.",
				mission = "Ajoute une cellule de code sous la dernière avec `<Space>jb`, écris print(\"salut\") dedans et exécute-la.",
				setup = function(ctx)
					notebook_open(ctx, "a * 2")
				end,
				check = function(ctx)
					return #notebook_cells(ctx) >= 4 and ctx.has('print("salut")') and notebook_ran(ctx) >= 1
				end,
			},
			{
				title = "Gérer les sorties et le kernel",
				module = "notebook",
				text = "Les sorties longues sont coupées : entre dedans pour les faire défiler. :w réécrit le .ipynb avec les sorties, tu peux le rouvrir dans VS Code ou Jupyter.",
				keys = {
					{ "<Space>jo", "entrer dans la sortie (q pour sortir)" },
					{ "<Space>jc", "effacer la sortie de la cellule" },
					{ "<Space>jx", "interrompre un calcul trop long" },
					{ "<Space>jr", "redémarrer le kernel (oublie les variables)" },
					{ "<Space>jk", "choisir un autre kernel" },
					{ "<Space>jv", "exécuter la sélection (visuel)" },
				},
				mission = "Ouvre la sortie de la cellule sous le curseur avec `<Space>jo`, puis ressors avec `q`.",
				setup = function(ctx)
					notebook_open(ctx, "a = 6 * 7")
				end,
				check = function(ctx)
					return ctx.typed("<Space>jo")
				end,
			},
			{
				title = "Aperçu Markdown",
				text = "Deux façons de voir un .md : le rendu directement dans l'éditeur (titres, listes, tableaux) ou un vrai aperçu dans le navigateur, mis à jour pendant que tu tapes, qui suit le curseur, avec les maths et les diagrammes.",
				keys = {
					{ "<Space>mr", "rendu dans l'éditeur (on/off)" },
					{ "<Space>mp", "aperçu dans le navigateur (on/off)" },
				},
				mission = "Ouvre l'aperçu navigateur avec `<Space>mp`, tape du texte ici et regarde-le apparaître. `<Space>mp` encore pour fermer.",
				setup = function(ctx)
					ctx.open("apercu.md", {
						"# Aperçu Markdown",
						"",
						"Du **gras**, de l'*italique* et du `code`.",
						"",
						"| Langage | Extension |",
						"| ------- | --------- |",
						"| Python  | .py       |",
						"| C       | .c        |",
						"",
						"Une formule : $E = mc^2$",
						"",
						"```mermaid",
						"graph LR",
						"  A[Idée] --> B[Code] --> C[Bravo]",
						"```",
						"",
						"- [ ] tâche à faire",
						"- [x] tâche faite",
					}, { cursor = { 1, 0 } })
				end,
				check = function(ctx)
					return ctx.typed("<Space>mp")
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "outils",
		title = "Outils de nide",
		steps = {
			{
				title = "La palette de commandes",
				text = {
					"`<Space>P` ouvre la palette, comme Ctrl+Maj+P dans VS Code : toutes les actions de nide (avec leur raccourci), les commandes :Nide…, :Tuto, et celles de Neovim. Tape quelques lettres, `Entrée` exécute.",
					"Ctrl+Maj+P marche aussi si ton terminal la transmet (kitty la garde souvent pour lui).",
				},
				keys = {
					{ "<Space>P", "palette de commandes" },
					{ ":NidePalette", "idem, en commande" },
				},
				mission = "Ouvre la palette avec `<Space>P`, tape docteur et valide avec `Entrée`.",
				setup = function(ctx)
					close_doctor()
					ctx.open("outils.txt", { "La palette retrouve n'importe quelle action par son nom." })
				end,
				check = function(ctx)
					return ctx.typed("<Space>P") and ctx.seen("nidedoctor")
				end,
			},
			{
				title = "Le docteur",
				text = {
					"Le docteur fait le bilan de l'installation : outils indispensables, langages (exécuter, LSP, formateur, débogueur), notebooks, plugins. Chaque ✗ vient avec la commande pour corriger.",
					"La même chose au format de Neovim : :checkhealth nide.",
				},
				keys = {
					{ "<Space>cD", "docteur (:NideDoctor)" },
					{ "i", "installer via Mason (ligne)" },
					{ "y", "copier le correctif" },
					{ "r", "relancer le bilan" },
					{ "q", "fermer" },
				},
				mission = "Ouvre le docteur avec `<Space>cD` (ou :NideDoctor), parcours-le, puis ferme-le avec `q`.",
				setup = function(ctx)
					close_doctor()
					ctx.open("outils.txt", { "Le docteur dit ce qui manque, et comment l'installer." })
				end,
				check = function(ctx)
					if ctx.visible_ft("nidedoctor") then
						ctx.state.opened = true
					end
					return ctx.state.opened and not ctx.visible_ft("nidedoctor")
				end,
			},
			{
				title = "Nouveau projet",
				text = {
					":NideNew crée un projet prêt à compiler et à déboguer : C ou C++ (Makefile, src/, include/), Python (.venv), Rust (cargo), LaTeX, notebook. git init compris ; nide se place ensuite dans le dossier du projet.",
					"Aussi : `<Space>fN`, ou `N` sur l'écran d'accueil. En une ligne : :NideNew c nom [dossier].",
				},
				keys = {
					{ ":NideNew", "assistant nouveau projet" },
					{ "<Space>fN", "idem" },
				},
				mission = {
					"Lance :NideNew (ou `<Space>fN`), choisis C, nomme-le demo et garde le dossier proposé (celui des exercices).",
				},
				hint = "Ensuite `F6` lance make run, `F5` débogue, `<Space>k` compile.",
				setup = function(ctx)
					close_doctor()
					vim.fn.delete(ctx.path("demo"), "rf")
					ctx.cd()
					ctx.state.before = subdirs(ctx.dir)
					ctx.state.cwd = vim.fn.getcwd(-1, -1)
					ctx.open("outils.txt", { "Le nouveau projet sera créé ici, dans le dossier d'exercices." })
				end,
				check = function(ctx)
					local new
					for name in pairs(subdirs(ctx.dir)) do
						if not ctx.state.before[name] and vim.uv.fs_stat(ctx.path(name .. "/Makefile")) then
							new = name
						end
					end
					if not new then
						return false
					end
					-- :NideNew fait un :cd global : on rend son dossier à l'utilisateur,
					-- seul l'onglet du tutoriel va dans le projet
					if vim.fn.getcwd(-1, -1) ~= ctx.state.cwd then
						local win = ctx.win()
						if win then
							vim.api.nvim_win_call(win, function()
								vim.cmd("cd " .. vim.fn.fnameescape(ctx.state.cwd))
							end)
						end
					end
					ctx.cd(new)
					return true
				end,
			},
			{
				title = "Squelettes de fichiers",
				text = {
					"Un nouveau fichier main.c, .h, .py, .sh ou Makefile démarre avec un squelette : include, garde d'en-tête, shebang… Le curseur est placé là où tu écris.",
					"Dans un fichier vide existant : :NideSkeleton. Pour s'en passer : vim.g.nide_skeletons = false dans lua/core/options.lua.",
				},
				keys = {
					{ ":e nom.h", "nouveau fichier (squelette)" },
					{ ":NideSkeleton", "insérer le squelette" },
				},
				mission = "Crée un en-tête : :e calcul.h, regarde la garde #ifndef, puis enregistre avec :w.",
				setup = function(ctx)
					vim.fn.delete(ctx.path("calcul.h"))
					ctx.cd()
					ctx.open("outils.txt", { "Crée calcul.h ici avec :e calcul.h" })
				end,
				check = function(ctx)
					local ok, lines = pcall(vim.fn.readfile, ctx.path("calcul.h"))
					return ok and table.concat(lines, "\n"):find("#ifndef CALCUL_H", 1, true) ~= nil
				end,
			},
			{
				title = "L'intro animée",
				text = {
					"Au démarrage, nide joue une courte animation (une collision au LHC qui forme le logo) : images natives dans kitty, demi-blocs de couleur ailleurs. N'importe quelle touche la passe.",
					"Pour la couper : vim.g.nide_intro = false. Pour forcer le moteur : vim.g.nide_intro_mode = \"kitty\" ou \"blocks\".",
				},
				keys = {
					{ ":NideIntro", "rejouer l'intro" },
				},
				hint = "Essaie :NideIntro, puis une touche pour revenir.",
				setup = function(ctx)
					ctx.cd()
					ctx.open("outils.txt", { "Une touche passe l'intro." })
				end,
			},
		},
	},

	-- =======================================================================
	{
		id = "more",
		title = "Aller plus loin",
		steps = {
			{
				title = "Tous les raccourcis",
				text = "Tu n'as pas à tout retenir : tout est cherchable.",
				keys = {
					{ "<Space>", "menu (attends un instant)" },
					{ "<Space>sk", "chercher parmi TOUS les raccourcis" },
					{ "<Space>sK", "raccourcis de ce fichier" },
					{ "<Space>P", "palette de commandes" },
					{ "<Space>sh", "aide de Neovim" },
				},
				mission = "Ouvre la liste de tous les raccourcis avec `<Space>sk` et cherche terminal.",
				setup = function(ctx)
					ctx.open("fin.txt", { "Presque fini !" })
				end,
				check = function(ctx)
					return ctx.typed("<Space>sk")
				end,
			},
			{
				title = "Interrupteurs d'interface",
				text = "Tout ce qui commence par `<Space>u` active / désactive un élément de l'interface.",
				keys = {
					{ "<Space>uw", "retour à la ligne" },
					{ "<Space>ul / uL", "numéros / numéros relatifs" },
					{ "<Space>ud", "diagnostics" },
					{ "<Space>ug", "guides d'indentation" },
					{ "<Space>uz", "mode zen" },
					{ "<Space>uC", "changer de thème" },
					{ "<Space>us", "correcteur orthographique" },
				},
				mission = "Active puis désactive le retour à la ligne : `<Space>uw` deux fois.",
				setup = function(ctx)
					ctx.open("fin.txt", { "Une ligne très longue pour voir l'effet du retour à la ligne : " .. string.rep("bla ", 60) })
				end,
				check = function(ctx)
					return ctx.typed_count("<Space>uw") >= 2
				end,
			},
			{
				title = "Sessions",
				text = "En quittant, l'IDE retient les fichiers et fenêtres ouverts pour chaque dossier.",
				keys = {
					{ "<Space>qs", "restaurer la session du dossier" },
					{ "<Space>ql", "restaurer la dernière session" },
					{ "<Space>qS", "choisir une session" },
					{ "<Space>qd", "ne pas sauver cette session" },
				},
			},
			{
				title = "C'est fini !",
				text = {
					"Bravo, tu as fait le tour de l'IDE.",
					"",
					"Pour la suite : appuie sur `Espace` et explore le menu, c'est la carte de tout ce qui existe.",
				},
				keys = {
					{ "<Space>?", "revenir à ce tutoriel" },
					{ ":Tuto reset", "recommencer de zéro" },
					{ "<Space>L", "plugins (Lazy)" },
					{ "<Space>fc", "fichiers de config" },
				},
			},
		},
	},
}
