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
	-- Keep in sync with Config.Slide. A jump taken out of a slide carries the
	-- slide's horizontal speed, so it has its own reach and its own row.
	SLIDE_SPEED = 48,
	SLIDE_GAPS = { 12, 16, 20, 24, 28, 32 },
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
local slideReach = CONFIG.SLIDE_SPEED * airtime

-- The character's own footprint clears a little more than its centre travels.
local footprint = 2
local absoluteMax = reach + footprint
local slideMax = slideReach + footprint

print(("\n=== Parkour metrics ==="))
print(("  gravity            %.1f"):format(gravity))
print(("  walk speed         %.1f studs/s"):format(walkSpeed))
print(("  slide speed        %.1f studs/s"):format(CONFIG.SLIDE_SPEED))
print(("  jump height        %.2f studs"):format(jumpHeight))
print(("  airtime            %.3f s"):format(airtime))
print("")
print(("  WALK  centre travel   %.2f studs   <- normal gaps at or under this"):format(reach))
print(("  WALK  ceiling         %.2f studs"):format(absoluteMax))
print(("  SLIDE centre travel   %.2f studs   <- slide-required gaps"):format(slideReach))
print(("  SLIDE ceiling         %.2f studs"):format(slideMax))
print("")
print(("  dead zone             %.2f - %.2f studs"):format(absoluteMax, slideReach))
print("")
print("Read the dead zone carefully. A gap in that band cannot be walked and")
print("does not need the slide either -- players will fall, retry, and blame")
print("the game rather than learn the mechanic. Put every gap decisively on")
print("one side, and SIGNAL which side it is: give slide-required jumps their")
print("own platform colour so the requirement is readable before the leap.")
print("")

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

-- Row one: walk jumps. Row two, offset in Z, is the slide row.
platform(origin, "WALK START", true)

local cursor = origin
for _, gap in CONFIG.GAPS do
	cursor += Vector3.new(CONFIG.PLATFORM_SIZE.X + gap, 0, 0)
	local clearable = gap <= reach
	local label = ("%d studs%s"):format(gap, clearable and "" or "  (needs slide)")
	platform(cursor, label, clearable)
end

local slideOrigin = origin + Vector3.new(0, 0, CONFIG.PLATFORM_SIZE.Z + 24)
platform(slideOrigin, "SLIDE START", true)

cursor = slideOrigin
for _, gap in CONFIG.SLIDE_GAPS do
	cursor += Vector3.new(CONFIG.PLATFORM_SIZE.X + gap, 0, 0)
	local clearable = gap <= slideReach
	local label = ("%d studs%s"):format(gap, clearable and "  (slide)" or "  (impossible)")
	platform(cursor, label, clearable)
end

rig.Parent = workspace

print(("[MetricsRig] built at %s — green is clearable, red is not."):format(tostring(origin)))
print("[MetricsRig] set CONFIG.CLEANUP = true and re-run to remove it.")
