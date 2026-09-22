--!strict
--[[
	Parkour obstacle kit. Every obstacle is a tagged part, configured by
	attributes on that part, so the whole course is authored in Studio without
	touching code.

	  MovingPlatform    MoveOffset (Vector3), MoveSeconds, MoveDelay
	  CrumblePlatform   CrumbleDelay, CrumbleRestore
	  RotatingBeam      SpinAxis (Vector3), SpinDegreesPerSecond
	  SwingingVine      SwingDegrees, SwingSeconds
	  LaunchPad         LaunchImpulse, LaunchDirection (Vector3)
	  ForgivingLanding  adds an invisible collision shim slightly wider than
	                    the visual part

	KNOWN TRADEOFF on MovingPlatform: a CFrame-tweened anchored part does not
	impart velocity to a character standing on it, so players drift toward the
	trailing edge on fast or long travels. It is what most shipped obbies do and
	it is fine under roughly 12 studs/second. If you need a platform that
	carries cleanly, swap it for an unanchored part on a PrismaticConstraint —
	noted here rather than hidden, because the failure only shows up in
	playtest.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Trove = require(Shared:WaitForChild("Trove"))

local SETTINGS = Config.Parkour

local ParkourService = {}

local trove = Trove.new()
local spinning: { [BasePart]: Vector3 } = {}
local crumbling: { [BasePart]: boolean } = {}

local function attribute<T>(part: BasePart, name: string, fallback: T): T
	local value = part:GetAttribute(name)
	if value ~= nil and typeof(value) == typeof(fallback) then
		return value :: any
	end
	return fallback
end

local function playerFromPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character) or nil
end

--[[
	A hard jump feels fair when the landing is forgiving by a fraction of a
	stud and unfair when it is pixel-perfect. The shim is invisible, so the
	player reads the visual edge and lands on the generous one.
]]
local function addLandingForgiveness(part: BasePart)
	if part:FindFirstChild("LandingShim") then
		return
	end

	local pad = SETTINGS.LandingForgivenessStuds
	local shim = Instance.new("Part")
	shim.Name = "LandingShim"
	shim.Size = part.Size + Vector3.new(pad * 2, 0, pad * 2)
	shim.CFrame = part.CFrame
	shim.Transparency = 1
	shim.Anchored = true
	shim.CanCollide = true
	shim.CanQuery = false
	shim.CastShadow = false
	shim.Parent = part

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = shim
	weld.Parent = shim
end

--[[ Obstacles ------------------------------------------------------------ ]]

local function bindMovingPlatform(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	local offset = attribute(part, "MoveOffset", Vector3.new(0, 0, 16))
	local seconds = attribute(part, "MoveSeconds", 3)
	local delay = attribute(part, "MoveDelay", 0)

	part.Anchored = true

	local info = TweenInfo.new(
		seconds,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true,
		delay
	)
	local tween = TweenService:Create(part, info, { CFrame = part.CFrame + offset })
	tween:Play()

	trove:Add(function()
		tween:Cancel()
	end)
end

local function bindCrumblePlatform(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	addLandingForgiveness(part)
	local originalTransparency = part.Transparency

	trove:Connect(part.Touched, function(hit: BasePart)
		if crumbling[part] or not playerFromPart(hit) then
			return
		end
		crumbling[part] = true

		task.spawn(function()
			local warning = TweenService:Create(
				part,
				TweenInfo.new(attribute(part, "CrumbleDelay", SETTINGS.CrumbleDelay)),
				{ Transparency = 0.7 }
			)
			warning:Play()
			warning.Completed:Wait()

			part.CanCollide = false
			part.Transparency = 1
			local shim = part:FindFirstChild("LandingShim")
			if shim and shim:IsA("BasePart") then
				shim.CanCollide = false
			end

			task.wait(attribute(part, "CrumbleRestore", SETTINGS.CrumbleRestore))

			part.CanCollide = true
			part.Transparency = originalTransparency
			if shim and shim:IsA("BasePart") then
				shim.CanCollide = true
			end
			crumbling[part] = nil
		end)
	end)
end

local function bindRotatingBeam(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	part.Anchored = true
	local axis = attribute(part, "SpinAxis", Vector3.yAxis)
	local degrees = attribute(part, "SpinDegreesPerSecond", 45)
	if degrees == 0 or axis.Magnitude == 0 then
		-- .Unit on a zero vector is NaN, which would corrupt the CFrame.
		return
	end
	spinning[part] = axis.Unit * math.rad(degrees)
end

local function bindSwingingVine(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	-- A tweened pivot rather than a RopeConstraint. Rope plus AlignPosition
	-- jitters badly with a character attached; a driven pivot does not.
	part.Anchored = true

	local degrees = attribute(part, "SwingDegrees", SETTINGS.VineSwingDegrees)
	local seconds = attribute(part, "SwingSeconds", SETTINGS.VineSwingSeconds)
	local origin = part.CFrame
	local half = math.rad(degrees) * 0.5

	part.CFrame = origin * CFrame.Angles(-half, 0, 0)

	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(part, info, { CFrame = origin * CFrame.Angles(half, 0, 0) })
	tween:Play()

	trove:Add(function()
		tween:Cancel()
	end)
end

local function bindLaunchPad(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	local impulse = attribute(part, "LaunchImpulse", SETTINGS.LaunchImpulse)
	local direction = attribute(part, "LaunchDirection", Vector3.yAxis)
	local cooling: { [Player]: number } = {}

	trove:Connect(part.Touched, function(hit: BasePart)
		local player = playerFromPart(hit)
		if not player then
			return
		end

		local now = os.clock()
		if cooling[player] and now - cooling[player] < 0.5 then
			return
		end
		cooling[player] = now

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = direction.Unit * impulse
		end
	end)
end

--[[ Lifecycle ------------------------------------------------------------ ]]

local BINDINGS = {
	{ tag = SETTINGS.MovingPlatformTag, bind = bindMovingPlatform },
	{ tag = SETTINGS.CrumblePlatformTag, bind = bindCrumblePlatform },
	{ tag = SETTINGS.RotatingBeamTag, bind = bindRotatingBeam },
	{ tag = SETTINGS.SwingingVineTag, bind = bindSwingingVine },
	{ tag = SETTINGS.LaunchPadTag, bind = bindLaunchPad },
	{ tag = "ForgivingLanding", bind = addLandingForgiveness },
}

function ParkourService.Start()
	for _, binding in BINDINGS do
		for _, instance in CollectionService:GetTagged(binding.tag) do
			binding.bind(instance)
		end
		trove:Connect(CollectionService:GetInstanceAddedSignal(binding.tag), binding.bind)
	end

	trove:Connect(CollectionService:GetInstanceRemovedSignal(SETTINGS.RotatingBeamTag), function(instance)
		if instance:IsA("BasePart") then
			spinning[instance] = nil
		end
	end)

	-- One loop drives every rotating beam. Per-beam connections would be the
	-- same work spread across dozens of handlers.
	trove:Connect(RunService.Heartbeat, function(deltaTime)
		for part, rate in spinning do
			if part.Parent then
				part.CFrame = part.CFrame * CFrame.fromAxisAngle(rate.Unit, rate.Magnitude * deltaTime)
			else
				spinning[part] = nil
			end
		end
	end)
end

function ParkourService.Stop()
	trove:Clean()
	table.clear(spinning)
	table.clear(crumbling)
end

return ParkourService
