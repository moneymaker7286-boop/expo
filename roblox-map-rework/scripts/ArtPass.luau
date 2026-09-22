--!nonstrict
--[[
	ArtPass.luau — one-shot art-direction pass.

	Paste into Roblox Studio's Command Bar and press Enter. Nothing is created,
	deleted or overwritten on the first run: DRY_RUN starts true, so the script
	only reports what it would touch. Read the report, then set DRY_RUN = false
	and run it again.

	It does four things, each independently switchable in CONFIG.PHASES:
	  LIGHTING   Atmosphere + post-processing + an off-noon sun.
	  SURFACES   Mutes tiled textures on large floors, smooths stud/inlet faces.
	  MATERIALS  Maps flat Plastic onto real materials by colour.
	  FOLIAGE    Jitters hue, scale and Y-rotation across every tree.

	Every change records the original value as an attribute on the instance, so
	MODE = "REVERT" undoes the pass even after a save-and-reopen. Ctrl+Z also
	works within the session.

	Exempt anything by tagging it "ArtPassIgnore" in the Tags section of the
	Properties panel.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local CONFIG = {
	-- "APPLY" or "REVERT".
	MODE = "APPLY",

	-- Leave true for the first run. The script reports and changes nothing.
	DRY_RUN = true,

	-- Scope. workspace hits everything including the lobby; point this at a
	-- single stage model to rework one area at a time, e.g.
	--   ROOT = workspace.Stages.Stage1
	ROOT = workspace,

	PHASES = {
		LIGHTING = true,
		SURFACES = true,
		MATERIALS = true,
		FOLIAGE = true,
	},

	IGNORE_TAG = "ArtPassIgnore",

	-- A face wider and longer than this counts as a "large floor" for the
	-- texture and surface-smoothing passes.
	MIN_FACE_STUDS = 40,

	-- Material changes alter friction, which changes how jumps land. When true,
	-- the original material's physics are pinned via CustomPhysicalProperties so
	-- only the look changes.
	PRESERVE_PHYSICS = true,

	FOLIAGE_NAME_PATTERNS = { "tree", "bush", "foliage", "plant", "shrub", "leaf", "leaves", "palm" },
	FOLIAGE_SCALE_RANGE = { 0.82, 1.35 },
	FOLIAGE_HUE_JITTER = 0.035,
	FOLIAGE_SAT_JITTER = 0.12,
	FOLIAGE_VAL_JITTER = 0.12,

	-- Fixed seed so a re-run reproduces the same scatter.
	RANDOM_SEED = 20260922,
}

--[[ Lighting ------------------------------------------------------------- ]]

-- Lighting.Technology is not scriptable. The script attempts it, and prints a
-- manual instruction when the engine refuses.
local LIGHTING_PROPS = {
	Ambient = Color3.fromRGB(70, 70, 78),
	OutdoorAmbient = Color3.fromRGB(105, 112, 124),
	Brightness = 2.4,
	ExposureCompensation = 0.15,
	ShadowSoftness = 0.35,
	GlobalShadows = true,
	EnvironmentDiffuseScale = 0.45,
	EnvironmentSpecularScale = 0.35,
	-- 15:20 rather than high noon. Noon is the flattest possible sun angle and
	-- is the single biggest reason a map reads as plastic.
	ClockTime = 15.3,
	GeographicLatitude = 12,
}

local EFFECTS = {
	{
		className = "Atmosphere",
		props = {
			Density = 0.34,
			Offset = 0.15,
			Color = Color3.fromRGB(199, 210, 199),
			Decay = Color3.fromRGB(106, 123, 116),
			Glare = 0.25,
			Haze = 1.6,
		},
	},
	{
		className = "ColorCorrectionEffect",
		props = {
			Brightness = 0.02,
			Contrast = 0.12,
			Saturation = 0.14,
			TintColor = Color3.fromRGB(255, 249, 242),
		},
	},
	{
		className = "SunRaysEffect",
		props = { Intensity = 0.09, Spread = 0.85 },
	},
	{
		className = "BloomEffect",
		props = { Intensity = 0.55, Size = 22, Threshold = 1.1 },
	},
}

--[[ Material mapping ----------------------------------------------------- ]]

-- Only Plastic and SmoothPlastic get remapped. Anything already given a real
-- material was a deliberate choice and is left alone.
local REMAPPABLE = {
	[Enum.Material.Plastic] = true,
	[Enum.Material.SmoothPlastic] = true,
}

local MATERIAL_BY_TONE = {
	green = Enum.Material.LeafyGrass,
	brown = Enum.Material.Ground,
	lightNeutral = Enum.Material.Concrete,
	darkNeutral = Enum.Material.Slate,
	-- Warm tones are reserved for the lava pass and deliberately skipped here.
	warm = nil,
	other = nil,
}

--[[ Helpers -------------------------------------------------------------- ]]

local rng = Random.new(CONFIG.RANDOM_SEED)
local dry = CONFIG.DRY_RUN
local reverting = CONFIG.MODE == "REVERT"

local stats = {}
local function bump(key, by)
	stats[key] = (stats[key] or 0) + (by or 1)
end

local warnings = {}
local function note(message)
	table.insert(warnings, message)
end

local function toneOf(color)
	local h, s, v = color:ToHSV()
	if s < 0.18 then
		return v > 0.62 and "lightNeutral" or "darkNeutral"
	end
	if h >= 0.20 and h <= 0.47 then
		return "green"
	end
	if h >= 0.055 and h < 0.13 then
		return "brown"
	end
	if h < 0.055 or h > 0.94 then
		return "warm"
	end
	return "other"
end

local function isExempt(inst)
	if CollectionService:HasTag(inst, CONFIG.IGNORE_TAG) then
		return true
	end
	-- Never touch player characters or anything parented under Terrain.
	if inst:FindFirstAncestorWhichIsA("Terrain") then
		return true
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function largestFaceArea(part)
	local s = part.Size
	local faces = { s.X * s.Z, s.X * s.Y, s.Y * s.Z }
	table.sort(faces)
	return faces[3]
end

local function looksLikeFoliage(model)
	local name = model.Name:lower()
	for _, pattern in ipairs(CONFIG.FOLIAGE_NAME_PATTERNS) do
		if name:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

--[[ Phase 1 — lighting --------------------------------------------------- ]]

local BACKUP_NAME = "ArtPassLightingBackup"

local function applyLighting()
	local existing = Lighting:FindFirstChild(BACKUP_NAME)

	if reverting then
		if not existing then
			note("No lighting backup found — lighting left as-is.")
			return
		end
		local ok, saved = pcall(HttpService.JSONDecode, HttpService, existing.Value)
		if not ok then
			note("Lighting backup is unreadable — lighting left as-is.")
			return
		end
		if not dry then
			for prop, value in pairs(saved) do
				local assigned = pcall(function()
					if type(value) == "table" then
						Lighting[prop] = Color3.fromRGB(value[1], value[2], value[3])
					else
						Lighting[prop] = value
					end
				end)
				if assigned then
					bump("lightingRestored")
				end
			end
			existing:Destroy()
		else
			bump("lightingRestored", 1)
		end

		for _, inst in ipairs(Lighting:GetChildren()) do
			if inst:GetAttribute("ArtPassCreated") then
				bump("effectsRemoved")
				if not dry then
					inst:Destroy()
				end
			end
		end
		return
	end

	-- Snapshot before the first write so REVERT has something to restore.
	if not existing then
		local snapshot = {}
		for prop in pairs(LIGHTING_PROPS) do
			local value = Lighting[prop]
			if typeof(value) == "Color3" then
				snapshot[prop] = {
					math.floor(value.R * 255 + 0.5),
					math.floor(value.G * 255 + 0.5),
					math.floor(value.B * 255 + 0.5),
				}
			else
				snapshot[prop] = value
			end
		end
		if not dry then
			local holder = Instance.new("StringValue")
			holder.Name = BACKUP_NAME
			holder.Value = HttpService:JSONEncode(snapshot)
			holder:SetAttribute("ArtPassCreated", true)
			holder.Parent = Lighting
		end
		bump("lightingSnapshot")
	end

	for prop, value in pairs(LIGHTING_PROPS) do
		if not dry then
			local ok = pcall(function()
				Lighting[prop] = value
			end)
			if not ok then
				note(("Could not set Lighting.%s"):format(prop))
			end
		end
		bump("lightingProps")
	end

	if not dry then
		local ok = pcall(function()
			Lighting.Technology = Enum.Technology.Future
		end)
		if not ok then
			note("Lighting.Technology is not scriptable — set it to Future by hand: select Lighting in the Explorer, then Technology in the Properties panel. This one matters; the rest of the pass is tuned for it.")
		end
	end

	for _, spec in ipairs(EFFECTS) do
		local inst = Lighting:FindFirstChildOfClass(spec.className)
		local created = false
		if not inst then
			created = true
			if not dry then
				inst = Instance.new(spec.className)
				inst:SetAttribute("ArtPassCreated", true)
				inst.Parent = Lighting
			end
		end
		if inst and not dry then
			for prop, value in pairs(spec.props) do
				pcall(function()
					inst[prop] = value
				end)
			end
		end
		bump(created and "effectsCreated" or "effectsTuned")
	end
end

--[[ Phase 2 — surface noise ---------------------------------------------- ]]

local SURFACE_FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

local function applySurfaces(descendants)
	for _, inst in ipairs(descendants) do
		if not isExempt(inst) then
			-- Tiled textures on big floors. Muted rather than destroyed, so the
			-- asset and its settings survive.
			if inst:IsA("Texture") or inst:IsA("Decal") then
				local part = inst.Parent
				if part and part:IsA("BasePart") and largestFaceArea(part) >= CONFIG.MIN_FACE_STUDS ^ 2 then
					if reverting then
						local orig = inst:GetAttribute("ArtPass_OrigTransparency")
						if orig then
							bump("texturesRestored")
							if not dry then
								inst.Transparency = orig
								inst:SetAttribute("ArtPass_OrigTransparency", nil)
							end
						end
					elseif inst:GetAttribute("ArtPass_OrigTransparency") == nil then
						bump("texturesMuted")
						if not dry then
							inst:SetAttribute("ArtPass_OrigTransparency", inst.Transparency)
							inst.Transparency = 1
						end
					end
				end
			end

			if inst:IsA("Part") and largestFaceArea(inst) >= CONFIG.MIN_FACE_STUDS ^ 2 then
				if reverting then
					local packed = inst:GetAttribute("ArtPass_OrigSurfaces")
					if packed then
						bump("surfacesRestored")
						if not dry then
							local i = 1
							for name in packed:gmatch("[^,]+") do
								pcall(function()
									inst[SURFACE_FACES[i]] = Enum.SurfaceType[name]
								end)
								i += 1
							end
							inst:SetAttribute("ArtPass_OrigSurfaces", nil)
						end
					end
				elseif inst:GetAttribute("ArtPass_OrigSurfaces") == nil then
					local original, needed = {}, false
					for _, face in ipairs(SURFACE_FACES) do
						local surface = inst[face]
						table.insert(original, surface.Name)
						if surface ~= Enum.SurfaceType.Smooth then
							needed = true
						end
					end
					if needed then
						bump("surfacesSmoothed")
						if not dry then
							inst:SetAttribute("ArtPass_OrigSurfaces", table.concat(original, ","))
							for _, face in ipairs(SURFACE_FACES) do
								inst[face] = Enum.SurfaceType.Smooth
							end
						end
					end
				end
			end
		end
	end
end

--[[ Phase 3 — materials -------------------------------------------------- ]]

local function applyMaterials(descendants)
	for _, inst in ipairs(descendants) do
		if inst:IsA("BasePart") and not isExempt(inst) then
			if reverting then
				local origName = inst:GetAttribute("ArtPass_OrigMaterial")
				if origName then
					bump("materialsRestored")
					if not dry then
						pcall(function()
							inst.Material = Enum.Material[origName]
						end)
						if inst:GetAttribute("ArtPass_PinnedPhysics") then
							inst.CustomPhysicalProperties = nil
							inst:SetAttribute("ArtPass_PinnedPhysics", nil)
						end
						inst:SetAttribute("ArtPass_OrigMaterial", nil)
					end
				end
			elseif REMAPPABLE[inst.Material] and inst:GetAttribute("ArtPass_OrigMaterial") == nil then
				-- Unanchored parts are gameplay physics. Left alone.
				if not inst.Anchored then
					bump("materialsSkippedUnanchored")
				else
					local target = MATERIAL_BY_TONE[toneOf(inst.Color)]
					if target then
						bump("materialsMapped")
						if not dry then
							if CONFIG.PRESERVE_PHYSICS and inst.CustomPhysicalProperties == nil then
								inst.CustomPhysicalProperties = PhysicalProperties.new(inst.Material)
								inst:SetAttribute("ArtPass_PinnedPhysics", true)
							end
							inst:SetAttribute("ArtPass_OrigMaterial", inst.Material.Name)
							inst.Material = target
						end
					else
						bump("materialsSkippedTone")
					end
				end
			end
		end
	end
end

--[[ Phase 4 — foliage variation ------------------------------------------ ]]

local function jitterColors(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and not isExempt(part) then
			if reverting then
				local packed = part:GetAttribute("ArtPass_OrigColor")
				if packed then
					if not dry then
						part.Color = Color3.fromRGB(
							tonumber(packed:match("^(%d+)")),
							tonumber(packed:match(",(%d+),")),
							tonumber(packed:match("(%d+)$"))
						)
						part:SetAttribute("ArtPass_OrigColor", nil)
					end
					bump("coloursRestored")
				end
			elseif toneOf(part.Color) == "green" and part:GetAttribute("ArtPass_OrigColor") == nil then
				local h, s, v = part.Color:ToHSV()
				local jittered = Color3.fromHSV(
					(h + rng:NextNumber(-CONFIG.FOLIAGE_HUE_JITTER, CONFIG.FOLIAGE_HUE_JITTER)) % 1,
					math.clamp(s + rng:NextNumber(-CONFIG.FOLIAGE_SAT_JITTER, CONFIG.FOLIAGE_SAT_JITTER), 0, 1),
					math.clamp(v + rng:NextNumber(-CONFIG.FOLIAGE_VAL_JITTER, CONFIG.FOLIAGE_VAL_JITTER), 0, 1)
				)
				if not dry then
					part:SetAttribute("ArtPass_OrigColor", ("%d,%d,%d"):format(
						math.floor(part.Color.R * 255 + 0.5),
						math.floor(part.Color.G * 255 + 0.5),
						math.floor(part.Color.B * 255 + 0.5)
					))
					part.Color = jittered
				end
				bump("coloursJittered")
			end
		end
	end
end

local function hasFoliageAncestor(model, root)
	local parent = model.Parent
	while parent and parent ~= root do
		if parent:IsA("Model") and looksLikeFoliage(parent) then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function applyFoliage(root)
	for _, model in ipairs(root:GetDescendants()) do
		if model:IsA("Model") and looksLikeFoliage(model) and not isExempt(model) and not hasFoliageAncestor(model, root) then
			bump("treesFound")
			jitterColors(model)

			if reverting then
				local origScale = model:GetAttribute("ArtPass_OrigScale")
				local rotApplied = model:GetAttribute("ArtPass_RotApplied")
				if origScale or rotApplied then
					bump("treesRestored")
					if not dry then
						pcall(function()
							if rotApplied then
								model:PivotTo(model:GetPivot() * CFrame.Angles(0, -math.rad(rotApplied), 0))
								model:SetAttribute("ArtPass_RotApplied", nil)
							end
							if origScale then
								model:ScaleTo(origScale)
								model:SetAttribute("ArtPass_OrigScale", nil)
							end
						end)
					end
				end
			elseif model:GetAttribute("ArtPass_OrigScale") == nil then
				local scale = rng:NextNumber(CONFIG.FOLIAGE_SCALE_RANGE[1], CONFIG.FOLIAGE_SCALE_RANGE[2])
				local angle = rng:NextNumber(0, 360)
				if not dry then
					local ok, err = pcall(function()
						model:SetAttribute("ArtPass_OrigScale", model:GetScale())
						model:SetAttribute("ArtPass_RotApplied", angle)
						model:ScaleTo(model:GetScale() * scale)
						model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(angle), 0))
					end)
					if not ok then
						note(("Could not vary %s (%s)"):format(model:GetFullName(), tostring(err)))
						bump("treesFailed")
					else
						bump("treesVaried")
					end
				else
					bump("treesVaried")
				end
			end
		end
	end
end

--[[ Run ------------------------------------------------------------------ ]]

local root = CONFIG.ROOT
assert(root and root:IsA("Instance"), "CONFIG.ROOT is not a valid Instance")

local recording
if not dry then
	local ok, id = pcall(function()
		return ChangeHistoryService:TryBeginRecording("ArtPass", "Art direction pass")
	end)
	recording = ok and id or nil
	if not recording then
		pcall(function()
			ChangeHistoryService:SetWaypoint("Before ArtPass")
		end)
	end
end

local descendants = root:GetDescendants()

if CONFIG.PHASES.LIGHTING then
	applyLighting()
end
if CONFIG.PHASES.SURFACES then
	applySurfaces(descendants)
end
if CONFIG.PHASES.MATERIALS then
	applyMaterials(descendants)
end
if CONFIG.PHASES.FOLIAGE then
	applyFoliage(root)
end

if not dry then
	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end)
	else
		pcall(function()
			ChangeHistoryService:SetWaypoint("After ArtPass")
		end)
	end
end

--[[ Report --------------------------------------------------------------- ]]

local ORDER = {
	{ "lightingProps", "lighting properties set" },
	{ "lightingSnapshot", "lighting snapshot saved" },
	{ "lightingRestored", "lighting properties restored" },
	{ "effectsCreated", "post-processing effects created" },
	{ "effectsTuned", "post-processing effects retuned" },
	{ "effectsRemoved", "post-processing effects removed" },
	{ "texturesMuted", "tiled textures muted on large floors" },
	{ "texturesRestored", "tiled textures restored" },
	{ "surfacesSmoothed", "parts smoothed (studs/inlets removed)" },
	{ "surfacesRestored", "part surfaces restored" },
	{ "materialsMapped", "parts remapped off flat Plastic" },
	{ "materialsRestored", "part materials restored" },
	{ "materialsSkippedUnanchored", "parts skipped (unanchored — gameplay physics)" },
	{ "materialsSkippedTone", "parts skipped (warm tone reserved for the lava pass)" },
	{ "treesFound", "foliage models found" },
	{ "treesVaried", "foliage models given unique scale + rotation" },
	{ "treesRestored", "foliage models restored" },
	{ "treesFailed", "foliage models that could not be varied" },
	{ "coloursJittered", "green parts hue-jittered" },
	{ "coloursRestored", "green part colours restored" },
}

print(("\n=== ArtPass — %s%s ==="):format(CONFIG.MODE, dry and " (DRY RUN — nothing changed)" or ""))
print(("scope: %s"):format(root:GetFullName()))
for _, row in ipairs(ORDER) do
	local count = stats[row[1]]
	if count and count > 0 then
		print(("  %6d  %s"):format(count, row[2]))
	end
end

if #warnings > 0 then
	print("\nnotes:")
	for _, message in ipairs(warnings) do
		print("  - " .. message)
	end
end

if dry then
	print("\nNothing was modified. Set CONFIG.DRY_RUN = false and run again to apply.")
	if (stats.treesFound or 0) == 0 and CONFIG.PHASES.FOLIAGE then
		print("No foliage matched. Add your tree model's name to CONFIG.FOLIAGE_NAME_PATTERNS.")
	end
else
	print("\nCtrl+Z reverts this session. MODE = \"REVERT\" undoes it after a save.")
end
