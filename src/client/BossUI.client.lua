--[[
	BossUI.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 5: the boss health bar. A Souls-style top-center bar — the boss NAME above a
	wide HP track that depletes as the boss takes damage. Shown when the fight starts,
	hidden on boss death or player death/leave. Driven entirely by the server's
	BossSync remote (visible, name, currentHP, maxHP). Matches the existing HUD style
	(dark, gold name, red fill).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BossSync = Remotes:WaitForChild("BossSync")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(212, 175, 55)
local RED = Color3.fromRGB(150, 30, 28)
local DARK = Color3.fromRGB(16, 16, 18)

----------------------------------------------------------------------
-- Build the bar (hidden until the fight starts)
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BossUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "BossBar"
container.AnchorPoint = Vector2.new(0.5, 0)
container.Position = UDim2.new(0.5, 0, 0, 24)
container.Size = UDim2.new(0, 560, 0, 44)
container.BackgroundTransparency = 1
container.Parent = screenGui

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "BossName"
nameLabel.BackgroundTransparency = 1
nameLabel.Position = UDim2.new(0, 0, 0, 0)
nameLabel.Size = UDim2.new(1, 0, 0, 20)
nameLabel.Font = Enum.Font.GothamMedium
nameLabel.Text = ""
nameLabel.TextSize = 16
nameLabel.TextColor3 = GOLD
nameLabel.TextXAlignment = Enum.TextXAlignment.Center
nameLabel.Parent = container

-- Dark track
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.new(0.5, 0, 0, 24)
track.Size = UDim2.new(1, 0, 0, 14)
track.BackgroundColor3 = DARK
track.BackgroundTransparency = 0.1
track.BorderSizePixel = 0
track.Parent = container

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 2)
trackCorner.Parent = track

-- Red fill whose width tracks currentHP / maxHP
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0)
fill.Position = UDim2.new(0, 0, 0, 0)
fill.Size = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = RED
fill.BorderSizePixel = 0
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 2)
fillCorner.Parent = fill

local FILL_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

----------------------------------------------------------------------
-- React to server boss updates
----------------------------------------------------------------------

BossSync.OnClientEvent:Connect(function(visible, name, hp, maxHp)
	if not visible then
		screenGui.Enabled = false
		return
	end
	screenGui.Enabled = true
	nameLabel.Text = name or ""
	local ratio = (maxHp and maxHp > 0) and math.clamp(hp / maxHp, 0, 1) or 0
	TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
end)
