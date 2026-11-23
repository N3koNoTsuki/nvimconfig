-- :checkhealth nide : le bilan de :NideDoctor au format checkhealth
local M = {}

function M.check()
	local doctor = require("util.doctor")
	doctor.probe_sync(3000)
	local report = doctor.collect()
	vim.health.start("nide")
	vim.health.info(doctor.summary(report) .. " (détails et installation : :NideDoctor)")
	for _, s in ipairs(report.sections) do
		vim.health.start("nide : " .. s.title)
		for _, it in ipairs(s.items) do
			local msg = it.label
			if it.parts then
				local parts = {}
				for _, p in ipairs(it.parts) do
					table.insert(parts, (p.skip and "–" or p.ok and "✓" or "✗") .. " " .. p.name)
				end
				msg = msg .. " : " .. table.concat(parts, "  ")
			elseif it.text then
				msg = msg .. " : " .. it.text
			end
			if it.status == "ok" then
				vim.health.ok(msg)
			elseif it.status == "err" then
				vim.health.error(msg, it.fix)
			elseif it.status == "opt" then
				vim.health.warn(msg .. " (facultatif)", it.fix)
			else
				vim.health.info(msg .. (it.fix and (" → " .. it.fix) or ""))
			end
		end
	end
end

return M
