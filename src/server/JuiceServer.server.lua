--[[
	JuiceServer.server.lua  (ServerScriptService)

	Phase 5.5 (game feel): the impact-feedback layer. Purely additive — it READS the
	existing hit hooks and adds feedback; it never changes damage, detection, stamina,
	dodge, AI decisions, or the economy.

	On a connecting player hit (CombatServer fires the "HitLanded" bindable with the hit
	Humanoid, hit part, and attacker) it stacks:
	  * HITSTOP — briefly anchors the hit entity's HumanoidRootPart. Anchoring (not
	    setting WalkSpeed) is deliberate: the enemy/boss loops re-set WalkSpeed every
	    tick and would instantly undo a WalkSpeed freeze, whereas an anchored root stays
	    put. Restored cleanly after HITSTOP_DURATION.
	  * IMPACT SOUND at the hit part.
	  * WHITE FLASH via a Highlight overlay — it does NOT touch the parts' Color/Material,
	    so it can never clobber the enemy's red telegraph tint (the main correctness risk
	    this design avoids entirely).
	  * HIT SPARK — a cheap neon ball that grows + fades, auto-cleaned.
	  * a small camera shake on the attacker.

	It also fires a bigger camera shake whenever a player TAKES damage (watching each
	player's Humanoid.HealthChanged — covers enemy hits, boss hits, anything).

	Boss roar / heavy-attack shakes are fired from BossAI (those are boss-specific
	moments). Everything here is cheap and cleaned up via Debris.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShakeCamera = Remotes:WaitForChild("ShakeCamera")

local Bindables = ServerStorage:WaitForChild("Bindables")
local HitLanded = Bindables:WaitForChild("HitLanded")

----------------------------------------------------------------------
-- Effects
----------------------------------------------------------------------

local hitstopRoots = {} -- [HumanoidRootPart] = true while frozen (re-entrancy guard)

local function applyHitstop(humanoid)
	local model = humanoid.Parent
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root or hitstopRoots[root] then
		return
	end
	hitstopRoots[root] = true
	local wasAnchored = root.Anchored
	root.Anchored = true
	task.delay(Config.HITSTOP_DURATION, function()
		if root.Parent then
			root.Anchored = wasAnchored
		end
		hitstopRoots[root] = nil
	end)
end

local function playHitSound(hitPart)
	local sound = Instance.new("Sound")
	sound.SoundId = Config.HIT_SOUND_ID
	sound.Volume = Config.HIT_SOUND_VOLUME
	sound.RollOffMaxDistance = 80
	sound.Parent = hitPart
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- White flash via Highlight — overlays the model without modifying any part colours,
-- so it never disturbs the telegraph tint.
local function flashWhite(model)
	if model:FindFirstChild("HitFlash") then
		return -- already flashing
	end
	local hl = Instance.new("Highlight")
	hl.Name = "HitFlash"
	hl.FillColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.25
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.OutlineTransparency = 0.4
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model
	Debris:AddItem(hl, Config.HIT_FLASH_DURATION)
end

local function spawnSpark(position)
	local spark = Instance.new("Part")
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(1.6, 1.6, 1.6)
	spark.Position = position
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.CastShadow = false
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(255, 244, 214)
	spark.Transparency = 0.1
	spark.Parent = workspace
	TweenService:Create(spark, TweenInfo.new(Config.SPARK_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(4.5, 4.5, 4.5),
	}):Play()
	Debris:AddItem(spark, Config.SPARK_LIFETIME + 0.1)
end

----------------------------------------------------------------------
-- Player hit connects -> stack the feedback
----------------------------------------------------------------------

HitLanded.Event:Connect(function(humanoid, hitPart, attacker)
	if not (humanoid and hitPart) then
		return
	end
	applyHitstop(humanoid)
	playHitSound(hitPart)
	local model = humanoid.Parent
	if model then
		flashWhite(model)
	end
	spawnSpark(hitPart.Position)
	if attacker and attacker:IsA("Player") then
		ShakeCamera:FireClient(attacker, Config.SHAKE_DEAL.intensity, Config.SHAKE_DEAL.duration)
	end
end)

----------------------------------------------------------------------
-- Player takes damage (any source) -> bigger shake
----------------------------------------------------------------------

local function watchPlayer(player)
	local function onCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then
			return
		end
		local lastHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(h)
			if h < lastHealth - 0.001 then -- took damage (ignore heals)
				ShakeCamera:FireClient(player, Config.SHAKE_TAKE.intensity, Config.SHAKE_TAKE.duration)
			end
			lastHealth = h
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
