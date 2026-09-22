--!strict
--[[
	Checkpoints. Server-authoritative, because the respawn position is exactly
	the kind of thing an exploiter would otherwise set themselves.

	Progress is in-memory only: it survives death, not a rejoin. Persisting it
	means a ProfileService-style session-locked store, which is deliberately
	out of scope here — raw SetAsync on player progress loses data.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Trove = require(Shared:WaitForChild("Trove"))

local SETTINGS = Config.Checkpoint

local CheckpointService = {}

local lastCheckpoint: { [Player]: CFrame } = {}
local trove = Trove.new()

local function playerFromPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character) or nil
end

function CheckpointService.Record(player: Player, cframe: CFrame)
	lastCheckpoint[player] = cframe
end

function CheckpointService.Get(player: Player): CFrame?
	return lastCheckpoint[player]
end

--[[
	Places a freshly spawned character at its last checkpoint. Called from the
	CharacterAdded path rather than on death, so it covers every respawn route
	(lava, a fall, /reset) without each one needing its own teleport.
]]
local function placeAtCheckpoint(player: Player, character: Model)
	local cframe = lastCheckpoint[player]
	if not cframe then
		return
	end

	if not character:FindFirstChild("HumanoidRootPart") then
		character:WaitForChild("HumanoidRootPart", 5)
	end

	-- Deferred so the engine has finished its own spawn placement first,
	-- otherwise it overwrites ours.
	task.defer(function()
		if character.Parent and character:FindFirstChild("HumanoidRootPart") then
			character:PivotTo(cframe + Vector3.new(0, SETTINGS.SpawnHeight, 0))
		end
	end)
end

local function bindCheckpoint(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	trove:Connect(part.Touched, function(hit: BasePart)
		local player = playerFromPart(hit)
		if not player then
			return
		end
		-- Re-touching an earlier checkpoint must not roll progress backwards.
		local existing = lastCheckpoint[player]
		if existing and existing.Position:FuzzyEq(part.Position, 0.5) then
			return
		end
		CheckpointService.Record(player, part.CFrame)
	end)
end

local function bindPlayer(player: Player)
	trove:Connect(player.CharacterAdded, function(character)
		placeAtCheckpoint(player, character)
	end)
end

function CheckpointService.Start()
	for _, part in CollectionService:GetTagged(SETTINGS.Tag) do
		bindCheckpoint(part)
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(SETTINGS.Tag), bindCheckpoint)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
	trove:Connect(Players.PlayerAdded, bindPlayer)

	trove:Connect(Players.PlayerRemoving, function(player)
		lastCheckpoint[player] = nil
	end)
end

function CheckpointService.Stop()
	trove:Clean()
	table.clear(lastCheckpoint)
end

return CheckpointService
