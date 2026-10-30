-- ================================================================================================
-- TITLE : cheatsheet
-- ABOUT : fzf-lua picker listing every keymap that is actually defined (config, plugins, Neovim
--         defaults), grouped by category, with a usage example in the preview for the curated ones (★).
--         <CR> runs a normal-mode keymap, or puts an Ex command in the cmdline.
-- ================================================================================================

local M = {}

-- { mode, keys, description, example }
-- mode : "n" normal, "v" visual, "i" insert, "t" terminal, ":" Ex command (left in the cmdline)
M.entries = {
	"Fichiers / navigation", -- category
	{ "n", "-", "Dossier parent (oil)", [[
Dans un fichier ou dans oil, remonte au dossier parent.

Exemple : dans TD5/main.c
  -        -> liste de TD5/
  -        -> liste de TD/
  <CR>     -> rentre dans le dossier / ouvre le fichier sous le curseur]] },
	{ "n", "g?", "Aide oil (dans oil)", [[
Dans une vue oil, affiche toutes les touches disponibles.

Gérer les fichiers = éditer le buffer puis :w
  renommer   : modifier le nom sur la ligne, :w
  créer      : o  test.c  <Esc>  :w      (dossier : finir par /)
  supprimer  : dd  :w
  déplacer   : dd dans un dossier, p dans un autre, :w]] },
	{ "n", "<leader>e", "Arbre nvim-tree (panneau latéral)", [[
Ouvre / ferme l'arbre de fichiers sur le côté (ferme le mode zen si actif).

Dans l'arbre :
  <CR>  ouvrir      a  créer      d  supprimer      r  renommer
  g?    aide]] },
	{ "n", "<leader>ff", "Chercher un fichier (fzf)", [[
Recherche floue sur les noms de fichiers du dossier courant.

Exemple : ouvrir function.c
  <leader>ff  func  <CR>

Dans fzf : <C-j>/<C-k> pour naviguer, <C-v> ouvrir en vsplit]] },
	{ "n", "<leader>fg", "Grep en direct dans le projet", [[
Cherche du texte dans tous les fichiers, résultats en direct.

Exemple : trouver tous les appels à malloc
  <leader>fg  malloc(  <CR> sur un résultat]] },
	{ "n", "<leader>fb", "Liste des buffers ouverts", [[
Basculer rapidement entre les fichiers déjà ouverts.

Exemple : <leader>fb  head  <CR>  -> header.h]] },
	{ "n", "<leader>fh", "Chercher dans l'aide de Neovim", [[
Recherche floue dans :help.

Exemple : <leader>fh  text-objects  <CR>]] },
	{ "n", "<leader>fk", "Tous les raccourcis (liste brute fzf)", [[
Liste brute de tous les raccourcis avec leur description,
sans exemples (version fzf-lua).]] },
	{ "n", "<leader>bd", "Fermer le buffer", [[
Comme :bd. Si c'était le dernier buffer, on retombe sur oil.]] },
	{ "n", "<leader>bn", "Buffer suivant", [[
Passe au buffer suivant. Équivalent natif : ]b]] },
	{ "n", "<leader>bp", "Buffer précédent", [[
Passe au buffer précédent. Équivalent natif : [b]] },
	{ "n", "<C-o>", "Revenir en arrière (sauts)", [[
Revient à la position précédente après un saut (gI, gD, recherche, G...).
<C-i> pour revenir en avant.

Exemple : sur EcrireFiles dans main.c
  gI      -> function.c (corps de la fonction)
  <C-o>   -> retour dans main.c, même ligne]] },
	{ "n", "<C-d>", "Demi-page vers le bas (centré)", [[
Descend d'une demi-page, curseur recentré à l'écran.
<C-u> pour remonter.]] },
	{ "n", "<C-u>", "Demi-page vers le haut (centré)", [[
Remonte d'une demi-page, curseur recentré à l'écran.]] },
	{ "n", "gx", "Ouvrir le lien / fichier sous le curseur", [[
Ouvre l'URL ou le chemin sous le curseur avec l'appli du système.

Exemple : sur https://github.com/stevearc/oil.nvim  ->  gx  -> navigateur]] },
	{ "n", "<leader>pa", "Copier le chemin du fichier", [[
Copie le chemin complet du fichier courant dans le presse-papier.

Exemple : -> /home/neko/Projects/C/INSA/3A/TD/TD5/main.c]] },
	{ "n", "<leader>rc", "Ouvrir la config nvim", [[
Ouvre ~/.config/nvim/init.lua.]] },

	"Compilation / exécution", -- category
	{ "n", "<leader>k", "Compiler (make -k depuis le dossier du fichier)", [[
Lance une commande de build dans le dossier du fichier courant,
sortie dans le buffer *compilation*.

Exemple : dans TD5/main.c
  <leader>k  <CR>               -> make -k dans TD5/
  <leader>k  make clean all <CR>

Dans *compilation* :
  <CR>    aller à l'erreur      <Tab>  erreur suivante
  <C-r>   recompiler            <C-c>  interrompre
  <C-q>   erreurs -> quickfix   q      fermer]] },
	{ "n", "<leader>K", "Recompiler", [[
Relance la dernière commande de compilation, depuis le même dossier.]] },
	{ "n", "]e", "Erreur de compilation suivante", [[
Saute à l'erreur suivante de *compilation*, depuis n'importe quel buffer.

Workflow : <leader>k  ->  ]e  corriger  ]e  corriger  ->  <leader>K]] },
	{ "n", "[e", "Erreur de compilation précédente", [[
Saute à l'erreur précédente de *compilation*.]] },
	{ ":", ":vsplit | terminal ./Output/", "Lancer le programme (interactif)", [[
Ouvre un terminal dans un split et lance ton exécutable.
Nécessaire si le programme fait des scanf.

Exemple :
  :vsplit | terminal ./Output/TD5 source.txt dest.txt
  i       -> taper dans le terminal
  <C-q>   -> revenir en mode normal (pour copier la sortie)]] },
	{ "t", "<C-q>", "Sortir du mode terminal", [[
Dans un :terminal, repasse en mode normal (pour scroller, copier...).
i pour retaper dans le terminal.]] },
	{ ":", ":!", "Commande shell rapide", [[
Lance une commande, la sortie s'affiche en bas puis disparaît.

Exemples :
  :!ls -la
  :!./Output/TD5
  :r !date          -> insère la sortie sous le curseur
  :new | r !make    -> sortie dans un nouveau buffer]] },

	"LSP : lire le code", -- category
	{ "n", "K", "Doc / signature sous le curseur", [[
Affiche la signature et la doc de la fonction sous le curseur.

Exemple : sur fopen  ->  FILE *fopen(const char *path, const char *mode)]] },
	{ "i", "<C-s>", "Signature de la fonction (insertion)", [[
En tapant les arguments d'un appel, affiche la signature.

Exemple : EcrireFiles(file, |   <C-s>
  -> int EcrireFiles(FILE * file, char * FileName, int nbLigne)]] },
	{ "n", "gi", "Aperçu de l'implémentation (corps)", [[
Affiche le corps de la fonction dans une fenêtre flottante.
<CR> dans la fenêtre pour ouvrir le fichier.

Exemple : sur EcrireFiles dans main.c -> aperçu de function.c

Si ça montre header.h : ouvrir function.c une fois (<leader>ff)
pour que clangd le connaisse.]] },
	{ "n", "gI", "Aller à l'implémentation (corps)", [[
Saute au corps de la fonction (function.c). <C-o> pour revenir.]] },
	{ "n", "<leader>gi", "Aperçu de l'implémentation (= gi)", [[
Même chose que gi (présent pour le menu which-key).]] },
	{ "n", "<leader>gI", "Aller à l'implémentation (= gI)", [[
Même chose que gI (présent pour le menu which-key).]] },
	{ "n", "<leader>gd", "Aperçu de la déclaration (prototype)", [[
Affiche le prototype (header.h) dans une fenêtre flottante.

Exemple : sur EcrireFiles
  int EcrireFiles(FILE * file, char * FileName, int nbLigne);]] },
	{ "n", "<leader>gD", "Aller à la déclaration (prototype)", [[
Saute au prototype dans header.h. <C-o> pour revenir.]] },
	{ "n", "<leader>gsi", "Implémentation dans un vsplit", [[
Ouvre le corps de la fonction dans un split vertical,
pour garder l'appel et le code côte à côte.]] },
	{ "n", "<leader>gsd", "Déclaration dans un vsplit", [[
Ouvre le prototype (header.h) dans un split vertical.]] },
	{ "n", "<leader>fr", "Toutes les références", [[
Liste tous les endroits où la fonction / variable est utilisée.

Exemple : sur EcrireFiles -> appels dans main.c, définition, prototype
Natif équivalent : grr]] },
	{ "n", "<leader>fd", "LSP finder (définitions + références)", [[
Tout ce que clangd sait sur le symbole : définition, déclaration,
références, dans une seule liste.]] },
	{ "n", "<leader>fi", "Implémentations (fzf)", [[
Liste les implémentations du symbole. En C, préférer gI (définition) :
"implementation" au sens LSP sert surtout aux méthodes virtuelles C++.]] },
	{ "n", "<leader>ft", "Définition du type", [[
Va à la définition du type de la variable sous le curseur.

Exemple : sur une variable  Liste *l  ->  typedef struct Liste {...}]] },
	{ "n", "<leader>fs", "Symboles du fichier", [[
Liste les fonctions / variables du fichier pour y sauter.

Exemple : <leader>fs  Ecrire  <CR>     (natif : gO)]] },
	{ "n", "<leader>fS", "Symboles du projet", [[
Comme <leader>fs mais dans tout le projet (fichiers connus de clangd).]] },
	{ "n", "<leader>fw", "Symboles du projet (LSP)", [[
Recherche de symboles dans tout le workspace.]] },
	{ "n", "<leader>cs", "Symboles (panneau Trouble)", [[
Panneau latéral avec la structure du fichier (fonctions, structs...).]] },
	{ "n", "<leader>cl", "Définitions / références (Trouble)", [[
Panneau Trouble avec définitions, références, implémentations
du symbole sous le curseur.]] },

	"LSP : modifier le code", -- category
	{ "n", "<leader>rn", "Renommer partout", [[
Renomme le symbole sous le curseur dans tout le projet.

Exemple : sur nbLigne  ->  <leader>rn  nbLignes  <CR>     (natif : grn)]] },
	{ "n", "<leader>ca", "Actions de code", [[
Corrections proposées par clangd (include manquant, etc.).   (natif : gra)

Exemple : sur printf sans #include <stdio.h>
  <leader>ca  -> "Include <stdio.h>"]] },
	{ "n", "<leader>oi", "Organiser les includes", [[
Trie / nettoie les imports si le serveur LSP le supporte, puis formate.]] },

	"Diagnostics", -- category
	{ "n", "<leader>d", "Diagnostic sous le curseur", [[
Affiche le warning / l'erreur clangd sous le curseur.]] },
	{ "n", "<leader>D", "Diagnostics de la ligne", [[
Affiche tous les warnings / erreurs de la ligne courante.]] },
	{ "n", "<leader>nd", "Diagnostic suivant", [[
Saute au warning / erreur suivant(e). Natif : ]d]] },
	{ "n", "<leader>pd", "Diagnostic précédent", [[
Saute au warning / erreur précédent(e). Natif : [d]] },
	{ "n", "<leader>xx", "Diagnostics du projet (Trouble)", [[
Liste de tous les warnings / erreurs du projet dans un panneau.
<CR> sur une ligne pour y aller, q pour fermer.]] },
	{ "n", "<leader>xX", "Diagnostics du fichier (Trouble)", [[
Comme <leader>xx mais seulement pour le fichier courant.]] },
	{ "n", "<leader>fx", "Diagnostics du fichier (fzf)", [[
Diagnostics du fichier dans fzf, avec aperçu.]] },
	{ "n", "<leader>fX", "Diagnostics du projet (fzf)", [[
Diagnostics de tout le projet dans fzf, avec aperçu.]] },
	{ "n", "<leader>xQ", "Quickfix (Trouble)", [[
Affiche la liste quickfix dans Trouble.

Exemple : dans *compilation*, <C-q> envoie les erreurs en quickfix,
puis <leader>xQ pour les parcourir.]] },
	{ "n", "<leader>xL", "Location list (Trouble)", [[
Affiche la location list (quickfix locale à la fenêtre) dans Trouble.]] },
	{ "n", "]q", "Élément quickfix suivant", [[
Passe à l'élément suivant de la quickfix ([q précédent, [Q / ]Q premier / dernier).

Exemple : :vimgrep /malloc/ **/*.c   puis  ]q ]q ]q]] },

	"Recherche / remplacement", -- category
	{ "n", "*", "Chercher le mot sous le curseur", [[
Cherche le mot sous le curseur. n / N : suivant / précédent.
<leader>c pour effacer le surlignage.]] },
	{ "n", "n", "Résultat suivant (centré)", [[
Résultat de recherche suivant, recentré à l'écran. N : précédent.]] },
	{ "n", "<leader>c", "Effacer le surlignage de recherche", [[
Équivalent de :nohlsearch.]] },
	{ ":", ":%s/ancien/nouveau/gc", "Remplacer dans le fichier", [[
Remplace toutes les occurrences, en demandant confirmation (c).
  y oui   n non   a tout   q quitter

En visuel (V) : sélectionner puis  :s/ancien/nouveau/g
Astuce : :%s/\<i\>/k/g  -> seulement le mot entier "i"]] },

	"Édition", -- category
	{ "n", "ciw", "Remplacer le mot", [[
Supprime le mot sous le curseur et passe en insertion.

Variantes (text objects) :
  ci(  ci"  ci{   contenu des (), "", {}
  da(             idem en incluant les ()
  dap             supprimer le bloc / paragraphe]] },
	{ "v", "a / i", "Text objects étendus (mini.ai)", [[
mini.ai ajoute des text objects, utilisables après d, c, y, v :
  if / af    appel de fonction        cif  -> vide les arguments de f(...)
  ia / aa    argument                 daa  -> supprime un argument + la virgule
  iq / aq    n'importe quels guillemets
  ib / ab    n'importe quelles parenthèses / crochets / accolades
  in / an    le prochain (ex. cin" depuis avant la chaîne)
  il / al    le précédent

Exemple : curseur sur  fopen(argv[1], "r")
  cia   -> remplace l'argument sous le curseur]] },
	{ "v", "ii / ai", "Bloc d'indentation (mini.indentscope)", [[
Sélectionne le bloc au même niveau d'indentation.

Exemples :
  vii   -> sélectionne le corps du for / if / fonction
  dai   -> supprime le bloc avec la ligne d'ouverture et de fermeture
  [i / ]i  -> aller au début / à la fin du bloc]] },
	{ "n", "sa", "Entourer (mini.surround)", [[
Ajoute des délimiteurs autour d'un text object.

Exemples :
  saiw)    mot       -> (mot)
  saiw"    mot       -> "mot"
  En visuel : sélectionner puis  sa]  ]] },
	{ "n", "sd", "Supprimer l'entourage", [[
Supprime les délimiteurs autour du curseur.

Exemples :
  sd"   "texte"  -> texte
  sd)   (a + b)  -> a + b]] },
	{ "n", "sr", "Remplacer l'entourage", [[
Remplace les délimiteurs autour du curseur.

Exemple :
  sr)]   (a + b)  -> [a + b]
  sr'"   'c'      -> "c"]] },
	{ "n", "gcc", "Commenter la ligne", [[
Commente / décommente la ligne.

Exemples :
  gcc        -> ligne courante
  gcip       -> tout le paragraphe
  V jjj gc   -> 4 lignes en visuel]] },
	{ "v", "gc", "Commenter la sélection", [[
Commente / décommente les lignes sélectionnées.]] },
	{ "n", "<M-j>", "Déplacer la ligne (mini.move)", [[
Alt + h/j/k/l déplace la ligne (ou la sélection en visuel)
vers la gauche / le bas / le haut / la droite.

Exemple : V jj  puis  <M-k><M-k>  -> remonte 3 lignes de 2 crans]] },
	{ "n", "J", "Joindre les lignes (curseur fixe)", [[
Joint la ligne suivante à la ligne courante sans bouger le curseur.]] },
	{ "n", "]<leader>", "Ligne vide en dessous", [[
Ajoute une ligne vide sous le curseur sans passer en insertion.
[<leader> pour au-dessus. 3]<leader> pour 3 lignes.]] },
	{ "v", "<leader>p", "Coller sans écraser le registre", [[
Remplace la sélection par le contenu copié, sans que le texte
remplacé n'écrase ce que tu as copié.

Exemple : yiw sur "toto", puis viw<leader>p sur plusieurs mots]] },
	{ "n", "<leader>x", "Supprimer sans copier", [[
Supprime dans le registre "trou noir" : ne touche pas à ce qui est copié.

Exemple : <leader>xiw  (mot)   <leader>x$  (jusqu'à la fin de ligne)
En visuel : sélectionner puis <leader>x
(<leader>xx est pris par Trouble : pour une ligne, utiliser "_dd)]] },
	{ "v", ">", "Indenter (sélection gardée)", [[
Indente la sélection et la garde active pour répéter. < pour désindenter.]] },
	{ "n", "qa", "Enregistrer une macro", [[
Enregistre une suite d'actions pour la rejouer.

Exemple : ajouter ; à la fin de 10 lignes
  qa   A;<Esc>j   q      -> enregistre dans a
  9@a                    -> rejoue 9 fois]] },
	{ "n", ".", "Répéter la dernière modification", [[
Rejoue la dernière modification à la position du curseur.

Exemple : ciw  toto <Esc>   puis  *  n  .  n  .]] },

	"Complétion (insertion)", -- category
	{ "i", "<C-Space>", "Ouvrir la complétion", [[
Force l'ouverture du menu de complétion.

Dans le menu :
  <C-j> / <C-k>   suivant / précédent
  <CR>            valider (seulement si un élément est sélectionné)
  <C-e>           fermer
  <C-f> / <C-b>   scroller la doc]] },
	{ "i", "<Tab>", "Sauter au champ suivant du snippet", [[
Dans un snippet inséré (ex. une boucle for), passe au champ suivant.
<S-Tab> pour revenir au précédent.]] },

	"Fenêtres", -- category
	{ "n", "<leader>sv", "Split vertical (oil)", [[
Ouvre un split vertical sur la vue oil du dossier courant.
<C-w>o pour ne garder que la fenêtre courante, <C-w>= pour égaliser.]] },
	{ "n", "<leader>sh", "Split horizontal (oil)", [[
Ouvre un split horizontal sur la vue oil du dossier courant.]] },
	{ "n", "<C-h>", "Fenêtre de gauche (marche aussi avec tmux)", [[
<C-h> <C-j> <C-k> <C-l> : changer de fenêtre (aussi entre panes tmux).]] },
	{ "n", "<C-Up>", "Redimensionner la fenêtre", [[
<C-Up> / <C-Down> : hauteur      <C-Left> / <C-Right> : largeur]] },
	{ "n", "<leader>z", "Mode zen", [[
Centre le buffer et masque le reste.]] },

	"Debug", -- category
	{ "n", "<leader>db", "Point d'arrêt", [[
Pose / enlève un breakpoint sur la ligne (compiler avec -g).

Workflow :
  <leader>db  sur la ligne
  <leader>dc  -> chemin : Output/TD5   -> arguments
  <leader>do  step over     <leader>di  step into
  <leader>du  step out      <leader>dc  continuer]] },
	{ "n", "<leader>dc", "Démarrer / continuer le debug", [[
Lance codelldb (demande l'exécutable, ex. Output/TD5) ou continue
jusqu'au prochain breakpoint.]] },
	{ "n", "<leader>do", "Debug : step over", [[
Exécute la ligne courante sans rentrer dans les fonctions appelées.]] },
	{ "n", "<leader>di", "Debug : step into", [[
Rentre dans la fonction appelée sur la ligne courante.

Exemple : sur EcrireFiles(...) -> on arrive dans function.c]] },
	{ "n", "<leader>du", "Debug : step out", [[
Termine la fonction courante et revient à l'appelant.]] },
	{ "n", "<leader>dr", "Debug : REPL", [=[
Ouvre la console du debugger pour évaluer des expressions.

Exemple : p nbLigne    p *file    p tab[3]]=] },

	"Git", -- category
	{ "n", "<leader>hv", "Diff du fichier en 2 splits (vs index)", [[
Diff du fichier courant, dans le même onglet :
  gauche = version de l'index (git add)   droite = TON fichier (éditable)
<leader>hV : pareil mais contre le dernier commit (HEAD).

Dans le diff :
  ]c / [c    changement suivant / précédent
  do         récupérer le bloc de l'autre côté (diff obtain)
  dp         envoyer le bloc de l'autre côté (diff put)
  <leader>hj rester sur le fichier réel, fermer le diff
  <leader>hq fermer le diff

Exemple : dans TD5/main.c
  <leader>hv   ]c ]c   <leader>hj  -> retour sur main.c à la ligne du changement]] },
	{ "n", "<leader>ht", "Diff du TD courant (diffview)", [[
Mono-repo : un seul dépôt git (INSA/3A/TD) avec un dossier par TD/TP.
<leader>ht ne montre QUE les fichiers modifiés du dossier du fichier courant
(TD5/, TP/...). À la racine (README.md) -> tout le dépôt.
<leader>hD : toujours tout le dépôt.

Fonctionne même si nvim a été lancé ailleurs (ex. depuis ~) :
le dépôt est trouvé à partir du fichier courant (ou du dossier oil).

Écran : panneau des fichiers à gauche, puis ancien | nouveau côte à côte.
  <Tab> / <S-Tab>  fichier modifié suivant / précédent
  ]c / [c          changement suivant / précédent
  -                stage / unstage le fichier (dans le panneau)
  <leader>hj       ouvrir le fichier réel à la ligne du curseur, fermer le diff
  gf               ouvrir le fichier réel, en gardant le diff (onglet)
  <leader>hq       fermer
  g?               aide diffview

Exemple : dans TD5/main.c
  <leader>ht  -> TD5/main.c, TD5/function.c   (TD4/ n'apparaît pas)
  <Tab>  ]c   <leader>hj  -> function.c, sur la ligne modifiée]] },
	{ "n", "<leader>hD", "Diff de tout le dépôt (diffview)", [[
Comme <leader>ht mais tous les dossiers (TD1..TD5, TP, README).
Utile avant un commit qui touche plusieurs TD.]] },
	{ "n", "<leader>hj", "Quitter le diff -> fichier réel", [[
Depuis un diff (diffview OU <leader>hv), ferme le diff et laisse
le vrai fichier ouvert, curseur sur la ligne qu'on regardait.

Exemple : <leader>ht  <Tab>  ]c  <leader>hj  -> on corrige directement]] },
	{ "n", "<leader>hq", "Fermer le diff", [[
Ferme diffview ou le split fugitive, retour là où on était.]] },
	{ "n", "<leader>hf", "Historique du fichier", [[
Liste des commits qui ont touché le fichier courant, avec leur diff.
  <CR>       voir ce commit       <Tab>  commit suivant
  <leader>hj aller au fichier réel      <leader>hq fermer
<leader>hF : historique de tout le TD courant (ex. TD5/).]] },
	{ "n", "<leader>hF", "Historique du TD courant", [[
Commits qui ont touché le dossier du TD (mono-repo : TD5/ seulement).

Exemple : dans TD5/main.c  ->  <leader>hF  -> "Ajout du TD5..." uniquement]] },
	{ "n", "]h", "Hunk git suivant (gitsigns)", [[
Saute au bloc modifié suivant dans le fichier ([h précédent).
Marche partout, pas besoin d'ouvrir un diff.
  <leader>hp  aperçu du bloc (ancien contenu)
  <leader>hr  annuler le bloc (revient à la version git)
  <leader>hs  stage / unstage le bloc   (en visuel : seulement les lignes)
  <leader>hS  stage tout le fichier]] },
	{ "n", "<leader>hp", "Aperçu du hunk", [[
Fenêtre flottante avec l'ancien et le nouveau contenu du bloc.]] },
	{ "n", "<leader>hb", "Blame de la ligne", [[
Qui a modifié la ligne, quand, dans quel commit (message complet).
<leader>hB : blame de tout le fichier dans un panneau.]] },
	{ "n", "<leader>hg", "Git status (fugitive)", [[
Statut du dépôt (tout le mono-repo).
  s / u   stage / unstage le fichier sous le curseur
  =       afficher le diff inline       dv  diff en 2 splits
  cc      commit                        g?  aide
Exemple : <leader>hg  s s  cc  "TD5 : fix malloc"  :wq]] },
	{ ":", ":Git ", "N'importe quelle commande git", [[
Lance git depuis nvim, sortie dans un buffer.

Exemples :
  :Git push
  :Git log --oneline -- TD5
  :Git add TD5]] },

	"Aide", -- category
	{ "n", "<leader>/", "Cette cheatsheet", [[
Liste de tous les raccourcis. ★ = avec un exemple rédigé.
Ajouter / modifier un exemple : lua/utils/cheatsheet.lua]] },
}

local mode_names = { n = "normal", x = "visuel", i = "insertion", t = "terminal", [":"] = "commande" }
local live_modes = { "n", "x", "i", "t" }

-- category of the keymaps that have no curated entry, by the plugin that defines them
local plugin_category = {
	["mini.ai"] = "Édition",
	["mini.comment"] = "Édition",
	["mini.indentscope"] = "Édition",
	["mini.move"] = "Édition",
	["mini.surround"] = "Édition",
	["oil.nvim"] = "Fichiers / navigation",
	["fzf-lua"] = "Fichiers / navigation",
	["nvim-tree.lua"] = "Fichiers / navigation",
	["compile-mode.nvim"] = "Compilation / exécution",
	["lspsaga.nvim"] = "LSP : lire le code",
	["trouble.nvim"] = "Diagnostics",
	["LuaSnip"] = "Complétion (insertion)",
	["nvim-cmp"] = "Complétion (insertion)",
	["zen-mode.nvim"] = "Fenêtres",
	["vim-tmux-navigator"] = "Fenêtres",
	["nvim-dap"] = "Debug",
	["nvim-dap-ui"] = "Debug",
	["gitsigns.nvim"] = "Git",
	["vim-fugitive"] = "Git",
	["which-key.nvim"] = "Aide",
}
local DEFAULTS = "Neovim (défauts)"
local MINE = "Mes autres raccourcis"
local ALL = "Tout"

local function display_lhs(lhs)
	return (lhs:gsub(" ", "<leader>"))
end

-- keymaps from Neovim/plugins that are just noise in a cheatsheet
local function is_noise(mode, map)
	if not map.desc or map.desc == "" then
		return true
	end
	if map.lhs:find("<Plug>") or map.lhs:find("<SNR>") then
		return true
	end
	if map.desc:match("^:help ") then
		return true
	end
	if mode == "i" and (map.desc:find("pair") or map.desc:find("MiniPairs")) then
		return true
	end
	return false
end

local function source_of(map)
	if map.callback then
		local info = debug.getinfo(map.callback, "S")
		return (info.source:gsub("^@", ""))
	end
	return nil
end

local function category_of(map)
	local src = source_of(map)
	if src then
		local plugin = src:match("/lazy/([^/]+)/")
		if plugin then
			return plugin_category[plugin] or ("Plugins : " .. plugin)
		end
		if src:find(vim.fn.stdpath("config"), 1, true) then
			return MINE
		end
		return DEFAULTS
	end
	local mini = map.rhs and map.rhs:match("Mini(%a+)") -- e.g. :<C-U>lua MiniSurround.add("visual")
	if mini then
		return plugin_category["mini." .. mini:lower()] or DEFAULTS
	end
	return DEFAULTS
end

-- curated entries + every live keymap, grouped by category (in display order)
local function collect()
	local categories, by_name = {}, {}
	local function add(name, item)
		if not by_name[name] then
			by_name[name] = { name = name, items = {} }
			table.insert(categories, by_name[name])
		end
		table.insert(by_name[name].items, item)
	end

	local curated = {} -- mode .. keycode -> true
	local current = MINE
	for _, entry in ipairs(M.entries) do
		if type(entry) == "string" then
			current = entry
		else
			local mode = entry[1] == "v" and "x" or entry[1]
			curated[mode .. vim.keycode(entry[2])] = true
			add(current, { mode = mode, lhs = entry[2], desc = entry[3], example = entry[4] })
		end
	end

	local seen, auto = {}, {}
	for _, mode in ipairs(live_modes) do
		local maps = vim.list_extend(vim.api.nvim_buf_get_keymap(0, mode), vim.api.nvim_get_keymap(mode))
		for _, map in ipairs(maps) do
			local id = mode .. vim.keycode(map.lhs)
			if not is_noise(mode, map) and not curated[id] and not seen[id] then
				seen[id] = true
				table.insert(auto, { mode = mode, lhs = display_lhs(map.lhs), desc = map.desc, map = map })
			end
		end
	end
	table.sort(auto, function(a, b)
		return a.mode == b.mode and a.lhs < b.lhs or a.mode < b.mode
	end)
	for _, item in ipairs(auto) do
		add(category_of(item.map), item)
	end

	-- keep Neovim defaults last, and a "Tout" folder first to search everything at once
	for i, cat in ipairs(categories) do
		if cat.name == DEFAULTS then
			table.insert(categories, table.remove(categories, i))
			break
		end
	end
	local all = { name = ALL, items = {} }
	for _, cat in ipairs(categories) do
		vim.list_extend(all.items, cat.items)
	end
	table.insert(categories, 1, all)
	return categories
end

local function item_line(item)
	local tag = item.mode == "x" and "v" or item.mode
	return string.format("%s %s %-12s %s", item.example and "★" or " ", tag, item.lhs, item.desc)
end

local function item_preview(item)
	local head = string.format("%s   (mode %s)\n%s\n\n", item.lhs, mode_names[item.mode], item.desc)
	if item.example then
		return head .. item.example
	end
	local map = item.map
	local action = map.rhs and map.rhs ~= "" and map.rhs or "fonction Lua"
	local src = source_of(map)
	if src and map.callback then
		src = src:gsub(vim.env.HOME, "~") .. ":" .. debug.getinfo(map.callback, "S").linedefined
	end
	return head
		.. "Action : "
		.. action
		.. (src and ("\nDéfini dans : " .. src) or "")
		.. "\n\n(pas d'exemple rédigé : à ajouter dans lua/utils/cheatsheet.lua)"
end

local function run(item)
	if item.mode == ":" then
		vim.api.nvim_feedkeys(item.lhs, "n", false) -- leave it in the cmdline to complete
	elseif item.mode == "n" and not item.lhs:find(" ") then
		vim.api.nvim_feedkeys(vim.keycode(item.lhs), "m", false)
	else
		vim.notify(item.lhs .. " : raccourci en mode " .. mode_names[item.mode], vim.log.levels.INFO)
	end
end

local open_categories -- forward declaration (the items picker goes back to it)

local function open_items(category, categories)
	local by_line, lines = {}, {}
	for _, item in ipairs(category.items) do
		local line = item_line(item)
		by_line[line] = item
		table.insert(lines, line)
	end

	require("fzf-lua").fzf_exec(lines, {
		prompt = category.name .. "> ",
		preview = function(selected)
			local item = by_line[selected[1]]
			return item and item_preview(item) or ""
		end,
		fzf_opts = {
			["--preview-window"] = "right,55%,wrap",
			["--header"] = "ctrl-b : retour aux catégories   ★ = exemple rédigé",
		},
		actions = {
			["default"] = function(selected)
				local item = by_line[selected[1]]
				if item then
					run(item)
				end
			end,
			["ctrl-b"] = function()
				open_categories(categories)
			end,
		},
	})
end

open_categories = function(categories)
	categories = categories or collect()
	local by_line, lines = {}, {}
	for _, cat in ipairs(categories) do
		local stars = 0
		for _, item in ipairs(cat.items) do
			stars = stars + (item.example and 1 or 0)
		end
		local pad = string.rep(" ", 28 - vim.fn.strdisplaywidth(cat.name)) -- %-28s counts bytes, not chars (é)
		local line = string.format("%s%s %3d raccourcis  %s", cat.name, pad, #cat.items, stars > 0 and ("★ " .. stars) or "")
		by_line[line] = cat
		table.insert(lines, line)
	end

	require("fzf-lua").fzf_exec(lines, {
		prompt = "Cheatsheet> ",
		preview = function(selected)
			local cat = by_line[selected[1]]
			if not cat then
				return ""
			end
			local out = {}
			for _, item in ipairs(cat.items) do
				table.insert(out, item_line(item))
			end
			return table.concat(out, "\n")
		end,
		fzf_opts = {
			["--preview-window"] = "right,60%",
			["--header"] = "<CR> : ouvrir la catégorie",
		},
		actions = {
			["default"] = function(selected)
				local cat = by_line[selected[1]]
				if cat then
					open_items(cat, categories)
				end
			end,
		},
	})
end

M.open = function()
	open_categories()
end

return M
