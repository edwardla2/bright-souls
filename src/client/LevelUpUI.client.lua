--[[
	LevelUpUI.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 4: the level-up menu, opened from a Site of Grace's "Level Up" prompt. Shows
	the four stats, the player's runes, and the rune cost of the next level; a "+" per
	stat spends runes (server-validated) to raise it. Matches the existing HUD style
	(dark panel, gold accents). The server (PlayerData) is authoritative — this only
	requests level-ups and renders what StatSync / RuneSync send back. The menu closes
	on the X button or when the player walks away from the Grace.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenLevelMenu = Remotes:WaitForChild("OpenLevelMenu")
local StatSync = Remotes:WaitForChild("StatSync")
local RuneSync = Remotes:WaitForChild("RuneSync")
local LevelUpRequest = Remotes:WaitForChild("LevelUpRequest")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(212, 175, 55)
local CREAM = Color3.fromRGB(230, 226, 210)
local DARK = Color3.fromRGB(20, 20, 24)

local STAT_ORDER = { "Vigor", "Endurance", "Strength", "Dexterity" }

-- Local cache, corrected by StatSync.
local stats = {
	Vigor = Config.BASE_STAT,
	Endurance = Config.BASE_STAT,
	Strength = Config.BASE_STAT,
	Dexterity = Config.BASE_STAT,
}
local nextCost = Config.LEVEL_BASE_COST
local runes = 0

local CLOSE_RANGE = 22 -- studs from the open spot; walking past this closes the menu
local openPos = nil

----------------------------------------------------------------------
-- Build the menu (hidden until opened)
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LevelUpUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 320, 0, 300)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 6)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 12)
title.Size = UDim2.new(1, -48, 0, 24)
title.Font = Enum.Font.GothamBold
title.Text = "LEVEL UP"
title.TextSize = 18
title.TextColor3 = GOLD
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local info = Instance.new("TextLabel")
info.Name = "Info"
info.BackgroundTransparency = 1
info.Position = UDim2.new(0, 16, 0, 38)
info.Size = UDim2.new(1, -32, 0, 18)
info.Font = Enum.Font.GothamMedium
info.TextSize = 13
info.TextColor3 = CREAM
info.TextXAlignment = Enum.TextXAlignment.Left
info.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 12)
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.BackgroundTransparency = 1
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Text = "X"
closeBtn.TextSize = 16
closeBtn.TextColor3 = CREAM
closeBtn.Parent = panel

-- Stat rows
local valueLabels = {} -- [statName] = TextLabel
local ROW_Y0 = 70
local ROW_H = 48
for i, statName in ipairs(STAT_ORDER) do
	local y = ROW_Y0 + (i - 1) * ROW_H

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 16, 0, y)
	row.Size = UDim2.new(1, -32, 0, ROW_H - 8)
	row.Parent = panel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.Text = statName
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = CREAM
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.BackgroundTransparency = 1
	valueLabel.Position = UDim2.new(0.55, 0, 0, 0)
	valueLabel.Size = UDim2.new(0.25, 0, 1, 0)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.Text = tostring(stats[statName])
	valueLabel.TextSize = 16
	valueLabel.TextColor3 = GOLD
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = row

	local plusBtn = Instance.new("TextButton")
	plusBtn.Name = "Plus"
	plusBtn.AnchorPoint = Vector2.new(1, 0.5)
	plusBtn.Position = UDim2.new(1, 0, 0.5, 0)
	plusBtn.Size = UDim2.new(0, 34, 0, 28)
	plusBtn.BackgroundColor3 = Color3.fromRGB(45, 42, 30)
	plusBtn.BorderSizePixel = 0
	plusBtn.Font = Enum.Font.GothamBold
	plusBtn.Text = "+"
	plusBtn.TextSize = 18
	plusBtn.TextColor3 = GOLD
	plusBtn.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = plusBtn

	plusBtn.Activated:Connect(function()
		LevelUpRequest:FireServer(statName)
	end)

	valueLabels[statName] = valueLabel
end

----------------------------------------------------------------------
-- Render + open / close
----------------------------------------------------------------------

local function render()
	info.Text = "Runes: " .. runes .. "    Next level: " .. nextCost
	for statName, valueLabel in pairs(valueLabels) do
		valueLabel.Text = tostring(stats[statName])
	end
end

local function openMenu()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	openPos = root and root.Position or nil
	render()
	screenGui.Enabled = true
end

local function closeMenu()
	screenGui.Enabled = false
	openPos = nil
end

OpenLevelMenu.OnClientEvent:Connect(openMenu)
closeBtn.Activated:Connect(closeMenu)

StatSync.OnClientEvent:Connect(function(newStats, cost, newRunes)
	stats = newStats
	nextCost = cost
	runes = newRunes
	render()
end)

-- The rune HUD already listens to RuneSync; mirror it so the open menu stays live.
RuneSync.OnClientEvent:Connect(function(total)
	runes = total
	if screenGui.Enabled then
		render()
	end
end)

-- Walk-away close: while open, if the player moves past CLOSE_RANGE from where they
-- opened it (i.e. leaves the Grace), close the menu.
RunService.Heartbeat:Connect(function()
	if not screenGui.Enabled or not openPos then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - openPos).Magnitude > CLOSE_RANGE then
		closeMenu()
	end
end)
