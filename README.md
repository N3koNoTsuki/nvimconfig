# nide

Une config Neovim (0.12+) pensée pour se comporter comme un IDE : explorateur, onglets, recherche floue,
autocomplétion, LSP pour une douzaine de langages, compilation de projet, débogueur sans configuration (F5),
tests, git, terminal intégré, notebooks, sessions, modèles de projets, activité Discord. Avec un
**tutoriel interactif** intégré pour la prise en main.

Testée sur Arch Linux. Elle s'installe à la place de la config Neovim habituelle (`~/.config/nvim`).

## Installer (Arch Linux)

1. Les dépendances :

   ```bash
   sudo pacman -S --needed neovim git ripgrep fd base-devel tree-sitter-cli curl unzip nodejs npm python lazygit ttf-nerd-fonts-symbols
   sudo pacman -S --needed uv imagemagick   # seulement pour le module Notebooks
   ```

   `uv` et `imagemagick` ne servent qu'aux notebooks Jupyter (le Python des notebooks, les graphiques) :
   inutiles si tu ne coches pas le module Notebooks. Les autres modules demandent parfois leur propre outil
   (voir [Modules](#modules)). Un terminal avec une police Nerd Font est conseillé ; kitty affiche l'intro
   animée et les graphiques des notebooks.

2. La config (sauvegarde d'abord l'ancienne si tu en as une) :

   ```bash
   [ -d ~/.config/nvim ] && mv ~/.config/nvim ~/.config/nvim.old
   git clone https://github.com/N3koNoTsuki/nvimconfig.git ~/.config/nvim
   ~/.config/nvim/install.sh
   ```

Dans un terminal, le script commence par un menu à cocher : la base est toujours installée, tu choisis
les modules (langages, notebooks, Discord…). Il installe ensuite les plugins, les parsers treesitter, les
serveurs LSP / formateurs / débogueurs (Mason) des modules choisis, les dictionnaires français et anglais,
le Python des notebooks et le serveur de l'activité Discord (si ces modules sont cochés), et crée le
lanceur `nide`. Il signale ce qui manque. Tu peux le relancer sans risque, par exemple pour mettre à jour.
Ensuite, `:NideDoctor` (`Espace cD`) fait le bilan : ce qui marche, ce qui manque et la commande pour l'installer
(même bilan au format Neovim : `:checkhealth nide`), y compris les modules actifs et désactivés.

## Modules

La **base** est toujours là : l'éditeur complet (explorateur, recherche, git, terminal, compilation, débogueur,
tutoriel…) et les langages de tous les jours : Lua, Bash, JSON, YAML, Markdown, TOML. Le reste est en modules :

| Module (id) | Ce qu'il apporte | Outil système requis |
| --- | --- | --- |
| C / C++ (`c`) | clangd, clang-format, débogueur codelldb | `gcc` (déjà dans `base-devel`) |
| Rust (`rust`) | rust-analyzer, débogueur codelldb, tests (neotest-rust) | `rust` (rustc, cargo) pour compiler |
| Python (`python`) | pyright, ruff, débogueur debugpy, tests (neotest-python) | `python` (déjà installé) |
| Web (`web`) | TypeScript / JavaScript (ts_ls), HTML, CSS | `nodejs` (déjà installé) ; `tsx` facultatif |
| Go (`go`) | gopls, gofumpt, goimports, débogueur delve, tests (neotest-golang) | `go` **obligatoire** : sans lui le module reste inactif |
| LaTeX (`latex`) | texlab, tex-fmt, vimtex (compilation, PDF synchronisé) | `texlive-basic texlive-latexextra texlive-binextra`, `zathura zathura-pdf-mupdf` |
| Docker (`docker`) | Dockerfile, docker compose, hadolint | aucun |
| SQL (`sql`) | PostgreSQL (postgres_lsp), sql-formatter | aucun |
| Notebooks (`notebook`) | Jupyter (`.ipynb`) : cellules, kernel, graphiques (molten, jupytext, image.nvim, otter) | `uv`, `imagemagick` (graphiques) |
| Discord (`discord`) | activité Rich Presence (cord.nvim, marche avec Vesktop) | Discord ou Vesktop lancé |

Options de `install.sh` :

```bash
~/.config/nvim/install.sh                 # menu à cocher (dans un terminal)
~/.config/nvim/install.sh --all           # tous les modules, sans menu
~/.config/nvim/install.sh --only c,python # seulement ces modules (+ la base), sans menu
~/.config/nvim/install.sh --yes           # sans menu, garde les choix précédents (tout si aucun) : mise à jour
~/.config/nvim/install.sh --dry-run       # montre ce qui serait fait, n'installe rien
~/.config/nvim/install.sh --help          # l'aide
```

**Changer de modules plus tard** : relance `~/.config/nvim/install.sh` et coche / décoche (ou `--only …`).
Les paquets Mason des modules décochés sont désinstallés ; leurs plugins ne sont plus chargés. Les leçons du
tutoriel d'un module désactivé restent lisibles, sans mission.

Le choix est enregistré dans `~/.local/share/nvim/nide-modules.json`, hors du dépôt :

```json
{"modules": {"c": true, "rust": false, "python": true, "notebook": false}}
```

Sans ce fichier (ou pour un module qui n'y figure pas), le module est **activé**. Mieux vaut passer par
`install.sh` que modifier le fichier à la main : c'est lui qui installe et désinstalle les outils.
La liste des modules (serveurs, outils, parsers, plugins de chacun) est dans `lua/nide/modules.lua`.

## Lancer

```bash
nvim              # écran d'accueil
nvim fichier.py   # ouvre un fichier
nvim mon-projet   # se place dans le dossier, écran d'accueil (mode IDE : Espace uI)
```

`nide` (créé dans `~/.local/bin` par `install.sh`) fait la même chose que `nvim`.

**Première fois : appuie sur `Espace` puis `?`** (ou `?` sur l'écran d'accueil, ou `:Tuto`).

L'écran d'accueil s'ouvre sur une courte intro animée (collision p⁺/p̄ qui se pose en logo) : animation
native dans kitty (ghostty ≥ 1.4 aussi), demi-blocs colorés ailleurs. N'importe quelle touche la passe,
`:NideIntro` la rejoue. Réglages (avant `require("core.lazy")` dans `init.lua`) :
`vim.g.nide_intro = false` (pas d'intro), `vim.g.nide_intro_mode = "auto" | "kitty" | "blocks"`.

L'activité Discord (fichier ouvert, langage) s'affiche si Discord ou Vesktop est lancé. Pour la couper,
décoche le module Discord (relance `install.sh`).

## Raccourcis principaux

`<leader>` = **Espace**. Appuie sur Espace et attends : un menu (which-key) montre tout ce qui suit.

| Touche | Action |
| --- | --- |
| `Espace ?` | Tutoriel / prise en main |
| `Espace P` | Palette de commandes (actions de nide, commandes `:`) ; `Ctrl+Maj+P` si ton terminal la transmet |
| `Espace sk` / `Espace sK` | Chercher parmi **tous** les raccourcis / ceux de ce fichier |
| `Espace Espace` / `Ctrl+p` | Chercher un fichier |
| `Espace /` | Chercher du texte dans le projet |
| `Espace ,` | Fichiers ouverts |
| `Espace e` | Explorateur de fichiers |
| `Maj+h` / `Maj+l` | Onglet précédent / suivant |
| `Espace bd` | Fermer l'onglet |
| `Ctrl+s` | Sauvegarder |
| `Ctrl+/` | Terminal (bas) — `Espace tf` : flottant |
| `Ctrl+h/j/k/l` | Changer de fenêtre |
| `s` + 2 lettres | Sauter n'importe où (flash) |
| `Ctrl+n` | Multi-curseur sur l'occurrence suivante |
| `Alt+j` / `Alt+k` | Déplacer la ligne / la sélection |
| `gcc` / `gc` | Commenter |
| `gsa` `gsd` `gsr` | Entourer / supprimer / remplacer `( ) " "` … |
| **Code** | |
| `gd` / `gr` / `gI` / `gy` | Définition / références / implémentations / type |
| `K` | Documentation |
| `Espace ca` | Actions de code (corrections rapides) |
| `Espace cr` / `F2` | Renommer partout |
| `Espace cf` | Formater (auto à la sauvegarde, `Espace uf` pour couper) |
| `Espace co` | Plan du fichier |
| `]e` / `[e` | Erreur suivante / précédente |
| `Espace xx` | Panneau des problèmes |
| `Espace sr` | Rechercher / remplacer dans tout le projet |
| **Exécuter** | |
| `F6` / `Espace r` | Lancer le fichier courant dans un terminal en bas (Python avec le `.venv`, C/C++ via `gcc -Wall -g`, Rust, Lua, JS/TS, shell, Go) ; `make run` si le Makefile du projet a une cible `run` |
| `Espace R` / `:Run args` | Lancer avec des arguments |
| `Espace or` | Revoir la sortie du dernier lancement |
| | Erreurs de compilation → panneau Problèmes (`Entrée` pour y aller, `]q` / `[q`) |
| **Compiler** (façon `M-x compile`) | |
| `Espace k` / `:Compile` | Compiler le projet : commande détectée (make, CMake, Meson, cargo, go, npm/pnpm, just, latexmk, ruff + pyright…) pré-remplie, modifiable, retenue par projet ; `↑` / `↓` = historique |
| `Espace K` / `:Recompile` | Recompiler sans question |
| `Espace kt` / `Espace kh` | Choisir une cible (Makefile, just, scripts npm, binaires cargo) / historique |
| `Espace kw` / `Espace kc` / `Espace ko` | Surveillance (recompile à l'enregistrement) / arrêter / sortie |
| | Sortie en couleurs en bas ; erreurs → diagnostics dans les fichiers (`]e` / `[e`) + quickfix ; `Entrée` sur une ligne de la sortie y emmène |
| **Tâches** (overseer) | |
| `Espace oo` / `Espace ob` | Choisir une tâche (make, cargo, npm…) / compiler le projet (= `Espace k`) |
| `Espace ol` / `Espace os` | Relancer la dernière tâche / commande shell en tâche |
| `Espace ot` / `Espace oa` | Panneau des tâches / action sur une tâche (arrêter…) |
| `Espace oq` | Erreurs de compilation (quickfix) |
| **Mode IDE** | |
| `Espace uI` | Explorateur (gauche) + plan (droite) + terminal (bas), ouvrir / fermer |
| `Espace uE` | Aller à un panneau |
| `]w` / `[w` / `q` | Dans un panneau : suivant / précédent / fermer |
| **Debug & tests** | |
| `F5` | Déboguer le fichier courant sans configuration, ou continuer : C/C++ compilé avec `-g` puis codelldb (avec un Makefile : fichier seul ou make, au choix), Rust via cargo, Python avec le `.venv`, Go |
| `F9` `F10` `F11` `Maj+F11` | Point d'arrêt / passer / entrer / sortir |
| `Espace dA` / `Espace dl` | Déboguer avec des arguments / relancer la dernière session |
| `Espace dT` | Aller dans la console du programme pour taper l'entrée standard (`scanf`, `input`) |
| `Espace dM` | Oublier le choix « fichier seul / make » retenu pour un projet avec Makefile |
| `Espace de` / `Espace dt` / `Espace du` | Évaluer sous le curseur / arrêter / interface ; à la fin du programme l'interface reste ouverte (code de sortie notifié), `q` ou `Espace du` la ferme |
| `Espace tr` / `Espace tF` / `Espace ts` | Test sous le curseur / du fichier / panneau |
| **Git** | |
| `Espace gg` | Lazygit |
| `]h` / `[h` | Bloc modifié suivant / précédent |
| `Espace ghp` / `ghs` / `ghr` | Aperçu / stager / annuler le bloc |
| `Espace gd` | Diff du projet |
| **Nouveau projet & outils** | |
| `:NideNew` / `Espace fN` / `N` (accueil) | Nouveau projet : C, C++ (Makefile, `src/`, `include/`), Python (`.venv`), Rust (cargo), LaTeX, notebook ; `git init` compris. En une ligne : `:NideNew c nom [dossier]` |
| | Squelettes : un nouveau `main.c`, `.h`, `.py`, `.sh` ou `Makefile` démarre pré-rempli ; `:NideSkeleton` dans un fichier vide ; `vim.g.nide_skeletons = false` pour couper |
| `:NideDoctor` / `Espace cD` | Bilan de l'installation (`i` installer via Mason, `y` copier le correctif) ; aussi `:checkhealth nide` |
| `:NideIntro` | Rejouer l'intro animée |
| **Sessions & interface** | |
| `Espace qs` / `Espace ql` | Restaurer la session du dossier / la dernière |
| `Espace u…` | Interrupteurs (retour à la ligne, numéros, indices, thème `uC`…) |
| **Notebooks Jupyter** (`.ipynb`, comme VS Code) | |
| `Ctrl+Entrée` / `Espace jj` | Exécuter la cellule |
| `Maj+Entrée` / `Espace jn` | Exécuter et passer à la suivante |
| `Alt+Entrée` | Exécuter et insérer une cellule |
| `Espace ja` / `Espace jA` | Tout exécuter / jusqu'ici |
| `]j` / `[j` | Cellule suivante / précédente |
| `Espace jb` / `jB` / `jm` / `jd` | Cellule de code dessous / dessus, texte Markdown, supprimer |
| `Espace jo` / `jc` / `jx` / `jr` / `jk` | Entrer dans la sortie, effacer, interrompre, redémarrer, choisir le kernel |
| `Espace jN` ou `:NotebookNew nom` | Nouveau notebook |
| **Markdown** | |
| `Espace mp` | Aperçu réel dans le navigateur (en direct, maths, mermaid) |
| `Espace mr` | Rendu dans l'éditeur (on/off) |
| **C / C++** | |
| `:CompileDb` | Régénérer la base clangd après l'ajout d'un `.c` (générée toute seule sinon) |
| **LaTeX** (vimtex, `\` = localleader) | |
| `\ll` / `\lv` | Compiler en continu / voir le PDF (synchronisé) |
| `\lc` / `\le` | Nettoyer les fichiers auxiliaires / erreurs de compilation |

## Plugins

| Rôle | Plugins |
| --- | --- |
| Gestionnaire | lazy.nvim |
| Interface | catppuccin (+ tokyonight, kanagawa), lualine, bufferline, noice, which-key, dropbar (fil d'Ariane), satellite (barre de défilement), mini.icons, edgy (disposition IDE) |
| Boîte à outils | snacks.nvim : accueil, explorateur, recherche floue, terminal, lazygit, notifications, guides d'indentation, zen, sessions récentes |
| Édition | flash, mini.ai, mini.pairs, mini.move, mini.surround, multicursor.nvim, todo-comments, grug-far |
| Code | nvim-treesitter (+ context), nvim-lspconfig, mason (+ mason-lspconfig, mason-tool-installer), blink.cmp, friendly-snippets, lazydev, conform, nvim-lint, aerial, trouble, render-markdown |
| Exécution & tâches | overseer (tâches ; lanceur F6, compilation Espace k et débogage F5 maison : `lua/util/`) |
| Debug & tests | nvim-dap, nvim-dap-ui, nvim-dap-virtual-text, mason-nvim-dap, nvim-dap-go, neotest (+ python, rust, golang) |
| Langages | vimtex (LaTeX) |
| Git | gitsigns, diffview, lazygit (via snacks) |
| Sessions | persistence.nvim |
| Discord | cord.nvim (activité Rich Presence ; marche avec Vesktop) |
| Notebooks & Markdown | jupytext.nvim, molten-nvim, image.nvim (graphiques dans kitty), otter.nvim (LSP dans les cellules), markdown-preview.nvim |

Langages avec LSP : Lua, Python (pyright + ruff), C/C++ (clangd), Rust, TypeScript/JavaScript, Bash, JSON,
YAML, Markdown, HTML, CSS, TOML, LaTeX (texlab), Docker (dockerls, compose, hadolint),
SQL (postgres_lsp, PostgreSQL seulement ; formatage sql-formatter). Débogage : C/C++/Rust (codelldb),
Python (debugpy), Go (delve).

Chaque langage hors base vient avec son module (voir [Modules](#modules)). Certains demandent un outil
en plus (`install.sh` signale ceux qui manquent) :

| Langage | À installer | Ce qu'on obtient |
| --- | --- | --- |
| Go | `sudo pacman -S --needed go` puis relancer `install.sh` | gopls, gofumpt / goimports, delve, tests (neotest-golang), CodeLens |
| LaTeX | `sudo pacman -S --needed texlive-basic texlive-latexextra texlive-binextra zathura zathura-pdf-mupdf` | compilation latexmk, PDF dans zathura, chktex (texlab et tex-fmt viennent de Mason) |
| TypeScript (F6) | `npm i -g tsx` (optionnel) | lancer un `.ts` avec tsx (sinon node ≥ 22.18) |

## Organisation

```
init.lua               point d'entrée
lua/core/              options, raccourcis de base, autocommandes, bootstrap de lazy
lua/plugins/           un fichier par thème (ui, snacks, editor, coding, lsp, dap, notebook…)
  lang.lua             plugins propres à un langage (vimtex, nvim-dap-go)
  layout.lua           disposition IDE (edgy) et mode IDE Espace uI
  runner.lua           F6 / Espace r et tâches overseer (Espace o)
  compile.lua          Espace k : compiler le projet
  templates.lua        :NideNew, squelettes de fichiers
  discord.lua          activité Discord (cord.nvim)
lua/nide/              palette de commandes, intro animée, :checkhealth nide
  modules.lua          les modules : serveurs, outils, parsers, plugins de chacun, et ceux qui sont activés
lua/util/              la logique maison :
  runner.lua           F6 : commande par langage, compilation, erreurs → quickfix
  project.lua          détection du projet (build le plus proche, commande, cibles), partagée par F5 / F6 / Espace k
  compile.lua          Espace k : compilation, analyse des erreurs, surveillance
  debug.lua            F5 zéro configuration
  templates.lua        nouveaux projets et squelettes
  doctor.lua           :NideDoctor
  notebook.lua         notebooks Jupyter (kernel, cellules)
  compiledb.lua        :CompileDb (base clangd)
lua/tuto/              le tutoriel interactif (init.lua : moteur, lessons.lua : chapitres)
plugin/                commandes :Tuto, :NideDoctor, :NidePalette
templates/             modèles de projets (c, cpp, python, latex, notebook) et squelettes (skeletons/)
assets/intro/          données de l'intro jouées au démarrage (frames kitty, demi-blocs, logo)
tests/                 smoke.sh (test de la config), intro_pty.py (intro dans un vrai terminal)
install.sh             installation / mise à jour
```

Ajouter un serveur LSP : ajoute son nom (nom lspconfig) dans `servers` de la base ou du module voulu,
dans `lua/nide/modules.lua`.

## Notebooks : d'où vient le kernel

À l'ouverture d'un `.ipynb`, le kernel démarre tout seul :
1. un `.venv` / `venv` trouvé en remontant depuis le notebook, s'il contient `ipykernel`
   (sinon : `uv pip install --python .venv/bin/python ipykernel`) ;
2. sinon le kernel enregistré dans le notebook, s'il est installé ;
3. sinon le kernel `nvim-ide` de la config : Python avec numpy, matplotlib, pandas, scipy, sympy (`~/.local/share/nvim/molten-venv`).

`:w` réécrit le `.ipynb` avec les sorties : il se rouvre tel quel dans VS Code ou Jupyter.
Les graphiques s'affichent dans kitty (ou ghostty / WezTerm), pas dans les autres terminaux.

## Vérifier que tout marche

```bash
~/.config/nvim/tests/smoke.sh
```

Démarre l'IDE sans interface, ouvre des fichiers Lua, Python, C, Markdown et un notebook, ouvre le tutoriel,
charge tous les plugins, et affiche `OK` ou les erreurs rencontrées. Il ne touche ni à tes sessions ni
à ta progression dans le tutoriel. À relancer après une mise à jour des plugins.

Il fait deux passes, sans tenir compte de tes modules : tous les modules activés, puis une passe rapide sans
notebook, discord, latex ni rust (les étapes de ces modules sont sautées, et leurs plugins ne doivent pas
être chargés). Pour cela il pointe la variable `NIDE_MODULES_FILE` vers un fichier de choix à lui (absent
pour « tout activé ») ; la config la lit à la place de `~/.local/share/nvim/nide-modules.json`. Les plugins,
eux, doivent être installés (lance `install.sh --all` si tu veux tester un module que tu n'as pas coché).

`tests/intro_pty.py [blocks|kitty] [ms]` teste l'intro dans un vrai pseudo-terminal (demande le module
Python `pyte`).
