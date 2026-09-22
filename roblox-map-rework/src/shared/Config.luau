--!strict
--[[
	Every tunable for the stage rework lives here. Nothing else in the project
	hardcodes a number, so retuning difficulty or performance is a one-file edit.
]]

export type LavaDamageMode = "Sink" | "Instant" | "DoT"

return {
	Lava = {
		Tag = "LavaVolume",

		-- Contact is resolved by a bounds query rather than .Touched, because
		-- .Touched tunnels at run speed and lets players cross lava untouched.
		ScanHz = 10,
		-- Volumes further than this from every player are skipped entirely.
		ActiveRadius = 180,

		-- A clipped toe should not be fatal. Contact must persist this long.
		GraceSeconds = 0.35,

		DamageMode = "Sink" :: LavaDamageMode,
		SinkSeconds = 0.9,
		SinkDepth = 7,
		DoTPerSecond = 34,

		-- Client VFX. Lights are pooled and reassigned to the nearest volumes
		-- rather than created per volume, which is what kills low-end framerate.
		LightPoolSize = 8,
		LightRange = 38,
		LightBrightness = 2.6,
		LightColor = Color3.fromRGB(255, 126, 38),
		FlickerHz = 6.5,
		FlickerDepth = 0.22,
		VfxRadius = 140,
		EmberRate = 6,
		-- Below this client FPS the VFX tier drops to static emissive, no lights.
		LowEndFpsThreshold = 35,
	},

	--[[
		Rising lava is a DIFFERENT MODE from the Lava table above, not a
		variant of it. Static lava is a hazard in a checkpointed parkour
		level: it forgives a clipped toe and sends you back a checkpoint.
		Rising lava is an elimination race: contact ends your round, there is
		no grace window, and checkpoints do not apply. Sharing one damage
		path between them would make one of the two feel wrong.
	]]
	RisingLava = {
		Tag = "RisingLava",

		IntermissionSeconds = 12,
		WarmupSeconds = 5,
		RoundSeconds = 150,
		MinPlayers = 1,

		-- Starts gentle and ramps, so the last thirty seconds are the tense
		-- ones rather than the whole round being a flat climb.
		RiseStudsPerSecond = 0.8,
		RiseAcceleration = 0.012,

		-- Lead time on the "LAVA CLOSING IN" banner, measured in studs of
		-- clearance below the player rather than seconds, because the rise
		-- rate changes.
		WarningClearanceStuds = 14,

		BroadcastHz = 4,
	},

	--[[
		The slide. Note what this does to the parkour gap grid: a jump taken
		out of a slide carries the slide's horizontal speed, so reach scales
		with Speed rather than WalkSpeed. At these values that is roughly
		three times a standing jump. Every gap therefore has to be authored
		as either walk-clearable or slide-required, and SIGNALLED to the
		player, or it reads as inconsistent.
	]]
	Slide = {
		Key = Enum.KeyCode.LeftShift,
		GamepadKey = Enum.KeyCode.ButtonL2,
		Speed = 48,
		Seconds = 0.55,
		Cooldown = 1.6,
		-- A slide is only available with your feet on the ground; an air-dash
		-- is a different ability and breaks the gap math further.
		RequireGrounded = true,
	},

	Checkpoint = {
		Tag = "Checkpoint",
		-- Studs above the checkpoint part to place the character on respawn.
		SpawnHeight = 4,
		RespawnDelay = 0.6,
	},

	Monkey = {
		SpawnerTag = "MonkeySpawner",
		PerchTag = "MonkeyPerch",
		-- Hard cap on simultaneously thinking monkeys. Everything else sleeps.
		MaxActive = 8,
		AggroRadius = 90,
		DeaggroRadius = 130,
		ThinkHz = 5,

		-- A throw the player cannot see coming reads as cheating, so the
		-- wind-up is mandatory and is never shorter than this.
		TelegraphSeconds = 0.75,
		ThrowCooldown = 3.2,
		ThrowRange = 85,
		ThrowDamage = 12,
		ProjectileSpeed = 70,

		PounceRange = 22,
		PounceCooldown = 4.5,
		PounceDamage = 18,
		PounceSpeed = 55,

		Health = 45,
		RespawnSeconds = 12,
		PoolSize = 12,
	},

	Parkour = {
		-- Authored against a measured jump, never eyeballed. Run
		-- scripts/ParkourMetricsRig.luau in Studio to re-measure after any
		-- change to WalkSpeed, JumpHeight or gravity.
		GapGridStuds = { 4, 6, 8, 10, 12, 14 },

		MovingPlatformTag = "MovingPlatform",
		CrumblePlatformTag = "CrumblePlatform",
		RotatingBeamTag = "RotatingBeam",
		SwingingVineTag = "SwingingVine",
		LaunchPadTag = "LaunchPad",

		CrumbleDelay = 0.45,
		CrumbleRestore = 3.0,
		LaunchImpulse = 110,
		VineSwingSeconds = 2.4,
		VineSwingDegrees = 55,

		-- Landing collision slightly wider than the visual. The standard trick
		-- for making a hard jump feel fair instead of pixel-perfect.
		LandingForgivenessStuds = 0.6,
	},
}
