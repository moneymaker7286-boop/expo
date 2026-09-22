# Tooling Ecosystem

Studio alone is workable for a solo prototype. Anything with version control, a
second developer or a code review step wants external tooling.

## Rojo — filesystem sync

Source of truth moves from the `.rbxl` to files on disk, so Luau lives in git.

```
project/
  default.project.json
  src/
    shared/      -> ReplicatedStorage.Shared
    server/      -> ServerScriptService
    client/      -> StarterPlayer.StarterPlayerScripts
```

```json
{
  "name": "MyGame",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Shared": { "$path": "src/shared" }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "Game": { "$path": "src/server" }
    }
  }
}
```

Filename suffixes decide the instance class: `.server.luau` → `Script`,
`.client.luau` → `LocalScript`, plain `.luau` → `ModuleScript`, and
`init.luau` in a folder makes that folder the module.

`rojo serve` then connect from the Studio plugin. `rojo build -o place.rbxlx`
produces a place file for CI.

## Wally — package management

```toml
[package]
name = "you/yourgame"
version = "0.1.0"
realm = "shared"
registry = "https://github.com/UpliftGames/wally-index"

[dependencies]
ProfileStore = "madstudioroblox/profilestore@1.0.0"
TestEZ = "roblox/testez@0.4.1"
Trove = "sleitnick/trove@1.1.0"
```

`wally install` writes to `Packages/`, which Rojo maps into
`ReplicatedStorage`. Commit `wally.lock`.

## Version control

The binary `.rbxl` does not diff or merge. Two options:

- **Rojo + git** — scripts diff properly; geometry stays in a place file that
  one person owns at a time.
- **`.rbxlx` (XML)** — diffable in principle, unmergeable in practice for
  anything non-trivial, but readable by tools and by a reviewer.

Save as `.rbxlx` rather than `.rbxl` if anything outside Studio needs to read
your place. It is also the only format an external reviewer can audit.

## Static analysis

- **Selene** — Luau linter. Catches undefined globals, unused variables,
  shadowing, deprecated API use.
- **StyLua** — formatter. Removes the entire category of style argument.
- **luau-lsp** — language server for VS Code: types, go-to-definition,
  diagnostics against the Roblox API surface.
- **`luau-analyze`** — the type checker as a CLI. Runs in CI and catches syntax
  and type errors without opening Studio.

A CI job that runs `selene`, `stylua --check` and `luau-analyze` on every push
catches most of what a reviewer would otherwise spend their attention on.

## Open Cloud

REST APIs for what used to need a person in Studio: publishing a place,
reading and writing DataStores from outside, managing user restrictions, and
updating live configuration. Authenticate with an API key or OAuth 2.0, scoped
per resource. Useful for admin panels, external leaderboards and deploy
automation.

## A reasonable setup

| Need | Tool |
| --- | --- |
| Code in git | Rojo |
| Dependencies | Wally |
| Format | StyLua |
| Lint | Selene |
| Types | luau-lsp locally, luau-analyze in CI |
| Tests | TestEZ |
| Persistence | ProfileStore |
| Cleanup | Trove / Janitor |
| Deploy | Open Cloud |
