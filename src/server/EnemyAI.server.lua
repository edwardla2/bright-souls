--[[
	EnemyAI.server.lua  (ServerScriptService)

	Phase 1 of Bright Souls: a single melee enemy that feels great to fight.

	Any Model in the workspace tagged "Enemy" (via CollectionService) that has a
	Humanoid + HumanoidRootPart is adopted as an enemy and driven by the souls-like
	AI state machine below. Each enemy runs its own non-blocking loop (task.spawn +
	task.wait), so one enemy's wind-up wait never freezes the others.

	STATE MACHINE
	  IDLE     → stand at spawn. Player within AGGRO_RANGE → AGGRO.
	  AGGRO /  → chase the nearest living player at CHASE_SPEED.
	  CHASE      • drifted past LEASH_RANGE from spawn (or lost the player) → RETURN
	             • player within ATTACK_RANGE and off cooldown → WINDUP
	             • otherwise MoveTo the player.
	  WINDUP   → stop, face the player, flag "Telegraphing", wait WINDUP_TIME, then
	             deal damage ONLY if the player is still in range (dodge payoff) →
	             back to CHASE.
	  RETURN   → walk home at WALK_SPEED; within 4 studs of spawn → IDLE.
	  DEAD     → on Humanoid.Died: stamp the "Runes" attribute (Phase 2 reads it),
	             wait 3s, despawn, and drop the state entry.

	This file is ADDITIVE. The player's existing attack (CombatServer's
	GetPartBoundsInBox + Humanoid:TakeDamage) already damages any Humanoid, so a
	tagged enemy takes player damage automatically — no damage logic is duplicated
	here. CombatServer / CombatClient / the dodge handler are untouched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)

local ENEMY_TAG = "Enemy"

-- Per-enemy state, keyed by the enemy Model.
-- { state = string, spawnPos = Vector3, target = Model?, lastAttack = number }
local enemies = {}

-- Every model we've already taken over, keyed by the model. Guards against
-- double-adoption when a model arrives through more than one path (e.g. it is
-- BOTH tagged "Enemy" AND named "Rig"), so it only ever gets a single AI loop.
local adopted = {}

-- Find the nearest LIVING player's character to a world position, within reason.
-- Returns (character, distance) or (nil, math.huge) if no valid player exists.
local function getNearestPlayer(originPos)
	local nearestChar, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local dist = (root.Position - originPos).Magnitude
			if dist < nearestDist then
				nearestChar, nearestDist = character, dist
			end
		end
	end
	return nearestChar, nearestDist
end

-- WINDUP telegraph styling. Three stacked cues — neon red, a throbbing pulse, and
-- a slight scale-up — make the wind-up unmistakable against the cold palette.
local TELEGRAPH_BRIGHT = Color3.fromRGB(255, 30, 30) -- peak of the throb
local TELEGRAPH_DARK = Color3.fromRGB(90, 10, 10) -- trough of the throb
local TELEGRAPH_SCALE = 1.15 -- "charging up" enlarge factor

-- Begin the telegraph: glow neon red, scale up, and kick off a concurrent pulse.
-- Each enemy stores its own originals (Color AND Material) and base scale in `data`,
-- so restores are exact and enemies never clobber each other.
local function startTelegraph(model, data)
	local originals = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			originals[part] = { color = part.Color, material = part.Material }
			part.Color = TELEGRAPH_BRIGHT
			part.Material = Enum.Material.Neon
		end
	end
	data.telegraphOriginals = originals

	-- Scale up slightly as a "charging" cue (ScaleTo is exact and reversible).
	if model.ScaleTo then
		data.telegraphScale = model:GetScale()
		model:ScaleTo(data.telegraphScale * TELEGRAPH_SCALE)
	end

	-- Concurrent pulse: throb the red between dark and bright. Runs ALONGSIDE the
	-- authoritative windup wait (never touches its timing) and stops the instant the
	-- flag clears, the enemy dies, or the model despawns — so nothing stays pulsing.
	data.telegraphActive = true
	task.spawn(function()
		local cycles = Config.TELEGRAPH_PULSE_CYCLES or 2
		local omega = (cycles * 2 * math.pi) / math.max(Config.ENEMY_WINDUP_TIME, 0.05) -- throbs/windup (louder = more)
		local startClock = os.clock()
		while data.telegraphActive and model.Parent do
			local t = (math.sin((os.clock() - startClock) * omega) + 1) / 2
			local color = TELEGRAPH_DARK:Lerp(TELEGRAPH_BRIGHT, t)
			if not data.telegraphActive then
				break -- told to stop while we were parked; don't re-tint
			end
			for part in pairs(originals) do
				if part.Parent then
					part.Color = color
				end
			end
			task.wait(0.03)
		end
	end)
end

-- End the telegraph and restore everything exactly: stop the pulse, put back each
-- part's Color + Material, and undo the scale. Safe on a dying/destroyed rig —
-- parts/models that are gone (Parent == nil) are skipped, so it never errors.
local function stopTelegraph(model, data)
	-- Clear the flag FIRST so the pulse can't re-tint after we restore.
	data.telegraphActive = false

	local originals = data.telegraphOriginals
	if originals then
		data.telegraphOriginals = nil
		for part, saved in pairs(originals) do
			if part.Parent then
				part.Color = saved.color
				part.Material = saved.material
			end
		end
	end

	if data.telegraphScale and model.ScaleTo and model.Parent then
		model:ScaleTo(data.telegraphScale)
	end
	data.telegraphScale = nil
end

-- Phase 5.5 (juice): play the windup "tell" sound on the rig at telegraph start.
local function playTelegraphSound(rig)
	local rigRoot = rig:FindFirstChild("HumanoidRootPart")
	if not rigRoot then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = Config.TELEGRAPH_SOUND_ID
	sound.Volume = Config.TELEGRAPH_SOUND_VOLUME
	sound.RollOffMaxDistance = 90
	sound.Parent = rigRoot
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- WINDUP: telegraph then (maybe) connect. Runs inline inside the enemy's loop, so
-- the task.wait below only parks THIS enemy. Returns the enemy to CHASE afterward.
local function performWindup(model, data, humanoid, root)
	-- Plant feet and face the target, Y-locked so the rig doesn't tip over.
	humanoid:MoveTo(root.Position)

	local targetChar = data.target
	local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		local lookAt = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
		root.CFrame = CFrame.new(root.Position, lookAt)
	end

	model:SetAttribute("Telegraphing", true)
	startTelegraph(model, data)
	playTelegraphSound(model)
	task.wait(Config.ENEMY_WINDUP_TIME)

	-- The enemy may have died / despawned during the wind-up.
	if not enemies[model] or humanoid.Health <= 0 then
		stopTelegraph(model, data) -- clear all cues on the dying enemy (guarded against destroyed rig)
		return
	end

	-- Phase 5.6b: poise broke during the wind-up — the swing is interrupted (no hit).
	if os.clock() < (model:GetAttribute("StaggerUntil") or 0) then
		stopTelegraph(model, data)
		model:SetAttribute("Telegraphing", false)
		data.state = "CHASE"
		return
	end

	-- The dodge payoff: re-check the target's CURRENT distance and only land the
	-- hit if they're still in range (+1 stud of slack). Roll out and you take none.
	local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
	local tRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	if targetHum and tRoot and targetHum.Health > 0 then
		local dist = (tRoot.Position - root.Position).Magnitude
		if dist <= Config.ENEMY_ATTACK_RANGE + 1 then
			targetHum:TakeDamage(Config.ENEMY_DAMAGE)
		end
	end

	stopTelegraph(model, data)
	model:SetAttribute("Telegraphing", false)
	data.lastAttack = os.clock()
	if data.state ~= "DEAD" then
		data.state = "CHASE"
	end
end

-- One decision tick for a single enemy.
local function tickEnemy(model, data, humanoid, root)
	if data.state == "DEAD" then
		return
	end

	-- Phase 5.6b poise: freeze in place while staggered; otherwise regenerate poise
	-- once enough time has passed since the last poise hit. This is the only gate the
	-- state machine needs — the decision logic below is untouched.
	if os.clock() < (model:GetAttribute("StaggerUntil") or 0) then
		humanoid:MoveTo(root.Position)
		return
	end
	local poise = model:GetAttribute("Poise")
	if poise then
		local maxPoise = model:GetAttribute("MaxPoise") or Config.ENEMY_MAX_POISE
		if poise < maxPoise and os.clock() - (model:GetAttribute("PoiseHitTime") or 0) >= Config.POISE_REGEN_DELAY then
			model:SetAttribute("Poise", math.min(maxPoise, poise + Config.POISE_REGEN_RATE * 0.1))
		end
	end

	local targetChar, dist = getNearestPlayer(root.Position)
	local distFromSpawn = (root.Position - data.spawnPos).Magnitude

	if data.state == "IDLE" then
		humanoid.WalkSpeed = Config.ENEMY_WALK_SPEED
		if targetChar and dist <= Config.ENEMY_AGGRO_RANGE then
			data.state = "AGGRO"
		end

	elseif data.state == "AGGRO" or data.state == "CHASE" then
		humanoid.WalkSpeed = Config.ENEMY_CHASE_SPEED

		if distFromSpawn > Config.ENEMY_LEASH_RANGE or not targetChar then
			-- Wandered too far from home, or every player is gone/dead — give up.
			data.state = "RETURN"
		elseif dist <= Config.ENEMY_ATTACK_RANGE
			and (os.clock() - data.lastAttack) >= Config.ENEMY_ATTACK_COOLDOWN then
			data.target = targetChar
			data.state = "WINDUP"
			performWindup(model, data, humanoid, root)
		else
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				humanoid:MoveTo(targetRoot.Position)
			end
		end

	elseif data.state == "RETURN" then
		humanoid.WalkSpeed = Config.ENEMY_WALK_SPEED
		humanoid:MoveTo(data.spawnPos)
		if distFromSpawn <= 4 then
			data.state = "IDLE"
		end
	end
end

-- Adopt a tagged Model as an enemy: validate, initialize stats, wire death, and
-- launch its own AI loop.
local function setupEnemy(model)
	if adopted[model] then
		return -- already taken over via some path; never start a second loop
	end
	if not model:IsA("Model") then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return -- not a valid rig; skip per spec (left un-adopted so it can retry)
	end

	adopted[model] = true

	humanoid.MaxHealth = Config.ENEMY_HP
	humanoid.Health = Config.ENEMY_HP
	humanoid.WalkSpeed = Config.ENEMY_WALK_SPEED
	model:SetAttribute("MaxPoise", Config.ENEMY_MAX_POISE) -- Phase 5.6b poise
	model:SetAttribute("Poise", Config.ENEMY_MAX_POISE)

	local data = {
		state = "IDLE",
		spawnPos = root.Position,
		target = nil,
		lastAttack = 0,
	}
	enemies[model] = data

	-- DEATH: drop runes (attribute for now), linger, then despawn + forget.
	humanoid.Died:Once(function()
		data.state = "DEAD"
		model:SetAttribute("Runes", Config.ENEMY_RUNE_REWARD)
		task.wait(3)
		enemies[model] = nil
		adopted[model] = nil
		model:Destroy()
	end)

	-- Per-enemy AI loop. Blocking here (the wind-up wait) only parks this enemy.
	task.spawn(function()
		while enemies[model] and humanoid.Health > 0 do
			tickEnemy(model, data, humanoid, root)
			task.wait(0.1)
		end
	end)
end

-- Adopt every enemy present at server start, and any tagged later at runtime.
for _, model in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
	setupEnemy(model)
end

CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(setupEnemy)

----------------------------------------------------------------------
-- Testing fallback: adopt models named "Rig" too
----------------------------------------------------------------------
-- Convenience so a freshly inserted rig can be fought without opening the Tag
-- Editor. Goes through the SAME setupEnemy path (and the same `adopted` guard),
-- so a rig that is also tagged "Enemy" still only gets one AI loop. The tag-based
-- detection above is unchanged.

local RIG_NAME = "Rig"

local function tryAdoptRig(instance)
	if instance:IsA("Model") and instance.Name == RIG_NAME then
		setupEnemy(instance)
	end
end

-- Rigs already in the workspace at server start (scan descendants so nested
-- rigs are caught too).
for _, instance in ipairs(workspace:GetDescendants()) do
	tryAdoptRig(instance)
end

-- Rigs added during play. ChildAdded covers direct workspace children;
-- DescendantAdded catches deeper nesting. The `adopted` guard dedupes the overlap
-- (a rig parented directly to workspace fires both).
workspace.ChildAdded:Connect(tryAdoptRig)
workspace.DescendantAdded:Connect(tryAdoptRig)
