--[[
	FlaskUI.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 3 HUD: the Ember Flask charge indicator + drink input. Built in code in the
	same style as the stamina and rune HUDs (dark plate, gold-on-dark, GothamBold),
	anchored bottom-left. Press FLASK_KEY to drink; the server (FlaskSystem) owns the
	actual charges and the heal — this only displays the count and requests drinks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FlaskDrink = Remotes:WaitForChild("FlaskDrink")
local FlaskSync = Remotes:WaitForChild("FlaskSync")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(212, 175, 55)
local DIM = Color3.fromRGB(110, 95, 55) -- empty / no charges

local charges = Config.FLASK_MAX_CHARGES
local drinking = false -- local input lock, mirroring the attack/dodge busy flag

----------------------------------------------------------------------
-- Build the HUD (bottom-left)
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlaskUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "FlaskCounter"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 24, 1, -24)
container.Size = UDim2.new(0, 150, 0, 44)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
container.BackgroundTransparency = 0.15
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = container

local caption = Instance.new("TextLabel")
caption.Name = "FlaskCaption"
caption.BackgroundTransparency = 1
caption.Size = UDim2.new(1, -16, 0, 12)
caption.Position = UDim2.new(0, 8, 0, 4)
caption.Font = Enum.Font.GothamBold
caption.Text = "EMBER FLASK"
caption.TextSize = 10
caption.TextColor3 = Color3.fromRGB(230, 226, 210)
caption.TextXAlignment = Enum.TextXAlignment.Left
caption.TextYAlignment = Enum.TextYAlignment.Top
caption.Parent = container

local countLabel = Instance.new("TextLabel")
countLabel.Name = "FlaskCount"
countLabel.BackgroundTransparency = 1
countLabel.Size = UDim2.new(1, -16, 1, -6)
countLabel.Position = UDim2.new(0, 8, 0, 4)
countLabel.Font = Enum.Font.GothamBold
countLabel.Text = "x" .. charges
countLabel.TextSize = 20
countLabel.TextColor3 = GOLD
countLabel.TextXAlignment = Enum.TextXAlignment.Right
countLabel.TextYAlignment = Enum.TextYAlignment.Bottom
countLabel.Parent = container

local function render()
	countLabel.Text = "x" .. charges
	countLabel.TextColor3 = (charges > 0) and GOLD or DIM
end

----------------------------------------------------------------------
-- Server sync + drink input
----------------------------------------------------------------------

FlaskSync.OnClientEvent:Connect(function(current, _max)
	charges = current
	render()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Ignore keys consumed by the engine UI, and anything while a drink is locked.
	if gameProcessed or drinking then
		return
	end
	if input.KeyCode == Config.FLASK_KEY then
		if charges <= 0 then
			return -- predict affordability; the server validates for real
		end
		drinking = true
		FlaskDrink:FireServer()
		task.delay(Config.FLASK_DRINK_TIME, function()
			drinking = false
		end)
	end
end)
