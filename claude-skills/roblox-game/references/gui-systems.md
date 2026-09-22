# GUI Systems

## Where UI lives

`StarterGui` contents clone into each player's `PlayerGui` on spawn. A
`ScreenGui` with `ResetOnSpawn = false` survives respawns — use it for anything
persistent, because rebuilding a HUD every death is both a flicker and a leak
risk if you also reconnect handlers.

## Scaling for every device

The single most common UI failure is a layout built at one aspect ratio.

```luau
-- Scale, not Offset, for anything that should grow with the screen
frame.Size = UDim2.fromScale(0.4, 0.1)

-- UIAspectRatioConstraint keeps a panel's shape across devices
local ratio = Instance.new("UIAspectRatioConstraint")
ratio.AspectRatio = 2
ratio.Parent = frame

-- TextScaled plus a UITextSizeConstraint avoids unreadable extremes
label.TextScaled = true
local bounds = Instance.new("UITextSizeConstraint")
bounds.MaxTextSize = 32
bounds.MinTextSize = 12
bounds.Parent = label
```

Set `ScreenGui.IgnoreGuiInset = true` only when you have accounted for the
Roblox top bar yourself. Keep a safe area: the top-left ~180 × 60 px is the
Roblox menu, and the bottom centre is the mobile jump button.

## Input that works everywhere

```luau
local UserInputService = game:GetService("UserInputService")

local touch = UserInputService.TouchEnabled
local gamepad = UserInputService.GamepadEnabled
local keyboard = UserInputService.KeyboardEnabled
```

Prefer `ContextActionService` over raw input for anything bindable — it gives
you a mobile button and gamepad binding for free:

```luau
ContextActionService:BindAction("Slide", handler, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)
ContextActionService:SetTitle("Slide", "Slide")
```

The `true` is `createTouchButton`. Without it, mobile players cannot use the
ability at all — a very common shipping bug.

## Layout

Use layout objects rather than hand-positioning children:

- `UIListLayout` — stacks, with `Padding` and `SortOrder`
- `UIGridLayout` — inventories, shops
- `UIPadding` — inner margins
- `UICorner`, `UIStroke`, `UIGradient` — styling without images

`UIListLayout` with `AutomaticSize` on the parent gives content-sized panels
without arithmetic.

## Performance

- A `ScreenGui` you are not showing should have `Enabled = false`, not
  transparency 1. Transparent UI still lays out and renders.
- Thousands of `TextLabel`s are slow. Virtualise long lists: render only the
  visible window and recycle frames on scroll.
- `BillboardGui` in world space costs per-instance. Cap how many are alive and
  hide beyond a distance.
- Animate with `TweenService`, not a `RenderStepped` loop writing `Position`.

## Readability rules that matter more than styling

From reviewing real places, in order of how often they are the problem:

1. **Overlapping text.** Two labels sharing screen space with no z-order plan
   reads as broken faster than any geometry problem.
2. **No visual hierarchy.** If six elements all use bold outlined text at the
   same size, none of them is important.
3. **No safe zones.** Text under the Roblox menu or the mobile jump button.
4. **Contrast.** Light text on a light world needs a stroke or a backing plate,
   not a hope.

## Don't build your own chat

`TextChatService` is the supported path and handles filtering, age-group
restrictions and moderation. Custom chat that bypasses
`TextService:FilterStringAsync` is a policy violation, not just a risk.
