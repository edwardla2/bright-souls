--[[
	CombatServer.server.lua  (ServerScriptService)

	Authoritative server for the souls-like combat loop. Responsibilities:
	  * Owns the single source of truth for every player's stamina and i-frame
	    state (clients only display what the server tells them).
	  * Regenerates stamina each Heartbeat, but pauses regen for REGEN_DELAY
	    seconds after any spend so trading blows actually drains the bar.
	  * Resolves ATTACKS with a box overlap query in front of the attacker,
	    damaging each unique humanoid once and skipping anyone with i-frames.
	  * Resolves DODGES by granting i-frames and launching a BodyVelocity burst.

	Clients request actions via RemoteEvents; this script validates stamina and
	is the only place damage / state mutations are allowed to happen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AttackEvent = Remotes:WaitForChild("AttackEvent")
local DodgeEvent = Remotes:WaitForChild("DodgeEvent")
local StaminaSync = Remotes:WaitForChild("StaminaSync")

-- Per-player combat state, keyed by the Player instance.
-- { stamina = number, lastUseTime = number (os.clock), iframes = boolean }
local playerData = {}

-- Phase 5.5 (juice): bindable fired when a player attack connects, so JuiceServer can
-- add hitstop/sound/flash/shake. Assigned below only if ServerStorage exists, so the
-- headless combat test harness (which has none) leaves it nil and stays unaffected.
local HitLanded = nil

-- Per-player stamina cap. Defaults to Config.MAX_STAMINA; PlayerData publishes a
-- higher value via the "MaxStamina" attribute when a player levels Endurance. This
-- is the one concession the stamina system makes to leveling — drain/regen/throttle
-- are otherwise unchanged, and at base Endurance this returns exactly the Config cap.
local function maxStaminaFor(player)
	return player:GetAttribute("MaxStamina") or Config.MAX_STAMINA
end

-- Push the current stamina value down to a player's HUD.
local function syncStamina(player)
	local data = playerData[player]
	if not data then
		return
	end
	-- Throttle: only replicate when the integer stamina value actually changes,
	-- so regen doesn't spam a RemoteEvent every Heartbeat.
	local floored = math.floor(data.stamina)
	if floored == data.lastSentStamina then
		return
	end
	data.lastSentStamina = floored
	StaminaSync:FireClient(player, data.stamina, maxStaminaFor(player))
end

-- Try to spend `amount` stamina. Returns true on success (and starts the regen
-- delay timer + syncs the client), false if the player can't afford it.
local function spendStamina(player, amount)
	local data = playerData[player]
	if not data then
		return false
	end
	if data.stamina < amount then
		return false
	end
	data.stamina = data.stamina - amount
	data.lastUseTime = os.clock()
	syncStamina(player)
	return true
end

Players.PlayerAdded:Connect(function(player)
	playerData[player] = {
		stamina = maxStaminaFor(player),
		lastUseTime = 0,
		iframes = false,
		lastSentStamina = -1,
	}
	syncStamina(player)
end)

Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
end)

-- Stamina regeneration. Runs every frame; only refills once REGEN_DELAY has
-- elapsed since the player's last spend, and syncs the client on every change.
RunService.Heartbeat:Connect(function(dt)
	for player, data in pairs(playerData) do
		local maxStamina = maxStaminaFor(player)
		if data.stamina < maxStamina then
			if os.clock() - data.lastUseTime >= Config.REGEN_DELAY then
				data.stamina = math.min(maxStamina, data.stamina + Config.REGEN_RATE * dt)
				syncStamina(player)
			end
		end
	end
end)

-- ATTACK: spend stamina, wind up 0.18s, then sweep a box in front of the
-- attacker and damage every unique humanoid found (unless it has i-frames).
AttackEvent.OnServerEvent:Connect(function(player)
	if not playerData[player] then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	if not spendStamina(player, Config.ATTACK_COST) then
		return
	end

	-- Wind-up: the hitbox only exists at the moment the swing connects.
	task.wait(0.18)

	-- Re-resolve the character in case the player died / respawned mid-swing.
	character = player.Character
	root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Center the hitbox HITBOX_REACH studs ahead of the root part.
	local hitboxCFrame = root.CFrame * CFrame.new(0, 0, -Config.HITBOX_REACH)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local parts = workspace:GetPartBoundsInBox(hitboxCFrame, Config.HITBOX_SIZE, overlapParams)

	local seen = {} -- de-dupe: a humanoid owns many parts, damage it once
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not seen[humanoid] then
			seen[humanoid] = true

			-- Skip targets that are currently dodging (i-frames active).
			local targetPlayer = Players:GetPlayerFromCharacter(model)
			local targetData = targetPlayer and playerData[targetPlayer]
			if not (targetData and targetData.iframes) then
				-- Phase 2: record who dealt the blow BEFORE damage lands, so if this
				-- is the killing hit the enemy's death (which drops its Runes) is
				-- attributed to the right player. PlayerData reads this LastAttacker
				-- to award runes. Lives on the enemy until it despawns (short-lived).
				local lastAttacker = model:FindFirstChild("LastAttacker")
				if not lastAttacker then
					lastAttacker = Instance.new("ObjectValue")
					lastAttacker.Name = "LastAttacker"
					lastAttacker.Parent = model
				end
				lastAttacker.Value = player

				humanoid:TakeDamage(Config.ATTACK_DAMAGE)

				-- Phase 5.5 (juice): signal the connecting hit so JuiceServer can add
				-- hitstop/sound/flash/spark/shake. Additive — does NOT change the damage
				-- above. Guarded so the test harness (HitLanded == nil) is unaffected.
				if HitLanded then
					HitLanded:Fire(humanoid, part, player)
				end
			end
		end
	end
end)

-- DODGE: spend stamina, grant i-frames, and launch a short BodyVelocity burst
-- in the player's movement direction (falling back to facing direction).
DodgeEvent.OnServerEvent:Connect(function(player)
	local data = playerData[player]
	if not data then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	if not spendStamina(player, Config.DODGE_COST) then
		return
	end

	data.iframes = true

	-- Dodge toward where the player is steering; if standing still, roll backward.
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.05 then
		moveDir = -root.CFrame.LookVector
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.VectorVelocity = moveDir * Config.DODGE_SPEED
	linearVelocity.MaxForce = 1e5
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = root

	-- Hold the dodge for its duration, then clean up and end i-frames.
	task.wait(Config.DODGE_DURATION)

	linearVelocity:Destroy()
	attachment:Destroy()
	data.iframes = false
end)

-- Phase 3 (additive): a Site of Grace can request a full stamina refill on rest.
-- This does NOT change the drain/regen/attack rules above — it only sets stamina to
-- max and syncs, exactly as regen does when it reaches the cap. Guarded so the
-- headless combat test harness (which has no ServerStorage) still loads this script.
local ServerStorage = game:GetService("ServerStorage")
if ServerStorage then
	local Bindables = ServerStorage:WaitForChild("Bindables")
	HitLanded = Bindables:WaitForChild("HitLanded")
	local RefillStamina = Bindables:WaitForChild("RefillStamina")
	RefillStamina.Event:Connect(function(player)
		local data = playerData[player]
		if data then
			data.stamina = maxStaminaFor(player)
			syncStamina(player)
		end
	end)
end
