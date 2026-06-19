--[[
	CombatClient.client.lua  (StarterPlayer.StarterPlayerScripts)

	Client side of the souls-like combat system. Responsibilities:
	  * Builds the combat HUD entirely in code: a "CombatUI" ScreenGui holding a
	    dark stamina track, a gold fill that tweens to match the server value,
	    and a small "STAMINA" caption.
	  * Listens for StaminaSync and animates the fill (turning red when low).
	  * Translates input into action requests — left click = attack, Q = dodge —
	    while gating on the locally-known stamina value, a busy lock, and
	    gameProcessed so typing/UI clicks never trigger combat.

	NOTE: the server is authoritative; this script only predicts affordability to
	avoid firing obviously-invalid requests. Real validation lives on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AttackEvent = Remotes:WaitForChild("AttackEvent")
local HeavyAttack = Remotes:WaitForChild("HeavyAttack")
local DodgeEvent = Remotes:WaitForChild("DodgeEvent")
local StaminaSync = Remotes:WaitForChild("StaminaSync")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Attack animation
----------------------------------------------------------------------
-- The slash track is loaded onto the character's Animator. Because the
-- Animator (and the whole character) is rebuilt every time the player
-- respawns, we re-load the track on each CharacterAdded. `attackTrack` is
-- nil until a character exists, so the input handler guards on it.

local attackTrack -- AnimationTrack for the light attack swing (per-character)

local function setupCharacterAnimation(character)
	local humanoid = character:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator")

	local attackAnim = Instance.new("Animation")
	attackAnim.AnimationId = Config.ATTACK_ANIM_ID

	attackTrack = animator:LoadAnimation(attackAnim)
	attackTrack.Priority = Enum.AnimationPriority.Action
end

-- Run for the character we already have (script may load after spawn), and
-- again on every future respawn.
if player.Character then
	setupCharacterAnimation(player.Character)
end
player.CharacterAdded:Connect(setupCharacterAnimation)

local GOLD = Color3.fromRGB(212, 175, 55)
local RED = Color3.fromRGB(200, 50, 45)
local LOW_THRESHOLD = 0.3 -- fraction of max below which the bar reads "red"

----------------------------------------------------------------------
-- Build the HUD
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CombatUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Dark track, centered horizontally (0.36 .. 0.64) and sitting near the bottom.
local staminaBar = Instance.new("Frame")
staminaBar.Name = "StaminaBar"
staminaBar.AnchorPoint = Vector2.new(0, 0)
staminaBar.Size = UDim2.new(0.28, 0, 0, 18)
staminaBar.Position = UDim2.new(0.36, 0, 1, -50)
staminaBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
staminaBar.BackgroundTransparency = 0.15
staminaBar.BorderSizePixel = 0
staminaBar.Parent = screenGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 4)
barCorner.Parent = staminaBar

-- Gold fill whose Width scale tracks (stamina / max).
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0)
fill.Position = UDim2.new(0, 0, 0, 0)
fill.Size = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = GOLD
fill.BorderSizePixel = 0
fill.Parent = staminaBar

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = fill

-- Small caption sitting just above the track.
local label = Instance.new("TextLabel")
label.Name = "StaminaLabel"
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, 0, 0, 14)
label.Position = UDim2.new(0, 0, 0, -16)
label.Font = Enum.Font.GothamBold
label.Text = "STAMINA"
label.TextSize = 11
label.TextColor3 = Color3.fromRGB(230, 226, 210)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = staminaBar

----------------------------------------------------------------------
-- React to server stamina updates
----------------------------------------------------------------------

local currentStamina = Config.MAX_STAMINA
local maxStamina = Config.MAX_STAMINA
local busy = false -- input lock during an action's recovery window

local FILL_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

StaminaSync.OnClientEvent:Connect(function(stamina, max)
	currentStamina = stamina
	maxStamina = max or Config.MAX_STAMINA

	local ratio = math.clamp(stamina / maxStamina, 0, 1)

	TweenService:Create(fill, FILL_TWEEN, {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()

	fill.BackgroundColor3 = (ratio < LOW_THRESHOLD) and RED or GOLD
end)

----------------------------------------------------------------------
-- Input -> action requests
----------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Ignore clicks/keys consumed by the engine UI, and anything during recovery.
	if gameProcessed or busy then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if currentStamina >= Config.ATTACK_COST then
			busy = true
			AttackEvent:FireServer()
			-- Play the swing locally; speed it up so it fits the 0.55s lock.
			if attackTrack then
				attackTrack:Play()
				attackTrack:AdjustSpeed(1.2)
			end
			task.delay(0.55, function()
				busy = false
			end)
		end
	elseif input.UserInputType == Config.HEAVY_ATTACK_KEY or input.KeyCode == Config.HEAVY_ATTACK_FALLBACK_KEY then
		-- HEAVY: slower swing, longer commit (can't cancel) than light.
		if currentStamina >= Config.HEAVY_ATTACK_COST then
			busy = true
			HeavyAttack:FireServer()
			if attackTrack then
				attackTrack:Play()
				attackTrack:AdjustSpeed(0.6)
			end
			task.delay(Config.HEAVY_ATTACK_WINDUP + 0.7, function()
				busy = false
			end)
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		if currentStamina >= Config.DODGE_COST then
			busy = true
			DodgeEvent:FireServer()
			task.delay(0.65, function()
				busy = false
			end)
		end
	end
end)
