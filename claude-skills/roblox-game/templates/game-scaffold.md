# Template: Game Scaffold

The structure everything else assumes.

## Layout

```
default.project.json
src/
  shared/                 -> ReplicatedStorage.Shared
    Config.luau             every tunable, one file
    Types.luau              exported types
    Remotes.luau            get-or-create remote definitions
    Trove.luau              cleanup container
    ObjectPool.luau         instance reuse
  server/                 -> ServerScriptService.Game
    Runtime.server.luau     the ONLY Script; starts services in order
    DataService.luau
    EconomyService.luau
    <Feature>Service.luau
  client/                 -> StarterPlayer.StarterPlayerScripts
    InputController.client.luau
    HudController.client.luau
```

One `Script`. Everything else is a `ModuleScript` with `Start()` and `Stop()`,
started in an explicit order. Implicit load order is a bug waiting for a slow
day.

## Runtime

```luau
--!strict
local services = script.Parent

local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))

-- Order is dependency order, stated once, here.
local START_ORDER = {
    { name = "DataService", service = DataService },
    { name = "EconomyService", service = EconomyService },
}

for _, entry in START_ORDER do
    local ok, err = pcall(entry.service.Start)
    if ok then
        print(`[Game] {entry.name} started`)
    else
        -- One service failing must not take the rest of the game down.
        warn(`[Game] {entry.name} failed to start: {err}`)
    end
end
```

## Service shape

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Trove = require(Shared:WaitForChild("Trove"))

local MyService = {}
local trove = Trove.new()

function MyService.Start()
    trove:Connect(someSignal, handler)
end

function MyService.Stop()
    trove:Clean()
end

return MyService
```

Every connection through the trove. Every tunable from Config. No literals
buried in logic.

## Config

```luau
--!strict
return table.freeze({
    Economy = {
        StartingCoins = 0,
        MaxGrant = 10_000,
        AutosaveSeconds = 90,
    },
    Combat = {
        SwingCooldown = 0.5,
        MaxRange = 20,
    },
})
```

`table.freeze` catches accidental mutation where it happens rather than three
systems later.

## Remotes

Server creates, client waits. A client can then never create a remote the
server does not know about. See the `Remotes` pattern in
`references/multiplayer-networking.md`.

## Tagging over hardcoding

Bind behaviour with `CollectionService` tags and configure per-instance with
attributes. Levels then get authored in Studio without touching code:

```luau
for _, part in CollectionService:GetTagged("Checkpoint") do
    bind(part)
end
trove:Connect(CollectionService:GetInstanceAddedSignal("Checkpoint"), bind)
```

Always handle both the existing tagged instances and the added signal. Handling
only one is a bug that shows up when a level streams in.
