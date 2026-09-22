--!nonstrict
--[[
	ParkourMetricsRig.luau — measure before you place anything.

	Paste into the Studio Command Bar. It computes what your character can
	actually clear from the live Humanoid values, then builds a labelled row of
	test gaps so you can confirm the number by jumping it.

	Author every gap in the course against this measurement. Eyeballed gaps are
	the single most common reason an obby feels broken.

	Run it again after ANY change to WalkSpeed, JumpPower/JumpHeight or
	Workspace.Gravity — all three move the number.

	Set CLEANUP = true to remove a previously built rig.
]]

local Players = game:GetService("Players")

local CONFIG = {
	CLEANUP = false,
	ORIGIN = nil, -- defaults to 40 studs in front of the camera
	PLATFORM_SIZE = Vector3.new(12, 1, 12),
	GAPS = { 4, 6, 8, 10, 12, 14, 16 },
}

local RIG_NAME = "ParkourMetricsRig"

local existing = workspace:FindFirstChild(RIG_NAME)
if existing then
	existing:Destroy()
	print("[MetricsRig] removed the previous rig")
end
if CONFIG.CLEANUP then
	return
end

--[[ Measurement ---------------------------------------------------------- ]]

-- Read from StarterPlayer so the numbers match what a fresh character spawns
-- with, not whatever the currently loaded test character was left on.
local starterPlayer = game:GetService("StarterPlayer")
local gravity = workspace.Gravity

local walkSpeed = starterPlayer.CharacterWalkSpeed
local useJumpPower = starterPlayer.CharacterUseJumpPower
local jumpHeight

if useJumpPower then
	-- h = v^2 / 2g
	jumpHeight = (starterPlayer.CharacterJumpPower ^ 2) / (2 * gravity)
else
	jumpHeight = starterPlayer.CharacterJumpHeight
end

-- Flat take-off to flat landing: airborne for two symmetric halves.
local airtime = 2 * math.sqrt((2 * jumpHeight) / gravity)
local reach = walkSpeed * airtime

-- The character's own footprint clears a little more than its centre travels.
local footprint = 2
local absoluteMax = reach + footprint

print(("\n=== Parkour metrics ==="))
print(("  gravity            %.1f"):format(gravity))
print(("  walk speed         %.1f studs/s"):format(walkSpeed))
print(("  jump height        %.2f studs"):format(jumpHeight))
print(("  airtime            %.3f s"):format(airtime))
print(("  centre travel      %.2f studs   <- author normal gaps at or under this"):format(reach))
print(("  absolute ceiling   %.2f studs   <- only for a deliberate skill check"):format(absoluteMax))
print("\nGaps beyond the ceiling are not hard, they are impossible. Build the")
print("course on the centre-travel number and keep a margin.\n")

--[[ Rig ------------------------------------------------------------------ ]]

local camera = workspace.CurrentCamera
local origin = CONFIG.ORIGIN
	or (camera and (camera.CFrame.Position + camera.CFrame.LookVector * 40))
	or Vector3.new(0, 20, 0)

local rig = Instance.new("Model")
rig.Name = RIG_NAME

local function platform(position: Vector3, label: string, clearable: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = label
	part.Size = CONFIG.PLATFORM_SIZE
	part.Position = position
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Color = clearable and Color3.fromRGB(86, 158, 96) or Color3.fromRGB(176, 78, 72)
	part.Parent = rig

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Text = label
	text.Parent = billboard

	return part
end

platform(origin, "START", true)

local cursor = origin
for _, gap in CONFIG.GAPS do
	cursor += Vector3.new(CONFIG.PLATFORM_SIZE.X + gap, 0, 0)
	local clearable = gap <= reach
	local label = ("%d studs%s"):format(gap, clearable and "" or "  (over the ceiling)")
	platform(cursor, label, clearable)
end

rig.Parent = workspace

print(("[MetricsRig] built at %s — green is clearable, red is not."):format(tostring(origin)))
print("[MetricsRig] set CONFIG.CLEANUP = true and re-run to remove it.")
