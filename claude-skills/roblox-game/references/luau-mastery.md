# Luau

Luau is Lua 5.1 plus a gradual type system, a different scheduler, and some
syntax Lua does not have. Most Lua answers found online are correct; the ones
about `wait`, `spawn` and types are not.

## Types

```luau
--!strict

type Vector = { x: number, y: number }
type Callback = (number) -> boolean
type Maybe<T> = T?

export type Profile = {
    coins: number,
    inventory: { [string]: number },
    lastSeen: number?,     -- optional field
}

local function total(values: { number }): number
    local sum = 0
    for _, value in values do
        sum += value
    end
    return sum
end
```

Three modes, set per file on the first line:

| Mode | Behaviour | Use for |
| --- | --- | --- |
| `--!nostrict` | Default. Minimal inference. | Legacy files |
| `--!nonstrict` | Flags definite runtime errors | Most gameplay code |
| `--!strict` | Full inference, unknown types are errors | Core systems, modules with an API |

Start new modules at `--!strict`. Escape hatches when the type system loses:
`(value :: any)`, `(value :: Part)`, and `assert(value, "...")` for narrowing.

## Syntax Lua 5.1 does not have

```luau
count += 1                      -- and -=, *=, /=, ..=, //=
local s = `coins: {count}`      -- string interpolation (backticks)
local x = if ready then 1 else 0 -- if-expression
local floor = 7 // 2            -- floor division

-- Generalized iteration: no ipairs/pairs needed
for index, value in myArray do end
for key, value in myDict do end
```

Generalized iteration respects `__iter`. Ordering over a dictionary is still
undefined — if you need deterministic order, build a sorted key array.

## The scheduler

```luau
task.wait(n)        -- not wait(n)
task.spawn(fn)      -- not spawn(fn)
task.delay(n, fn)   -- not delay(n, fn)
task.defer(fn)      -- run at the end of the current resumption cycle
task.cancel(thread)
```

`wait()` and `spawn()` throttle under load and can take far longer than asked
for. `task.defer` is the tool for "after the engine has finished what it is
doing" — repositioning a freshly spawned character, for instance.

## Tables

```luau
table.find(array, value)        -- index or nil
table.clear(t)                  -- empties in place, keeps allocation
table.freeze(t)                 -- shallow immutable; table.isfrozen(t)
table.create(100, 0)            -- preallocate

-- Removing while iterating: go backwards, or you skip elements
for index = #items, 1, -1 do
    if items[index].dead then
        table.remove(items, index)
    end
end
```

`table.freeze` on config tables catches accidental mutation at the point it
happens rather than three systems later.

## Modules

A `ModuleScript` runs once per environment and its return value is cached.
Server and client each get their own copy — a module is **not** a way to share
state across the boundary.

```luau
local M = {}
M.__index = M

export type M = typeof(setmetatable({} :: { value: number }, M))

function M.new(value: number): M
    return setmetatable({ value = value }, M)
end

function M.get(self: M): number
    return self.value
end

return M
```

Declaring methods as `function M.get(self: M)` rather than `function M:get()`
gives the type checker a `self` it understands, while callers still write
`instance:get()`.

## Errors

```luau
local ok, result = pcall(riskyThing, argument)   -- no closure allocation
if not ok then
    warn(`riskyThing failed: {result}`)
end
```

`pcall(fn, args...)` avoids allocating a closure per call — meaningful in a hot
path. Use `xpcall` with `debug.traceback` when you need the stack.

Never swallow an error silently. A `pcall` whose failure branch is empty is a
bug that will be invisible for months.

## Common surprises

- `#t` on a table with holes is undefined. Track length yourself for sparse data.
- `nil` in an array creates a hole. Use `table.remove`, not `t[i] = nil`.
- Strings are interned and immutable; build with `table.concat`, not `..` in a loop.
- `os.clock()` is monotonic and machine-local. `os.time()` is wall-clock UTC.
- Integer division `//` floors toward negative infinity, so `-7 // 2 == -4`.
