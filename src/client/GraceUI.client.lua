--[[
	GraceUI.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 3: the brief "Grace Restored" flourish shown when the player rests at a Site
	of Grace. The server (GraceSystem) fires GraceRested; we fade a short line of gold
	text in and out near screen centre. Purely cosmetic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GraceRested = Remotes:WaitForChild("GraceRested")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(212, 175, 55)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GraceUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "GraceText"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.new(0.5, 0, 0.42, 0)
label.Size = UDim2.new(0, 400, 0, 40)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.Text = "Grace Restored"
label.TextSize = 26
label.TextColor3 = GOLD
label.TextTransparency = 1 -- hidden until a rest fires
label.Parent = screenGui

local FADE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

GraceRested.OnClientEvent:Connect(function()
	label.TextTransparency = 1
	TweenService:Create(label, FADE_IN, { TextTransparency = 0 }):Play()
	task.delay(1.4, function()
		TweenService:Create(label, FADE_OUT, { TextTransparency = 1 }):Play()
	end)
end)
