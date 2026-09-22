--!strict
--[[
	Lava contact and death.

	Contact is resolved with a bounds query on a fixed tick, NOT with
	BasePart.Touched. At run speed a character tunnels through a thin volume
	between physics steps and .Touched never fires, which is how players end up
	able to bunny-hop straight across a lava pit. A bounds query samples where
	the character actually is.

	Damage is server-side only. The client is told nothing it could lie about.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Trove = require(Shared:WaitForChild("Trove"))

local CheckpointService = require(script.Parent:WaitForChild("CheckpointService"))

local SETTINGS = Config.Lava
local SCAN_INTERVAL = 1 / SETTINGS.ScanHz

local LavaService = {}

local volumes: { BasePart } = {}
local contactSince: { [Player]: number } = {}
local sinking: { [Player]: boolean } = {}
local trove = Trove.new()

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
-- Lava is usually non-collidable so players fall in, so the query must not
-- respect CanCollide.
overlapParams.RespectCanCollide = false

local function playerFromPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function nearAnyPlayer(volume: BasePart, positions: { [Player]: Vector3 }): boolean
	local reach = SETTINGS.ActiveRadius + volume.Size.Magnitude
	local center = volume.Position
	for _, position in positions do
		if (position - center).Magnitude <= reach then
			return true
		end
	end
	return false
end

--[[
	The sink. An instant kill over a parkour gap reads as a broken trigger
	volume; a short controlled descent reads as lava and gives the player the
	beat of feedback that makes the death feel earned.

	The root is anchored for the descent so engine physics does not fight the
	interpolation.
]]
local function sink(player: Player)
	if sinking[player] then
		return
	end
	sinking[player] = true

	task.spawn(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not (humanoid and root and root:IsA("BasePart")) then
			sinking[player] = nil
			return
		end

		humanoid.PlatformStand = true
		root.Anchored = true

		local from = root.CFrame
		local to = from - Vector3.new(0, SETTINGS.SinkDepth, 0)
		local elapsed = 0

		while elapsed < SETTINGS.SinkSeconds do
			elapsed += RunService.Heartbeat:Wait()
			if not root.Parent then
				break
			end
			root.CFrame = from:Lerp(to, math.min(elapsed / SETTINGS.SinkSeconds, 1))
		end

		if humanoid.Parent then
			humanoid.Health = 0
		end

		sinking[player] = nil
		contactSince[player] = nil
	end)
end

local function punish(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if SETTINGS.DamageMode == "DoT" then
		humanoid:TakeDamage(SETTINGS.DoTPerSecond * SCAN_INTERVAL)
	elseif SETTINGS.DamageMode == "Instant" then
		humanoid.Health = 0
	else
		sink(player)
	end
end

local function scan()
	local characters: { Instance } = {}
	local positions: { [Player]: Vector3 } = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			table.insert(characters, character)
			positions[player] = root.Position
		end
	end

	if #characters == 0 then
		table.clear(contactSince)
		return
	end

	overlapParams.FilterDescendantsInstances = characters

	local touching: { [Player]: boolean } = {}
	for index = #volumes, 1, -1 do
		local volume = volumes[index]
		if not volume.Parent then
			table.remove(volumes, index)
		elseif nearAnyPlayer(volume, positions) then
			for _, part in workspace:GetPartBoundsInBox(volume.CFrame, volume.Size, overlapParams) do
				local player = playerFromPart(part)
				if player then
					touching[player] = true
				end
			end
		end
	end

	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if touching[player] then
			-- Grace window: a clipped toe at the edge of a jump survives, a
			-- genuine fall does not.
			contactSince[player] = contactSince[player] or now
			if now - contactSince[player] >= SETTINGS.GraceSeconds then
				punish(player)
			end
		else
			contactSince[player] = nil
		end
	end
end

function LavaService.Start()
	local function track(instance: Instance)
		if instance:IsA("BasePart") and not table.find(volumes, instance) then
			table.insert(volumes, instance)
		end
	end

	for _, instance in CollectionService:GetTagged(SETTINGS.Tag) do
		track(instance)
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(SETTINGS.Tag), track)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(SETTINGS.Tag), function(instance)
		local index = table.find(volumes, instance)
		if index then
			table.remove(volumes, index)
		end
	end)

	trove:Connect(Players.PlayerRemoving, function(player)
		contactSince[player] = nil
		sinking[player] = nil
	end)

	local accumulator = 0
	trove:Connect(RunService.Heartbeat, function(deltaTime)
		accumulator += deltaTime
		if accumulator < SCAN_INTERVAL then
			return
		end
		accumulator = 0
		scan()
	end)
end

function LavaService.Stop()
	trove:Clean()
	table.clear(volumes)
	table.clear(contactSince)
	table.clear(sinking)
end

return LavaService
