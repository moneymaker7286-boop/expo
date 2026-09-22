--!strict
--[[
	Rising lava rounds.

	This is a separate mode from LavaService, deliberately. LavaService guards
	a static hazard inside a checkpointed parkour level: it forgives a clipped
	toe and sends you back one checkpoint. Here the lava is the clock, contact
	ends your round outright, and there is no checkpoint to return to.

	Contact is a height comparison, not a bounds query. The rising plane is
	enormous and axis-aligned, so "is the player's root below the surface" is
	both cheaper and more reliable than overlap testing against it.

	Tag the lava plane "RisingLava". Its starting CFrame is captured at boot
	and restored between rounds.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Trove = require(Shared:WaitForChild("Trove"))

local SETTINGS = Config.RisingLava

export type Phase = "Idle" | "Intermission" | "Warmup" | "Rising" | "Results"

local RisingLavaService = {}

local trove = Trove.new()
local stateEvent = Remotes.Event("RisingLavaState")

local plane: BasePart? = nil
local restCFrame: CFrame? = nil

local phase: Phase = "Idle"
local phaseEndsAt = 0
local riseSpeed = 0
local alive: { [Player]: boolean } = {}
local running = false

local function surfaceY(): number
	local part = plane
	if not part then
		return -math.huge
	end
	return part.Position.Y + part.Size.Y * 0.5
end

local function countAlive(): number
	local count = 0
	for _ in alive do
		count += 1
	end
	return count
end

local function broadcast()
	local part = plane
	stateEvent:FireAllClients({
		phase = phase,
		secondsLeft = math.max(phaseEndsAt - os.clock(), 0),
		surfaceY = part and surfaceY() or nil,
		aliveCount = countAlive(),
		warningStuds = SETTINGS.WarningClearanceStuds,
	})
end

local function setPhase(next: Phase, seconds: number)
	phase = next
	phaseEndsAt = os.clock() + seconds
	broadcast()
end

local function eligiblePlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, player)
	end
	return list
end

local function eliminate(player: Player)
	if not alive[player] then
		return
	end
	alive[player] = nil

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function resetPlane()
	local part = plane
	if part and restCFrame then
		part.CFrame = restCFrame
	end
	riseSpeed = SETTINGS.RiseStudsPerSecond
end

--[[
	The rise. Accelerating rather than linear: a flat climb makes the whole
	round feel the same, where a ramp puts the pressure in the last stretch.
]]
local function stepRise(deltaTime: number)
	local part = plane
	if not part then
		return
	end

	riseSpeed += SETTINGS.RiseAcceleration * deltaTime
	part.CFrame = part.CFrame + Vector3.new(0, riseSpeed * deltaTime, 0)

	local top = surfaceY()
	for player in alive do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
			alive[player] = nil
		elseif root.Position.Y <= top then
			-- No grace window. This is a race, and a forgiving edge here would
			-- let a player stand in lava to cut a corner.
			eliminate(player)
		end
	end
end

local function runRound()
	resetPlane()
	table.clear(alive)

	setPhase("Intermission", SETTINGS.IntermissionSeconds)
	while os.clock() < phaseEndsAt do
		task.wait(0.25)
		broadcast()
	end

	if #eligiblePlayers() < SETTINGS.MinPlayers then
		phase = "Idle"
		broadcast()
		return
	end

	for _, player in eligiblePlayers() do
		alive[player] = true
		player:LoadCharacter()
	end

	setPhase("Warmup", SETTINGS.WarmupSeconds)
	while os.clock() < phaseEndsAt do
		task.wait(0.25)
		broadcast()
	end

	setPhase("Rising", SETTINGS.RoundSeconds)
	local broadcastInterval = 1 / SETTINGS.BroadcastHz
	local sinceBroadcast = 0
	local lastTick = os.clock()

	while os.clock() < phaseEndsAt and countAlive() > 0 do
		local now = os.clock()
		local deltaTime = now - lastTick
		lastTick = now

		stepRise(deltaTime)

		sinceBroadcast += deltaTime
		if sinceBroadcast >= broadcastInterval then
			sinceBroadcast = 0
			broadcast()
		end

		RunService.Heartbeat:Wait()
	end

	setPhase("Results", 4)
	task.wait(4)
	resetPlane()

	for _, player in Players:GetPlayers() do
		player:LoadCharacter()
	end
end

function RisingLavaService.Start()
	local tagged = CollectionService:GetTagged(SETTINGS.Tag)
	for _, instance in tagged do
		if instance:IsA("BasePart") then
			plane = instance
			restCFrame = instance.CFrame
			break
		end
	end

	if not plane then
		-- Not an error: a place with no rising-lava stage simply does not run
		-- this mode. LavaService still guards any static lava.
		warn("[RisingLavaService] no part tagged RisingLava — mode idle")
		return
	end

	riseSpeed = SETTINGS.RiseStudsPerSecond

	trove:Connect(Players.PlayerRemoving, function(player)
		alive[player] = nil
	end)

	running = true
	trove:Add(function()
		running = false
	end)

	task.spawn(function()
		while running do
			local ok, err = pcall(runRound)
			if not ok then
				warn(("[RisingLavaService] round failed: %s"):format(tostring(err)))
				task.wait(3)
			end
			task.wait(0.5)
		end
	end)
end

function RisingLavaService.Stop()
	trove:Clean()
	resetPlane()
	table.clear(alive)
	phase = "Idle"
end

return RisingLavaService
