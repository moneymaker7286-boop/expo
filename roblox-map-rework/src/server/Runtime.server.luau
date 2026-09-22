--!strict
--[[
	The only Script in the project. Everything else is a ModuleScript started
	from here, in dependency order, so load order is explicit rather than
	whatever order the engine happens to pick.
]]

local services = script.Parent :: Instance

local CheckpointService = require(services:WaitForChild("CheckpointService"))
local LavaService = require(services:WaitForChild("LavaService"))
local MonkeyService = require(services:WaitForChild("MonkeyService"))
local ParkourService = require(services:WaitForChild("ParkourService"))
local RisingLavaService = require(services:WaitForChild("RisingLavaService"))
local SlideService = require(services:WaitForChild("SlideService"))

local START_ORDER = {
	{ name = "CheckpointService", service = CheckpointService },
	{ name = "LavaService", service = LavaService },
	{ name = "ParkourService", service = ParkourService },
	{ name = "SlideService", service = SlideService },
	{ name = "RisingLavaService", service = RisingLavaService },
	{ name = "MonkeyService", service = MonkeyService },
}

for _, entry in START_ORDER do
	local ok, err = pcall(entry.service.Start)
	if ok then
		print(("[StageRework] %s started"):format(entry.name))
	else
		-- One service failing must not take the rest of the stage down.
		warn(("[StageRework] %s failed to start: %s"):format(entry.name, tostring(err)))
	end
end
