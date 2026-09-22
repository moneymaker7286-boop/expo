--!strict
--[[
	Jungle monkeys.

	Three decisions worth knowing about before you tune this:

	1. Traversal uses PERCH NODES, not PathfindingService. Pathfinding through
	   dense jungle clutter is both expensive and produces ground-hugging
	   routes that look nothing like a monkey. Tag parts in the canopy
	   "MonkeyPerch" and agents leap node to node, only touching the ground
	   when they close for a pounce.

	2. One throttled loop thinks for every agent, and at most Config.Monkey
	   .MaxActive of them think at all. Everything beyond that cap is skipped
	   entirely — no per-agent connections, no per-frame work.

	3. The throw telegraph is not optional and has a floor. Untelegraphed
	   ranged damage during a lava jump reads as the game cheating, so the
	   wind-up publishes a "Telegraph" attribute, a tracer and a sound before
	   anything leaves the monkey's hand.

	Art: drop a rig at ServerStorage.MonkeyTemplate and it is used as-is. With
	no template the service builds a blocky stand-in so the system is testable
	before the art exists.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ObjectPool = require(Shared:WaitForChild("ObjectPool"))
local Trove = require(Shared:WaitForChild("Trove"))

local SETTINGS = Config.Monkey
local THINK_INTERVAL = 1 / SETTINGS.ThinkHz

type State = "Sleeping" | "Perched" | "Alert" | "Approach" | "Throwing" | "Pouncing" | "Retreating" | "Dead"

type Agent = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	perches: { BasePart },
	home: BasePart?,
	state: State,
	target: Player?,
	busy: boolean,
	nextThrow: number,
	nextPounce: number,
	enteredAt: number,
	trove: any,
}

local MonkeyService = {}

local agents: { Agent } = {}
local trove = Trove.new()
local monkeyFolder: Folder
local projectilePool: ObjectPool.ObjectPool

local projectileParams = RaycastParams.new()
projectileParams.FilterType = Enum.RaycastFilterType.Exclude
projectileParams.RespectCanCollide = true

--[[ Rig ------------------------------------------------------------------ ]]

local function buildPlaceholderRig(): Model
	local model = Instance.new("Model")
	model.Name = "Monkey"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = Color3.fromRGB(94, 66, 41)
	root.Material = Enum.Material.Sand
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(122, 88, 56)
	head.Material = Enum.Material.Sand
	head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 1
	humanoid.Parent = model

	model.PrimaryPart = root

	return model
end

local function buildProjectileTemplate(): BasePart
	local projectile = Instance.new("Part")
	projectile.Name = "MonkeyThrow"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.one * 0.9
	projectile.Color = Color3.fromRGB(88, 61, 36)
	projectile.Material = Enum.Material.Wood
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.CanTouch = false

	-- A visible trail is part of the telegraph: the player needs to read the
	-- shot's path mid-flight, not just its origin.
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "TrailStart"
	attachment0.Position = Vector3.new(0, 0.3, 0)
	attachment0.Parent = projectile

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TrailEnd"
	attachment1.Position = Vector3.new(0, -0.3, 0)
	attachment1.Parent = projectile

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = 0.35
	trail.LightEmission = 0.3
	trail.Color = ColorSequence.new(Color3.fromRGB(226, 205, 168))
	trail.Parent = projectile

	return projectile
end

--[[ Helpers -------------------------------------------------------------- ]]

local function nearestPlayer(position: Vector3): (Player?, number)
	local best: Player? = nil
	local bestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end

	return best, bestDistance
end

local function targetPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root.Position or nil
end

local function setState(agent: Agent, state: State)
	agent.state = state
	agent.enteredAt = os.clock()
	agent.model:SetAttribute("State", state)
end

local function perchNearest(agent: Agent, position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge

	for _, perch in agent.perches do
		if perch.Parent then
			local distance = (perch.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = perch, distance
			end
		end
	end

	return best
end

-- A leap, not a walk: anchored for the flight with a sine arc, so it reads as
-- swinging between branches.
local function leapTo(agent: Agent, destination: Vector3, seconds: number)
	if agent.busy then
		return
	end
	agent.busy = true

	task.spawn(function()
		local root = agent.root
		if not root.Parent then
			agent.busy = false
			return
		end

		root.Anchored = true
		local from = root.Position
		local peak = math.max((destination - from).Magnitude * 0.22, 3)
		local elapsed = 0

		while elapsed < seconds do
			elapsed += RunService.Heartbeat:Wait()
			if not root.Parent then
				break
			end
			local alpha = math.min(elapsed / seconds, 1)
			local arc = math.sin(alpha * math.pi) * peak
			root.CFrame = CFrame.lookAt(
				from:Lerp(destination, alpha) + Vector3.new(0, arc, 0),
				destination
			)
		end

		agent.busy = false
	end)
end

--[[ Attacks -------------------------------------------------------------- ]]

local function damagePlayerFromPart(part: BasePart, amount: number): boolean
	local character = part:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
		return true
	end

	return false
end

local function launchProjectile(agent: Agent, destination: Vector3)
	local origin = agent.root.Position + Vector3.new(0, 1.8, 0)
	local projectile = projectilePool:Get(monkeyFolder) :: BasePart
	projectile.Position = origin

	projectileParams.FilterDescendantsInstances = { monkeyFolder }

	task.spawn(function()
		local position = origin
		local flat = (destination - origin)
		local travelTime = math.max(flat.Magnitude / SETTINGS.ProjectileSpeed, 0.1)
		-- Lead the arc so the shot lands where it was aimed.
		local velocity = flat / travelTime + Vector3.new(0, 0.5 * workspace.Gravity * travelTime * 0.35, 0)
		local elapsed = 0

		while elapsed < 4 do
			local deltaTime = RunService.Heartbeat:Wait()
			elapsed += deltaTime

			if not projectile.Parent then
				return
			end

			velocity -= Vector3.new(0, workspace.Gravity * 0.35 * deltaTime, 0)
			local step = velocity * deltaTime

			-- Raycast the whole step rather than testing the endpoint, so a
			-- fast shot cannot pass through a player between frames.
			local hit = workspace:Raycast(position, step, projectileParams)
			if hit then
				damagePlayerFromPart(hit.Instance, SETTINGS.ThrowDamage)
				break
			end

			position += step
			projectile.Position = position
		end

		projectilePool:Return(projectile)
	end)
end

local function throwAt(agent: Agent, player: Player)
	if agent.busy then
		return
	end
	agent.busy = true

	task.spawn(function()
		-- Wind-up. The telegraph attribute, the tracer and the sound all fire
		-- BEFORE the projectile exists.
		agent.model:SetAttribute("Telegraph", true)

		local tracer = Instance.new("Beam")
		local fromAttachment = Instance.new("Attachment")
		fromAttachment.Parent = agent.root

		local toAttachment = Instance.new("Attachment")
		local destination = targetPosition(player)
		if not destination then
			fromAttachment:Destroy()
			toAttachment:Destroy()
			agent.model:SetAttribute("Telegraph", false)
			agent.busy = false
			return
		end

		local marker = Instance.new("Part")
		marker.Anchored = true
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Size = Vector3.one
		marker.Position = destination
		marker.Parent = monkeyFolder
		toAttachment.Parent = marker

		tracer.Attachment0 = fromAttachment
		tracer.Attachment1 = toAttachment
		tracer.Width0 = 0.12
		tracer.Width1 = 0.12
		tracer.Color = ColorSequence.new(Color3.fromRGB(255, 226, 148))
		tracer.Transparency = NumberSequence.new(0.35)
		tracer.Parent = agent.root

		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/action_get_up.mp3"
		sound.Volume = 0.6
		sound.RollOffMaxDistance = 120
		sound.Parent = agent.root
		sound:Play()

		task.wait(math.max(SETTINGS.TelegraphSeconds, 0.4))

		tracer:Destroy()
		fromAttachment:Destroy()
		marker:Destroy()
		sound:Destroy()
		agent.model:SetAttribute("Telegraph", false)

		-- Re-aim at the wind-up's end, so strafing during the telegraph
		-- genuinely dodges the shot.
		local finalDestination = targetPosition(player)
		if finalDestination and agent.root.Parent then
			launchProjectile(agent, finalDestination)
		end

		agent.nextThrow = os.clock() + SETTINGS.ThrowCooldown
		agent.busy = false
	end)
end

local function pounceAt(agent: Agent, player: Player)
	local destination = targetPosition(player)
	if not destination or agent.busy then
		return
	end

	agent.model:SetAttribute("Telegraph", true)
	task.spawn(function()
		task.wait(0.35)
		agent.model:SetAttribute("Telegraph", false)

		local landing = targetPosition(player)
		if not landing or not agent.root.Parent then
			return
		end

		leapTo(agent, landing, math.max((landing - agent.root.Position).Magnitude / SETTINGS.PounceSpeed, 0.25))

		-- Contact damage, once, on arrival.
		task.wait(0.3)
		local root = agent.root
		if not root.Parent then
			return
		end

		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { monkeyFolder }

		for _, part in workspace:GetPartBoundsInRadius(root.Position, 4, overlap) do
			if damagePlayerFromPart(part, SETTINGS.PounceDamage) then
				break
			end
		end

		agent.nextPounce = os.clock() + SETTINGS.PounceCooldown
	end)
end

--[[ State machine -------------------------------------------------------- ]]

local function stepAgent(agent: Agent, now: number)
	if agent.state == "Dead" or agent.busy then
		return
	end

	local player, distance = nearestPlayer(agent.root.Position)

	if not player or distance > SETTINGS.DeaggroRadius then
		if agent.state ~= "Perched" and agent.state ~= "Retreating" then
			setState(agent, "Retreating")
		end
	end

	agent.target = player

	if agent.state == "Perched" then
		agent.root.Anchored = true
		if player and distance <= SETTINGS.AggroRadius then
			setState(agent, "Alert")
		end
	elseif agent.state == "Alert" then
		-- A beat of hesitation before committing. Reads as noticing you.
		if now - agent.enteredAt < 0.4 then
			return
		end
		if not player then
			setState(agent, "Retreating")
		elseif distance <= SETTINGS.PounceRange and now >= agent.nextPounce then
			setState(agent, "Pouncing")
			pounceAt(agent, player)
		elseif distance <= SETTINGS.ThrowRange and now >= agent.nextThrow then
			setState(agent, "Throwing")
			throwAt(agent, player)
		else
			setState(agent, "Approach")
		end
	elseif agent.state == "Approach" then
		if not player then
			setState(agent, "Retreating")
			return
		end

		local destination = targetPosition(player)
		if not destination then
			return
		end

		local perch = perchNearest(agent, destination)
		local perchIsCloser = perch
			and (perch.Position - destination).Magnitude < (agent.root.Position - destination).Magnitude - 6

		if perch and perchIsCloser then
			leapTo(agent, perch.Position + Vector3.new(0, 2, 0), 0.55)
		else
			-- Ground closing only. This is the one place a Humanoid walks.
			agent.root.Anchored = false
			agent.humanoid:MoveTo(destination)
		end

		if distance <= SETTINGS.ThrowRange then
			setState(agent, "Alert")
		end
	elseif agent.state == "Throwing" or agent.state == "Pouncing" then
		setState(agent, "Retreating")
	elseif agent.state == "Retreating" then
		local home = agent.home
		if home and home.Parent and (agent.root.Position - home.Position).Magnitude > 4 then
			leapTo(agent, home.Position + Vector3.new(0, 2, 0), 0.6)
		else
			setState(agent, "Perched")
		end
	end
end

--[[ Spawning ------------------------------------------------------------- ]]

local function collectPerches(spawner: BasePart): { BasePart }
	local perches: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(SETTINGS.PerchTag) do
		if instance:IsA("BasePart") and (instance.Position - spawner.Position).Magnitude <= SETTINGS.AggroRadius * 2 then
			table.insert(perches, instance)
		end
	end
	return perches
end

local function spawnAgent(spawner: BasePart, template: Model)
	local model = template:Clone()
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	if not (root and root:IsA("BasePart") and humanoid) then
		warn("[MonkeyService] template needs a Humanoid and a HumanoidRootPart")
		model:Destroy()
		return
	end

	humanoid.MaxHealth = SETTINGS.Health
	humanoid.Health = SETTINGS.Health

	local perches = collectPerches(spawner)
	local home = perches[1]
	model:PivotTo(CFrame.new((home and home.Position or spawner.Position) + Vector3.new(0, 2, 0)))
	model.Parent = monkeyFolder

	local agent: Agent = {
		model = model,
		humanoid = humanoid,
		root = root,
		perches = perches,
		home = home,
		state = "Perched",
		target = nil,
		busy = false,
		nextThrow = 0,
		nextPounce = 0,
		enteredAt = os.clock(),
		trove = Trove.new(),
	}

	agent.trove:Connect(humanoid.Died, function()
		setState(agent, "Dead")
		task.delay(SETTINGS.RespawnSeconds, function()
			local index = table.find(agents, agent)
			if index then
				table.remove(agents, index)
			end
			agent.trove:Clean()
			model:Destroy()
			if spawner.Parent then
				spawnAgent(spawner, template)
			end
		end)
	end)

	table.insert(agents, agent)
	setState(agent, "Perched")
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function MonkeyService.Start()
	monkeyFolder = Instance.new("Folder")
	monkeyFolder.Name = "Monkeys"
	monkeyFolder.Parent = workspace
	trove:Add(monkeyFolder)

	local template = ServerStorage:FindFirstChild("MonkeyTemplate")
	if template and template:IsA("Model") then
		template = template:Clone()
	else
		warn("[MonkeyService] no ServerStorage.MonkeyTemplate — using the blocky stand-in")
		template = buildPlaceholderRig()
	end
	trove:Add(template)

	projectilePool = ObjectPool.new(buildProjectileTemplate(), 8, function(instance)
		local part = instance :: BasePart
		part.CFrame = CFrame.new(0, -500, 0)
	end)
	trove:Add(function()
		projectilePool:Destroy()
	end)

	for _, spawner in CollectionService:GetTagged(SETTINGS.SpawnerTag) do
		if spawner:IsA("BasePart") then
			spawnAgent(spawner, template :: Model)
		end
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(SETTINGS.SpawnerTag), function(spawner)
		if spawner:IsA("BasePart") then
			spawnAgent(spawner, template :: Model)
		end
	end)

	-- ONE loop for every agent, and only the nearest MaxActive of them think.
	local accumulator = 0
	trove:Connect(RunService.Heartbeat, function(deltaTime)
		accumulator += deltaTime
		if accumulator < THINK_INTERVAL then
			return
		end
		accumulator = 0

		local ranked: { { agent: Agent, distance: number } } = {}
		for _, agent in agents do
			if agent.model.Parent and agent.state ~= "Dead" then
				local _, distance = nearestPlayer(agent.root.Position)
				table.insert(ranked, { agent = agent, distance = distance })
			end
		end

		table.sort(ranked, function(a, b)
			return a.distance < b.distance
		end)

		local now = os.clock()
		for index, entry in ranked do
			if index <= SETTINGS.MaxActive and entry.distance <= SETTINGS.DeaggroRadius then
				stepAgent(entry.agent, now)
			elseif entry.agent.state ~= "Sleeping" and entry.agent.state ~= "Perched" then
				-- Beyond the cap an agent is parked, not simulated.
				setState(entry.agent, "Perched")
				entry.agent.root.Anchored = true
			end
		end
	end)
end

function MonkeyService.Stop()
	for _, agent in agents do
		agent.trove:Clean()
	end
	table.clear(agents)
	trove:Clean()
end

return MonkeyService
