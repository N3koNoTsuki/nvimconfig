-- :Tuto        ouvre (ou rejoint) le tutoriel interactif
-- :Tuto reset  remet la progression à zéro
-- :Tuto quit   ferme le tutoriel
vim.api.nvim_create_user_command("Tuto", function(o)
	local tuto = require("tuto")
	if o.args == "reset" then
		tuto.reset()
	elseif o.args == "quit" then
		tuto.quit()
	else
		tuto.open()
	end
end, {
	nargs = "?",
	complete = function()
		return { "reset", "quit" }
	end,
	desc = "Tutoriel interactif de nvim-ide",
})
