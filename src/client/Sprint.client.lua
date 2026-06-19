--[[
	Sprint.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 5.6a: hold-to-sprint. Client-driven for responsiveness (it sets WalkSpeed
	immediately), but the stamina cost is SERVER-authoritative: this fires the "Sprint"
	remote and CombatServer drains the SAME stamina pool that attacks/dodges use (and
	pauses regen the same way). The client self-regulates off the synced stamina value
	from StaminaSync — so when stamina runs out, it stops on its own.

	Additive: it does not touch the stamina internals, dodge, or any combat logic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Sprint = Remotes:WaitForChild("Sprint")
local StaminaSync = Remotes:WaitForChild("StaminaSync")

local player = Players.LocalPlayer

local keyHeld = false
local sprinting = false
local currentStamina = Config.MAX_STAMINA -- corrected by StaminaSync

local function getHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

StaminaSync.OnClientEvent:Connect(function(stamina)
	currentStamina = stamina
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Config.SPRINT_KEY then
		keyHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.SPRINT_KEY then
		keyHeld = false
	end
end)

-- Evaluate the sprint state each frame. WalkSpeed is set locally (immediate); the
-- Sprint remote only fires on transitions, so traffic stays light.
RunService.Heartbeat:Connect(function()
	local humanoid = getHumanoid()
	if not humanoid then
		sprinting = false
		return
	end

	local moving = humanoid.MoveDirection.Magnitude > 0.05
	-- Higher bar to START than to CONTINUE: can't begin a sprint below SPRINT_MIN, but
	-- once going you may ride it down to empty.
	local threshold = sprinting and 0 or Config.SPRINT_MIN_STAMINA
	local shouldSprint = keyHeld and moving and currentStamina > threshold

	if shouldSprint and not sprinting then
		sprinting = true
		humanoid.WalkSpeed = Config.SPRINT_SPEED
		Sprint:FireServer(true)
	elseif not shouldSprint and sprinting then
		sprinting = false
		humanoid.WalkSpeed = Config.BASE_WALK_SPEED
		Sprint:FireServer(false)
	end
end)
