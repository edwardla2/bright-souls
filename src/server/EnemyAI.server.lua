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
	task.wait(Config.ENEMY_WINDUP_TIME)

	-- The enemy may have died / despawned during the wind-up.
	if not enemies[model] or humanoid.Health <= 0 then
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
