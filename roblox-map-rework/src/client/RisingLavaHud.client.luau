--!strict
--[[
	Rising-lava round HUD: the countdown, the phase line, and the proximity
	warning.

	The warning fires on CLEARANCE, not on a timer. The rise accelerates, so a
	fixed "10 seconds left" lead would arrive too early at the start of a round
	and too late at the end. Studs of lava below your feet is the honest signal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local stateEvent = Remotes.Event("RisingLavaState")

local gui = Instance.new("ScreenGui")
gui.Name = "RisingLavaHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function label(name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Size = size
	text.Position = position
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = textSize
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.35
	text.TextStrokeColor3 = Color3.new(0, 0, 0)
	text.Text = ""
	text.Parent = gui
	return text
end

local timer = label("Timer", UDim2.fromOffset(320, 56), UDim2.new(0.5, 0, 0, 18), 44)
local phaseLine = label("Phase", UDim2.fromOffset(460, 28), UDim2.new(0.5, 0, 0, 74), 18)

local warning = Instance.new("TextLabel")
warning.Name = "Warning"
warning.Size = UDim2.new(1, 0, 0, 46)
warning.Position = UDim2.new(0, 0, 1, -96)
warning.BackgroundColor3 = Color3.fromRGB(122, 26, 10)
warning.BackgroundTransparency = 0.15
warning.BorderSizePixel = 0
warning.Font = Enum.Font.GothamBlack
warning.TextSize = 24
warning.TextColor3 = Color3.fromRGB(255, 226, 190)
warning.Text = "LAVA CLOSING IN"
warning.Visible = false
warning.Parent = gui

local PHASE_TEXT = {
	Idle = "Waiting for players",
	Intermission = "Next round starting",
	Warmup = "Get to high ground",
	Rising = "Escape the rising lava",
	Results = "Round over",
}

local latest: any = nil

stateEvent.OnClientEvent:Connect(function(state)
	latest = state

	timer.Text = ("%.1fs"):format(state.secondsLeft or 0)
	phaseLine.Text = PHASE_TEXT[state.phase] or ""

	if state.phase ~= "Rising" then
		warning.Visible = false
	end
end)

local pulse = TweenService:Create(
	warning,
	TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.55 }
)
pulse:Play()

RunService.RenderStepped:Connect(function()
	local state = latest
	if not state or state.phase ~= "Rising" or not state.surfaceY then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		warning.Visible = false
		return
	end

	local clearance = root.Position.Y - state.surfaceY
	warning.Visible = clearance <= (state.warningStuds or 14)
end)
