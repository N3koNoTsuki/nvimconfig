# nvimconfig

Configuration Neovim (0.12 ou plus récent).

## Installer sur une nouvelle machine

```bash
git clone https://github.com/N3koNoTsuki/nvimconfig.git ~/.config/nvim && ~/.config/nvim/install.sh
```

Une config déjà présente dans `~/.config/nvim` n'est jamais supprimée si tu lances le script depuis un autre
dossier : elle est renommée en `nvim.bak-<date>`.

Le script installe les paquets système (Arch uniquement), les plugins aux versions de `lazy-lock.json`, les
parsers treesitter, les outils Mason, le serveur Discord et la partie notebooks.

| Option | Effet |
| --- | --- |
| `--no-system` | n'installe aucun paquet (pas de sudo), liste seulement les commandes manquantes |
| `--no-notebook` | saute Jupyter : ni octave, ni imagemagick, ni jupytext, ni venv Molten |

Sur une autre distribution, installe d'abord les commandes signalées par le script, puis relance-le.

Une dépendance est cherchée par sa commande, d'où qu'elle vienne : seules les commandes absentes du `PATH` donnent
lieu à une installation de paquet. Si `pacman` échoue, le script continue et signale ce qui manque avec la conséquence.
Une erreur 404 veut dire que la base de paquets est périmée : lance `sudo pacman -Syu`, puis relance le script.

À la fin, le script compare les plugins, les parsers et les outils Mason à ce que la config attend, et échoue s'il
en manque.

## Mettre à jour une machine

```bash
cd ~/.config/nvim && git pull && ./install.sh
```

Le script peut être relancé sans risque. Il remet les plugins aux versions de `lazy-lock.json` : après un
`:Lazy update`, commite ce fichier pour que les autres machines suivent.

`origin` tire en HTTPS sans clé et pousse en SSH, il faut donc la clé GitHub seulement pour `git push`.

## Ce qui dépend de la machine

Tout reste optionnel, la config démarre sans :

| Absent | Conséquence |
| --- | --- |
| Dux Shell / DankMaterialShell | le thème `dms` garde ses réglages par défaut et ne suit plus le mode clair/sombre de la shell |
| niri ou `helium-browser` | `<leader>mp` ouvre l'aperçu Markdown dans le navigateur par défaut |
| kitty | les graphiques des notebooks ne s'affichent pas |
| `~/.local/bin` dans le `PATH` | nvim ne trouve pas `jupytext` |
