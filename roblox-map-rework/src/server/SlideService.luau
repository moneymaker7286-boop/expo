--!strict
--[[
	Slide cooldown gate.

	Be clear about what this is and is not. Roblox hands a client network
	ownership of its own character, so the client can already write
	AssemblyLinearVelocity on itself whether or not we grant a slide. This
	service is therefore NOT an anti-exploit boundary for movement — it enforces
	a consistent cooldown for honest clients and gives the server a truthful
	answer to "is this player sliding right now", which matters for anything
	that keys off the slide (scoring, ability gating, a slide-only shortcut).

	Anything that must not be forged — damage, currency, round elimination —
	stays server-authoritative in its own service and never trusts this.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Trove = require(Shared:WaitForChild("Trove"))

local SETTINGS = Config.Slide

local SlideService = {}

local trove = Trove.new()
local slideEvent = Remotes.Event("SlideRequest")

local nextAllowed: { [Player]: number } = {}
local slidingUntil: { [Player]: number } = {}

function SlideService.IsSliding(player: Player): boolean
	local until_ = slidingUntil[player]
	return until_ ~= nil and os.clock() < until_
end

function SlideService.Start()
	trove:Connect(slideEvent.OnServerEvent, function(player: Player)
		local now = os.clock()

		-- Rate limit. A flood of requests costs the server nothing beyond
		-- this comparison.
		if nextAllowed[player] and now < nextAllowed[player] then
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		if SETTINGS.RequireGrounded and humanoid.FloorMaterial == Enum.Material.Air then
			return
		end

		nextAllowed[player] = now + SETTINGS.Cooldown
		slidingUntil[player] = now + SETTINGS.Seconds

		-- Acknowledge, so the client can show the cooldown honestly rather
		-- than guessing.
		slideEvent:FireClient(player, SETTINGS.Cooldown)
	end)

	trove:Connect(Players.PlayerRemoving, function(player)
		nextAllowed[player] = nil
		slidingUntil[player] = nil
	end)
end

function SlideService.Stop()
	trove:Clean()
	table.clear(nextAllowed)
	table.clear(slidingUntil)
end

return SlideService
