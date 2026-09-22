--!strict
--[[
	The slide, driven locally for responsiveness and mirrored to the server for
	its cooldown record.

	Gravity is preserved deliberately: the mover writes X and Z each frame and
	leaves Y to whatever the physics solver already had. Pinning Y is what makes
	a dash feel like being dragged along a rail instead of skidding.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SETTINGS = Config.Slide
local ACTION = "StageReworkSlide"

local player = Players.LocalPlayer
local slideEvent = Remotes.Event("SlideRequest")

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local sliding = false
local nextAllowed = 0

local function bindCharacter(character: Model)
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	sliding = false
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

local function startSlide()
	local currentRoot = root
	local currentHumanoid = humanoid

	if sliding or not currentRoot or not currentHumanoid then
		return
	end
	if currentHumanoid.Health <= 0 then
		return
	end
	if os.clock() < nextAllowed then
		return
	end
	if SETTINGS.RequireGrounded and currentHumanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	sliding = true
	nextAllowed = os.clock() + SETTINGS.Cooldown
	slideEvent:FireServer()

	local direction = currentRoot.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.05 then
		sliding = false
		return
	end
	direction = direction.Unit

	local attachment = Instance.new("Attachment")
	attachment.Name = "SlideAttachment"
	attachment.Parent = currentRoot

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = math.huge
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = direction * SETTINGS.Speed
	mover.Parent = currentRoot

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		if elapsed >= SETTINGS.Seconds or not currentRoot.Parent or not mover.Parent then
			connection:Disconnect()
			mover:Destroy()
			attachment:Destroy()
			sliding = false
			return
		end

		-- Y is left to physics so the slide still falls off ledges.
		mover.VectorVelocity = Vector3.new(
			direction.X * SETTINGS.Speed,
			currentRoot.AssemblyLinearVelocity.Y,
			direction.Z * SETTINGS.Speed
		)
	end)
end

ContextActionService:BindAction(ACTION, function(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		startSlide()
	end
	return Enum.ContextActionResult.Pass
end, true, SETTINGS.Key, SETTINGS.GamepadKey)

ContextActionService:SetTitle(ACTION, "Slide")

-- The server's acknowledgement is the authority on cooldown; the local guess
-- above only exists so the input feels instant.
slideEvent.OnClientEvent:Connect(function(cooldown: number)
	nextAllowed = os.clock() + cooldown
end)
