--[[
	RuneUI.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 2 HUD: a rune counter. Built entirely in code, in the same style as the
	CombatUI stamina bar (dark plate, gold-on-dark, GothamBold). Sits in the
	bottom-right corner and updates whenever the server fires RuneSync with the
	player's new rune total.

	Display only — the server (PlayerData) is authoritative for the actual count.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RuneSync = Remotes:WaitForChild("RuneSync")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(212, 175, 55)

----------------------------------------------------------------------
-- Build the HUD
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RuneUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Dark plate anchored to the bottom-right.
local container = Instance.new("Frame")
container.Name = "RuneCounter"
container.AnchorPoint = Vector2.new(1, 1)
container.Position = UDim2.new(1, -24, 1, -24)
container.Size = UDim2.new(0, 150, 0, 44)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
container.BackgroundTransparency = 0.15
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = container

-- Small caption, top-left of the plate.
local caption = Instance.new("TextLabel")
caption.Name = "RuneCaption"
caption.BackgroundTransparency = 1
caption.Size = UDim2.new(1, -16, 0, 12)
caption.Position = UDim2.new(0, 8, 0, 4)
caption.Font = Enum.Font.GothamBold
caption.Text = "RUNES"
caption.TextSize = 10
caption.TextColor3 = Color3.fromRGB(230, 226, 210)
caption.TextXAlignment = Enum.TextXAlignment.Left
caption.TextYAlignment = Enum.TextYAlignment.Top
caption.Parent = container

-- The count, large and gold, right-aligned.
local countLabel = Instance.new("TextLabel")
countLabel.Name = "RuneCount"
countLabel.BackgroundTransparency = 1
countLabel.Size = UDim2.new(1, -16, 1, -6)
countLabel.Position = UDim2.new(0, 8, 0, 4)
countLabel.Font = Enum.Font.GothamBold
countLabel.Text = "0"
countLabel.TextSize = 20
countLabel.TextColor3 = GOLD
countLabel.TextXAlignment = Enum.TextXAlignment.Right
countLabel.TextYAlignment = Enum.TextYAlignment.Bottom
countLabel.Parent = container

----------------------------------------------------------------------
-- React to server rune updates
----------------------------------------------------------------------

RuneSync.OnClientEvent:Connect(function(total)
	countLabel.Text = tostring(total)
end)
