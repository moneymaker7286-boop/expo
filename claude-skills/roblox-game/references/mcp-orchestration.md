# MCP Orchestration

`SKILL.md` detects one of three modes at invocation. This file is what to do in
each.

## Detecting the mode

Check which tools are actually present before planning any workflow:

| Mode | Signals | Capability |
| --- | --- | --- |
| **full** | `execute_luau`, `get_file_tree`, `grep_scripts`, `create_build` | Run code, browse the tree, search scripts, build |
| **standard** | `run_code`, `insert_model`, `get_console_output`, `start_stop_play` | Run code, insert models, read console, playtest |
| **offline** | none of the above | Code generation and guidance only |

Never assume a mode. If the tool is not in the list, it does not exist, and a
workflow that depends on it must be rewritten rather than attempted.

## A Studio MCP server runs on the same machine as Studio

This constrains things more than people expect. The MCP server bridges Studio
to an MCP client **locally**. A session running in a cloud container cannot
reach a Studio instance on someone's desktop, no matter what is installed in
the container.

So: a cloud session is always **offline mode** with respect to Studio. To get
hands-on in a place, the agent has to be running on the same machine as Studio.
Say this plainly rather than attempting a connection that cannot work.

## Offline mode

The default, and not a degraded one — most valuable work is done here.

- Produce complete, paste-ready scripts, not fragments.
- Say exactly where each script goes (`ServerScriptService`, a `ModuleScript`
  under `ReplicatedStorage.Shared`, a Command Bar one-shot).
- Prefer Command Bar one-shots for bulk edits to an existing place: they need no
  project setup and the user can undo them.
- Make destructive operations dry-runnable by default and reversible after a
  save, since you cannot see the result yourself.
- Ask for a `.rbxlx` export when an audit of the actual place is needed. The
  binary `.rbxl` is opaque; the XML one is readable.

## Standard mode

```
run_code           -- execute Luau in the open place
insert_model       -- pull an asset in by id
get_console_output -- read errors and prints back
start_stop_play    -- enter and leave playtest
```

Loop: write, `run_code`, `get_console_output`, fix, repeat. Actually read the
console after every run — a silent failure looks identical to a success.

Before any bulk change, snapshot what you are about to modify so it can be put
back. You are operating on someone's live place file.

## Full mode

Adds tree browsing and script search, which changes the approach: read the
existing code before writing new code.

```
get_file_tree      -- what exists and where
grep_scripts       -- find every call site before changing an API
execute_luau       -- run
create_build       -- produce a place file
```

`grep_scripts` first, always. Renaming a function without finding its callers is
how a working place stops working.

## Rules that hold in every mode

- Never run a destructive operation without a stated way to undo it.
- Read the console after running code. Assume nothing.
- Report what actually happened, including failures, rather than what was
  intended.
- If a tool is missing, say so and fall back — do not simulate a result.
