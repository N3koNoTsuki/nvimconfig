-- Activité Discord (Rich Presence) : fichier ouvert, langage, projet
-- Marche aussi avec Vesktop (via arRPC). Le serveur est téléchargé par install.sh (:Cord update fetch).
-- https://github.com/vyfor/cord.nvim
return {
	"vyfor/cord.nvim",
	-- module discord (lua/nide/modules.lua) : installé et chargé seulement s'il est activé
	enabled = function() return require("nide.modules").plugin_enabled("vyfor/cord.nvim") end,
	event = "VeryLazy",
	build = ":Cord update fetch",
	opts = {},
}
