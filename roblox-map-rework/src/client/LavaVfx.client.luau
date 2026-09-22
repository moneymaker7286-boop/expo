--!strict
--[[
	Lava presentation. Client-only: nothing here is authoritative, and nothing
	here replicates, so the cost is per-machine and can be scaled per-machine.

	Two rules drive the design:
	  - Lights are POOLED and reassigned to whichever volumes are nearest the
	    camera. A PointLight per volume is what takes a lava level from 60fps
	    to 20 on a mid-range phone.
	  - Flicker runs off ONE shared clock. Per-light randomness reads as a
	    strobe rather than as firelight.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local SETTINGS = Config.Lava
local ASSIGN_INTERVAL = 0.25

local container = Instance.new("Folder")
container.Name = "LavaVfx_Local"
container.Parent = workspace

local lights: { PointLight } = {}
local holders: { BasePart } = {}
local emitters: { [BasePart]: ParticleEmitter } = {}

for index = 1, SETTINGS.LightPoolSize do
	local holder = Instance.new("Part")
	holder.Name = ("LavaLight%d"):format(index)
	holder.Size = Vector3.one
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Parent = container

	local light = Instance.new("PointLight")
	light.Range = SETTINGS.LightRange
	light.Brightness = SETTINGS.LightBrightness
	light.Color = SETTINGS.LightColor
	light.Shadows = false
	light.Enabled = false
	light.Parent = holder

	table.insert(holders, holder)
	table.insert(lights, light)
end

local function emitterFor(volume: BasePart): ParticleEmitter
	local existing = emitters[volume]
	if existing and existing.Parent then
		return existing
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LavaEmbers_Local"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1.6, 3.4)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(18, 18)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 176, 74), Color3.fromRGB(198, 52, 12))
	emitter.LightEmission = 0.85
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(0.35, 0.05)
	emitter.Parent = volume
	emitters[volume] = emitter

	return emitter
end

local function volumesByDistance(): { BasePart }
	local sorted: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(SETTINGS.Tag) do
		if instance:IsA("BasePart") then
			table.insert(sorted, instance)
		end
	end

	local camera = workspace.CurrentCamera
	local origin = camera and camera.CFrame.Position or Vector3.zero
	table.sort(sorted, function(a, b)
		return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude
	end)

	return sorted
end

-- Rolling FPS estimate. Below the threshold the whole dynamic layer is dropped
-- and the lava falls back to its emissive material alone, which still reads.
local estimatedFps = 60
local lowEndMode = false

local assignClock = 0

RunService.RenderStepped:Connect(function(deltaTime: number)
	if deltaTime > 0 then
		estimatedFps += (1 / deltaTime - estimatedFps) * 0.05
	end
	lowEndMode = estimatedFps < SETTINGS.LowEndFpsThreshold

	assignClock += deltaTime
	if assignClock >= ASSIGN_INTERVAL then
		assignClock = 0

		local sorted = volumesByDistance()
		local camera = workspace.CurrentCamera
		local origin = camera and camera.CFrame.Position or Vector3.zero

		for index, holder in holders do
			local volume = sorted[index]
			local light = lights[index]

			if volume and not lowEndMode and (volume.Position - origin).Magnitude <= SETTINGS.VfxRadius then
				holder.Position = volume.Position + Vector3.new(0, volume.Size.Y * 0.5 + 2, 0)
				light.Enabled = true
			else
				light.Enabled = false
			end
		end

		for _, volume in sorted do
			local inRange = not lowEndMode and (volume.Position - origin).Magnitude <= SETTINGS.VfxRadius
			if inRange then
				local emitter = emitterFor(volume)
				emitter.Rate = SETTINGS.EmberRate
			else
				local emitter = emitters[volume]
				if emitter and emitter.Parent then
					emitter.Rate = 0
				end
			end
		end
	end

	if lowEndMode then
		return
	end

	-- One clock, every light. Shared phase is what makes it read as heat
	-- rather than as a fault.
	local pulse = math.sin(os.clock() * math.pi * 2 * SETTINGS.FlickerHz)
	local scale = 1 - SETTINGS.FlickerDepth * (0.5 + 0.5 * pulse)
	local brightness = SETTINGS.LightBrightness * scale

	for _, light in lights do
		if light.Enabled then
			light.Brightness = brightness
		end
	end
end)

CollectionService:GetInstanceRemovedSignal(SETTINGS.Tag):Connect(function(instance)
	if instance:IsA("BasePart") then
		local emitter = emitters[instance]
		if emitter then
			emitter:Destroy()
		end
		emitters[instance] = nil
	end
end)
