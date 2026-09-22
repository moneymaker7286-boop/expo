--!nonstrict
--[[
	ScatterTool.luau — populate a level with layered vegetation.

	Paste into the Studio Command Bar. DRY_RUN starts true, so the first run only
	reports what it would place.

	What makes a jungle read as a jungle is VERTICAL LAYERING, not tree count.
	A field of trunk-and-ball trees at one height looks like a field of
	lollipops however many you add. This tool places four layers per clump:

	    canopy   overhead, wide, occludes the sky
	    trunk    the mid mass you walk between
	    shrub    waist height, breaks up the floor line
	    debris   ground litter, kills the flat-plane read

	It scatters CLUMPS, not individual plants. Three thousand separate trees is
	how a forest rework ends at 15 FPS; forty clumps of eight read denser and
	cost a fraction.

	Everything it creates goes under one Model, so MODE = "REVERT" is a single
	Destroy and is exact.

	REGION is required: point it at a part whose volume covers the area to fill.
	The tool raycasts down from the region's ceiling to find ground, so it works
	on Terrain and on parts alike.
]]

local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local CONFIG = {
	MODE = "APPLY", -- "APPLY" or "REVERT"
	DRY_RUN = true,

	-- "Jungle" | "Forest" | "Snow"
	PRESET = "Jungle",

	-- REQUIRED. A part whose bounding volume is the area to fill. Make it
	-- invisible and non-collidable; the tool ignores it when raycasting.
	--   REGION = workspace.Stages.Stage2.ScatterRegion
	REGION = nil,

	CLUMPS = 40,
	PLANTS_PER_CLUMP = { 6, 10 },
	CLUMP_SPREAD = 22,

	-- Skip ground steeper than this, so nothing grows off a cliff face.
	MAX_SLOPE_DEGREES = 40,

	-- Perch nodes for MonkeyService, placed in the canopy. Jungle and Forest
	-- only; a snow level has no monkeys.
	TAG_PERCHES = true,
	PERCHES_PER_CLUMP = 2,

	-- Optional folder of real models to use instead of the built-in blocky
	-- stand-ins. Each child is treated as one interchangeable variant.
	--   TEMPLATE_FOLDER = game.ServerStorage.FoliageVariants
	TEMPLATE_FOLDER = nil,

	SEED = 20260922,
}

local PRESETS = {
	Jungle = {
		canopy = { Color3.fromRGB(46, 110, 52), Color3.fromRGB(62, 132, 60), Color3.fromRGB(38, 92, 46) },
		trunk = { Color3.fromRGB(86, 62, 40), Color3.fromRGB(104, 76, 50) },
		shrub = { Color3.fromRGB(64, 138, 66), Color3.fromRGB(88, 158, 74) },
		debris = { Color3.fromRGB(72, 58, 38), Color3.fromRGB(58, 70, 44) },
		canopyMaterial = Enum.Material.LeafyGrass,
		trunkMaterial = Enum.Material.Wood,
		trunkHeight = { 22, 38 },
		canopyLayers = 3,
		canopyRadius = { 9, 15 },
		vines = true,
	},
	Forest = {
		canopy = { Color3.fromRGB(44, 92, 62), Color3.fromRGB(56, 108, 70), Color3.fromRGB(36, 78, 54) },
		trunk = { Color3.fromRGB(78, 56, 38), Color3.fromRGB(96, 70, 46) },
		shrub = { Color3.fromRGB(70, 122, 68), Color3.fromRGB(84, 140, 76) },
		debris = { Color3.fromRGB(80, 64, 42), Color3.fromRGB(96, 86, 60) },
		canopyMaterial = Enum.Material.LeafyGrass,
		trunkMaterial = Enum.Material.Wood,
		trunkHeight = { 26, 46 },
		-- Stacked discs of shrinking radius: a conifer silhouette, which is
		-- what separates a forest read from a jungle one.
		canopyLayers = 4,
		canopyRadius = { 7, 12 },
		vines = false,
	},
	Snow = {
		canopy = { Color3.fromRGB(226, 234, 246), Color3.fromRGB(206, 218, 236), Color3.fromRGB(240, 246, 255) },
		trunk = { Color3.fromRGB(64, 54, 48), Color3.fromRGB(80, 68, 60) },
		shrub = { Color3.fromRGB(214, 226, 240), Color3.fromRGB(232, 240, 250) },
		debris = { Color3.fromRGB(120, 124, 134), Color3.fromRGB(96, 100, 110) },
		canopyMaterial = Enum.Material.Snow,
		trunkMaterial = Enum.Material.Wood,
		trunkHeight = { 18, 32 },
		canopyLayers = 4,
		canopyRadius = { 6, 11 },
		vines = false,
	},
}

local CONTAINER_NAME = "ScatteredFoliage"

--[[ Setup --------------------------------------------------------------- ]]

local preset = PRESETS[CONFIG.PRESET]
assert(preset, ("CONFIG.PRESET %q is not Jungle, Forest or Snow"):format(tostring(CONFIG.PRESET)))

local containerName = ("%s_%s"):format(CONTAINER_NAME, CONFIG.PRESET)
local existing = workspace:FindFirstChild(containerName)

if CONFIG.MODE == "REVERT" then
	if existing then
		local count = #existing:GetDescendants()
		if not CONFIG.DRY_RUN then
			existing:Destroy()
		end
		print(("[Scatter] %s %d instances under %s"):format(
			CONFIG.DRY_RUN and "would remove" or "removed", count, containerName))
	else
		print(("[Scatter] nothing to revert — no %s in Workspace"):format(containerName))
	end
	return
end

local region = CONFIG.REGION
assert(region and region:IsA("BasePart"),
	"CONFIG.REGION must be a BasePart covering the area to fill. Make an invisible, non-collidable part over the level and point REGION at it.")

if existing then
	print(("[Scatter] %s already exists. Run with MODE = \"REVERT\" first, or it will be added to."):format(containerName))
end

local rng = Random.new(CONFIG.SEED)
local dry = CONFIG.DRY_RUN

local stats = { clumps = 0, canopy = 0, trunks = 0, shrubs = 0, debris = 0, vines = 0, perches = 0, misses = 0 }

local templates = nil
if CONFIG.TEMPLATE_FOLDER then
	templates = {}
	for _, child in CONFIG.TEMPLATE_FOLDER:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(templates, child)
		end
	end
	if #templates == 0 then
		templates = nil
		warn("[Scatter] TEMPLATE_FOLDER has no Models or BaseParts — using the built-in stand-ins")
	end
end

local container = existing
if not dry and not container then
	container = Instance.new("Model")
	container.Name = containerName
	container.Parent = workspace
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
rayParams.FilterDescendantsInstances = { region, container or workspace:FindFirstChild(containerName) }

--[[ Primitives ----------------------------------------------------------- ]]

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function newPart(name, size, cframe, color, material, parent, extra)
	if dry then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	-- Foliage must never snag a player mid-parkour.
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	-- Everything set BEFORE Parent: parenting makes the instance live, and
	-- properties written afterwards cost a second replication round and show a
	-- one-frame flash of the default value.
	if extra then
		for property, value in extra do
			part[property] = value
		end
	end

	part.Parent = parent
	return part
end

-- A Cylinder's circular faces sit on its X axis, so standing one upright or
-- laying one flat both mean rotating X to point up.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function newDisc(name, radius, thickness, position, color, material, parent)
	if dry then
		return nil
	end
	return newPart(name, Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(position) * UPRIGHT * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
		color, material, parent,
		{ Shape = Enum.PartType.Cylinder, CastShadow = radius > 6 })
end

local function newColumn(name, radius, height, basePosition, color, material, parent)
	if dry then
		return nil
	end
	return newPart(name, Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(basePosition + Vector3.new(0, height * 0.5, 0)) * UPRIGHT,
		color, material, parent,
		{ Shape = Enum.PartType.Cylinder })
end

--[[ Layers --------------------------------------------------------------- ]]

local function placeTree(origin, clump)
	local height = rng:NextNumber(preset.trunkHeight[1], preset.trunkHeight[2])
	local trunkRadius = height * rng:NextNumber(0.016, 0.028)

	newColumn("Trunk", trunkRadius, height, origin, pick(preset.trunk), preset.trunkMaterial, clump)
	stats.trunks += 1

	-- Canopy: discs of shrinking radius going up. Jungle spreads wide and
	-- flat; Forest tapers to a conifer point.
	local baseRadius = rng:NextNumber(preset.canopyRadius[1], preset.canopyRadius[2])
	local perches = {}

	for layer = 1, preset.canopyLayers do
		local fraction = (layer - 1) / math.max(preset.canopyLayers - 1, 1)
		local radius = baseRadius * (1 - fraction * (CONFIG.PRESET == "Jungle" and 0.35 or 0.75))
		local layerY = height * (0.62 + fraction * 0.38)
		local position = origin + Vector3.new(
			rng:NextNumber(-1.5, 1.5),
			layerY,
			rng:NextNumber(-1.5, 1.5)
		)

		newDisc("Canopy", radius, rng:NextNumber(1.6, 3.2), position, pick(preset.canopy), preset.canopyMaterial, clump)
		stats.canopy += 1

		if layer <= 2 then
			table.insert(perches, position)
		end
	end

	-- Hanging vines. Jungle only, and they are most of why a jungle reads as
	-- one rather than as a tall forest.
	if preset.vines and rng:NextNumber() < 0.6 then
		for _ = 1, rng:NextInteger(1, 3) do
			local length = rng:NextNumber(4, 12)
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(2, baseRadius * 0.8)
			local top = origin + Vector3.new(
				math.cos(angle) * distance,
				height * 0.74 - length * 0.5,
				math.sin(angle) * distance
			)
			newPart("Vine", Vector3.new(0.35, length, 0.35), CFrame.new(top),
				pick(preset.canopy), Enum.Material.Grass, clump)
			stats.vines += 1
		end
	end

	return perches
end

local function placeShrub(origin, clump)
	local radius = rng:NextNumber(1.2, 3.4)
	if not dry then
		newPart("Shrub", Vector3.one * radius * 2,
			CFrame.new(origin + Vector3.new(0, radius * 0.55, 0)),
			pick(preset.shrub), preset.canopyMaterial, clump,
			{ Shape = Enum.PartType.Ball, CastShadow = false })
	end
	stats.shrubs += 1
end

local function placeDebris(origin, clump)
	local size = Vector3.new(rng:NextNumber(1.5, 5), rng:NextNumber(0.2, 0.6), rng:NextNumber(1.5, 5))
	if not dry then
		newPart("Debris", size,
			CFrame.new(origin + Vector3.new(0, size.Y * 0.5, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			pick(preset.debris), Enum.Material.Ground, clump,
			{ CastShadow = false })
	end
	stats.debris += 1
end

local function placeTemplate(origin, clump)
	local template = templates[rng:NextInteger(1, #templates)]
	if dry then
		stats.trunks += 1
		return
	end
	local copy = template:Clone()
	copy.Parent = clump
	if copy:IsA("Model") then
		copy:PivotTo(CFrame.new(origin) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		pcall(function()
			copy:ScaleTo(copy:GetScale() * rng:NextNumber(0.82, 1.35))
		end)
	else
		copy.CFrame = CFrame.new(origin) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	end
	stats.trunks += 1
end

--[[ Scatter -------------------------------------------------------------- ]]

local minCorner = region.Position - region.Size * 0.5
local maxCorner = region.Position + region.Size * 0.5
local rayLength = region.Size.Y + 20
local maxSlope = math.cos(math.rad(CONFIG.MAX_SLOPE_DEGREES))

local recording
if not dry then
	local ok, id = pcall(function()
		return ChangeHistoryService:TryBeginRecording("Scatter", "Scatter foliage")
	end)
	recording = ok and id or nil
end

for _ = 1, CONFIG.CLUMPS do
	local centerX = rng:NextNumber(minCorner.X, maxCorner.X)
	local centerZ = rng:NextNumber(minCorner.Z, maxCorner.Z)
	local origin = Vector3.new(centerX, maxCorner.Y + 10, centerZ)

	local ground = workspace:Raycast(origin, Vector3.new(0, -rayLength, 0), rayParams)
	if not ground or ground.Normal.Y < maxSlope then
		stats.misses += 1
		continue
	end

	local clump = nil
	if not dry then
		clump = Instance.new("Model")
		clump.Name = "Clump"
		clump.Parent = container
	end
	stats.clumps += 1

	local count = rng:NextInteger(CONFIG.PLANTS_PER_CLUMP[1], CONFIG.PLANTS_PER_CLUMP[2])
	local canopyPositions = {}

	for index = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, CONFIG.CLUMP_SPREAD)
		local sampleOrigin = Vector3.new(
			ground.Position.X + math.cos(angle) * distance,
			maxCorner.Y + 10,
			ground.Position.Z + math.sin(angle) * distance
		)

		local spot = workspace:Raycast(sampleOrigin, Vector3.new(0, -rayLength, 0), rayParams)
		if not spot or spot.Normal.Y < maxSlope then
			continue
		end

		if templates then
			placeTemplate(spot.Position, clump)
		elseif index <= math.ceil(count * 0.4) then
			-- Layer split per clump: 40% trees, 35% shrubs, 25% ground litter.
			for _, position in placeTree(spot.Position, clump) do
				table.insert(canopyPositions, position)
			end
		elseif index <= math.ceil(count * 0.75) then
			placeShrub(spot.Position, clump)
		else
			placeDebris(spot.Position, clump)
		end
	end

	-- Perch nodes for MonkeyService, in the canopy where a monkey belongs.
	if CONFIG.TAG_PERCHES and CONFIG.PRESET ~= "Snow" and #canopyPositions > 0 then
		for _ = 1, math.min(CONFIG.PERCHES_PER_CLUMP, #canopyPositions) do
			local position = canopyPositions[rng:NextInteger(1, #canopyPositions)]
			stats.perches += 1
			if not dry then
				local perch = newPart("MonkeyPerch", Vector3.new(2, 0.4, 2),
					CFrame.new(position + Vector3.new(0, 1.2, 0)),
					Color3.fromRGB(92, 66, 44), Enum.Material.Wood, clump,
					{ Transparency = 1, CastShadow = false })
				if perch then
					CollectionService:AddTag(perch, "MonkeyPerch")
				end
			end
		end
	end
end

if not dry and recording then
	pcall(function()
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end)
end

--[[ Report --------------------------------------------------------------- ]]

print(("\n=== Scatter — %s%s ==="):format(CONFIG.PRESET, dry and " (DRY RUN — nothing placed)" or ""))
print(("region: %s"):format(region:GetFullName()))
print(("  %6d  clumps"):format(stats.clumps))
print(("  %6d  canopy discs"):format(stats.canopy))
print(("  %6d  trunks"):format(stats.trunks))
print(("  %6d  shrubs"):format(stats.shrubs))
print(("  %6d  ground debris"):format(stats.debris))
if stats.vines > 0 then
	print(("  %6d  vines"):format(stats.vines))
end
if stats.perches > 0 then
	print(("  %6d  MonkeyPerch nodes tagged"):format(stats.perches))
end
if stats.misses > 0 then
	print(("  %6d  clumps skipped (no ground, or slope over %d degrees)"):format(
		stats.misses, CONFIG.MAX_SLOPE_DEGREES))
end

local total = stats.canopy + stats.trunks + stats.shrubs + stats.debris + stats.vines + stats.perches
print(("\n%d parts total."):format(total))

if dry then
	print("Nothing was placed. Set CONFIG.DRY_RUN = false and run again.")
	if stats.clumps == 0 then
		print("No clumps landed. Check that REGION actually sits above your ground.")
	end
else
	print(("Everything lives under workspace.%s — MODE = \"REVERT\" removes it exactly."):format(containerName))
	print("Run ArtPass next with the matching PRESET to light it.")
end
