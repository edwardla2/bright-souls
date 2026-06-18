--[[
	BossAI.server.lua  (ServerScriptService)

	Phase 5 of Bright Souls: the first boss, The Tide-Drowned Knight. A boss is a
	souped-up enemy — it follows the SAME structural patterns as EnemyAI (per-entity
	state, telegraph -> attack -> recovery) but is its own system so EnemyAI stays
	untouched. It adds: multiple attack patterns, readable punish windows, a phase
	transition at 50% HP, a fog gate that commits you to the arena, and a boss health
	bar. The fog gate is folded in here (the prompt allows it) to avoid cross-script
	activation wiring.

	Reuse, not rewrite, of existing systems:
	  * Rune reward: CombatServer already stamps a "LastAttacker" ObjectValue on the
	    boss when a player hits it, and PlayerData already watches that + the model's
	    "Runes" attribute. So on death we just set "Runes" = BOSS_RUNE_REWARD and the
	    existing Phase 2 path pays the killer — no duplicated award logic.
	  * Dodge i-frames: a dodging player carries a LinearVelocity on their HRP for
	    exactly the i-frame window (CombatServer creates/destroys it alongside the
	    iframes flag). We treat its presence as "i-framing" so a well-timed roll avoids
	    boss damage, WITHOUT reaching into CombatServer's private state or altering the
	    dodge handler.
	  * Telegraph: re-implemented locally in the same red-neon style as EnemyAI so it
	    reads consistently (EnemyAI's helpers are private to that script).

	The boss must be tagged "Boss" (NOT "Enemy") and named something other than "Rig",
	so neither EnemyAI nor the Grace enemy-respawn picks it up. GraceSystem also
	explicitly excludes "Boss"-tagged models from its respawn snapshot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BossSync = Remotes:WaitForChild("BossSync")
local ShakeCamera = Remotes:WaitForChild("ShakeCamera")

local BOSS_TAG = "Boss"
local FOGGATE_TAG = "FogGate"
local BOSS_NAME = "The Tide-Drowned Knight"

local TELEGRAPH_COLOR = Color3.fromRGB(255, 30, 30)
local TELEGRAPH_SCALE = 1.12
local ROAR_TIME = 1.5 -- invulnerable phase-2 transition beat

-- Per-boss state, keyed by the boss Model.
-- { model, humanoid, root, active, state, phase, phase2Triggered, lastAttack, spawnCFrame }
local bosses = {}

-- One active arena fight at a time (MVP: a single boss + gate).
local fightActive = false
local bossDefeated = false
local fightPlayerDiedConn = nil
local fogGates = {} -- BasePart fog gates

----------------------------------------------------------------------
-- Low-level helpers
----------------------------------------------------------------------

local function getNearestPlayer(originPos, maxRange)
	local nearestChar, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local dist = (root.Position - originPos).Magnitude
			if dist < nearestDist and dist <= maxRange then
				nearestChar, nearestDist = character, dist
			end
		end
	end
	return nearestChar, nearestDist
end

-- See the header note: a LinearVelocity on the HRP means the player is mid-dodge.
local function isIFraming(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:FindFirstChildOfClass("LinearVelocity") ~= nil
end

local function startTelegraph(boss)
	local originals = {}
	for _, part in ipairs(boss.model:GetDescendants()) do
		if part:IsA("BasePart") then
			originals[part] = { color = part.Color, material = part.Material }
			part.Color = TELEGRAPH_COLOR
			part.Material = Enum.Material.Neon
		end
	end
	boss.telegraphOriginals = originals
	if boss.model.ScaleTo then
		boss.telegraphScale = boss.model:GetScale()
		boss.model:ScaleTo(boss.telegraphScale * TELEGRAPH_SCALE)
	end
end

local function stopTelegraph(boss)
	local originals = boss.telegraphOriginals
	if originals then
		boss.telegraphOriginals = nil
		for part, saved in pairs(originals) do
			if part.Parent then
				part.Color = saved.color
				part.Material = saved.material
			end
		end
	end
	if boss.telegraphScale and boss.model.ScaleTo and boss.model.Parent then
		boss.model:ScaleTo(boss.telegraphScale)
	end
	boss.telegraphScale = nil
end

local function faceTarget(boss, targetRoot)
	local lookAt = Vector3.new(targetRoot.Position.X, boss.root.Position.Y, targetRoot.Position.Z)
	boss.root.CFrame = CFrame.new(boss.root.Position, lookAt)
end

local function showBossBar(hp, maxHp)
	BossSync:FireAllClients(true, BOSS_NAME, math.max(hp, 0), maxHp)
end

local function hideBossBar()
	BossSync:FireAllClients(false)
end

-- Phase 5.5 (juice): the windup "tell" sound on the boss rig at telegraph start.
local function playTelegraphSound(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = Config.TELEGRAPH_SOUND_ID
	sound.Volume = Config.TELEGRAPH_SOUND_VOLUME
	sound.RollOffMaxDistance = 120
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 3)
end

----------------------------------------------------------------------
-- Attacks
----------------------------------------------------------------------

local function chooseAttack(dist)
	if dist > Config.BOSS_ATTACK_RANGE then
		return "Lunge" -- only the lunge reaches from here; use it to close distance
	end
	local pool = { "Overhead", "Sweep", "Lunge" }
	return pool[math.random(#pool)]
end

-- Sweep a box in front of the boss; damage any LIVING player that isn't i-framing.
local function doHit(boss, atk)
	local hitboxCFrame = boss.root.CFrame * CFrame.new(0, 0, -(atk.range / 2))
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { boss.model }

	local parts = workspace:GetPartBoundsInBox(hitboxCFrame, atk.hitboxSize, params)
	local seen = {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		local targetPlayer = model and Players:GetPlayerFromCharacter(model)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if targetPlayer and humanoid and humanoid.Health > 0 and not seen[humanoid] then
			seen[humanoid] = true
			if not isIFraming(model) then -- a well-timed dodge avoids the hit
				humanoid:TakeDamage(atk.damage)
			end
		end
	end
end

-- One full attack: WINDUP (telegraph) -> HIT -> RECOVERY (punish window). Runs inline
-- in the boss loop so the waits only park THIS boss.
local function performAttack(boss, targetChar, dist)
	local attackName = chooseAttack(dist)
	local atk = Config.BOSS_ATTACKS[attackName]

	boss.state = "WINDUP"
	boss.humanoid:MoveTo(boss.root.Position) -- plant feet
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		faceTarget(boss, targetRoot)
	end

	boss.model:SetAttribute("Telegraphing", true)
	startTelegraph(boss)
	playTelegraphSound(boss.model)
	task.wait(atk.windup)

	-- Boss may have died during the wind-up.
	if not bosses[boss.model] or boss.humanoid.Health <= 0 then
		stopTelegraph(boss)
		boss.model:SetAttribute("Telegraphing", false)
		return
	end

	stopTelegraph(boss)
	boss.model:SetAttribute("Telegraphing", false)
	doHit(boss, atk)

	-- Phase 5.5 (juice): heavy swings shake the screen for impact weight.
	if attackName == "Overhead" or attackName == "Lunge" then
		ShakeCamera:FireAllClients(Config.SHAKE_HEAVY.intensity, Config.SHAKE_HEAVY.duration)
	end

	-- RECOVERY: the boss does nothing — the player's window to punish. Phase 2
	-- shrinks it (and the cooldown) for a clear, single escalation.
	boss.state = "RECOVERY"
	local recovery = atk.recovery
	if boss.phase >= 2 then
		recovery = recovery * Config.BOSS_PHASE2_RECOVERY_FACTOR
	end
	task.wait(recovery)

	boss.lastAttack = os.clock()
	boss.state = boss.active and "CHASE" or "IDLE"
end

-- Phase 2: a brief telegraphed, INVULNERABLE roar, then escalate aggression.
local function triggerPhase2(boss)
	boss.state = "PHASE2_ROAR"
	boss.humanoid:MoveTo(boss.root.Position)
	ShakeCamera:FireAllClients(Config.SHAKE_ROAR.intensity, Config.SHAKE_ROAR.duration) -- juice

	-- Invulnerable for the roar: restore any HP drop so hits during it do nothing.
	-- (Reaches no further than this Humanoid — no CombatServer changes.)
	local roarHP = boss.humanoid.Health
	local conn = boss.humanoid.HealthChanged:Connect(function(h)
		if h < roarHP then
			boss.humanoid.Health = roarHP
		end
	end)

	boss.model:SetAttribute("Telegraphing", true)
	startTelegraph(boss)
	task.wait(ROAR_TIME)
	stopTelegraph(boss)
	boss.model:SetAttribute("Telegraphing", false)
	conn:Disconnect()

	boss.phase = 2
	boss.lastAttack = os.clock() -- a beat before the faster offence resumes
	boss.state = boss.active and "CHASE" or "IDLE"
end

-- One decision tick (only called while the boss is active and not mid-action).
local function tickBoss(boss)
	-- Phase transition the first time HP crosses the threshold.
	if not boss.phase2Triggered and boss.humanoid.Health <= boss.humanoid.MaxHealth * Config.BOSS_PHASE2_THRESHOLD then
		boss.phase2Triggered = true
		triggerPhase2(boss)
		return
	end

	local targetChar, dist = getNearestPlayer(boss.root.Position, Config.BOSS_AGGRO_RANGE)
	if not targetChar then
		return -- no one in the arena; hold position
	end

	boss.humanoid.WalkSpeed = Config.BOSS_CHASE_SPEED
	local cooldown = Config.BOSS_ATTACK_COOLDOWN
	if boss.phase >= 2 then
		cooldown = cooldown * Config.BOSS_PHASE2_RECOVERY_FACTOR
	end

	if dist <= Config.BOSS_ATTACKS.Lunge.range and (os.clock() - boss.lastAttack) >= cooldown then
		performAttack(boss, targetChar, dist)
	else
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			boss.humanoid:MoveTo(targetRoot.Position)
		end
	end
end

----------------------------------------------------------------------
-- Fight lifecycle + fog gate
----------------------------------------------------------------------

local function sealGates()
	for _, gate in ipairs(fogGates) do
		gate.CanCollide = true
	end
end

local function unsealGates()
	for _, gate in ipairs(fogGates) do
		gate.CanCollide = false
	end
end

-- Put a boss back to its starting state (used when the player dies — Souls retry).
local function resetBoss(boss)
	boss.active = false
	boss.state = "IDLE"
	boss.phase = 1
	boss.phase2Triggered = false
	if boss.humanoid.Health > 0 then
		boss.humanoid.Health = boss.humanoid.MaxHealth
		if boss.model.Parent then
			boss.model:PivotTo(boss.spawnCFrame)
		end
	end
end

-- The player who started the fight died → unseal for a retry and reset the boss.
local function onFightPlayerDied()
	if not fightActive then
		return
	end
	fightActive = false
	if fightPlayerDiedConn then
		fightPlayerDiedConn:Disconnect()
		fightPlayerDiedConn = nil
	end
	unsealGates()
	for _, boss in pairs(bosses) do
		resetBoss(boss)
	end
	hideBossBar()
end

local function startFight(player)
	if fightActive or bossDefeated then
		return -- already fighting, or the boss is already dead (gate stays open)
	end

	local engaged = false
	for _, boss in pairs(bosses) do
		if boss.humanoid.Health > 0 then
			boss.active = true
			boss.state = "CHASE"
			if not engaged then
				showBossBar(boss.humanoid.Health, boss.humanoid.MaxHealth)
				engaged = true
			end
		end
	end
	if not engaged then
		return -- no living boss to fight
	end

	fightActive = true
	sealGates()

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		fightPlayerDiedConn = humanoid.Died:Connect(onFightPlayerDied)
	end
end

local function onBossDeath(boss)
	bossDefeated = true
	fightActive = false
	boss.active = false
	boss.state = "DEAD"

	-- Award the killer via the EXISTING Phase 2 path (PlayerData watches LastAttacker
	-- + the Runes attribute). We only stamp the reward here.
	boss.model:SetAttribute("Runes", Config.BOSS_RUNE_REWARD)

	-- The boss stays dead: unseal permanently and never re-trigger.
	unsealGates()
	if fightPlayerDiedConn then
		fightPlayerDiedConn:Disconnect()
		fightPlayerDiedConn = nil
	end
	hideBossBar()
end

----------------------------------------------------------------------
-- Adoption
----------------------------------------------------------------------

local function setupBoss(model)
	if bosses[model] then
		return
	end
	if not model:IsA("Model") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	humanoid.MaxHealth = Config.BOSS_HP
	humanoid.Health = Config.BOSS_HP
	humanoid.WalkSpeed = Config.BOSS_WALK_SPEED

	local boss = {
		model = model,
		humanoid = humanoid,
		root = root,
		active = false,
		state = "IDLE",
		phase = 1,
		phase2Triggered = false,
		lastAttack = 0,
		spawnCFrame = model:GetPivot(),
	}
	bosses[model] = boss

	-- Keep the boss bar in sync while the fight is on.
	humanoid.HealthChanged:Connect(function(h)
		if fightActive then
			showBossBar(h, humanoid.MaxHealth)
		end
	end)

	humanoid.Died:Once(function()
		onBossDeath(boss)
	end)

	-- Per-boss AI loop. IDLE (does nothing) until the fog gate activates it.
	task.spawn(function()
		while bosses[model] and humanoid.Health > 0 do
			if boss.active then
				tickBoss(boss)
			end
			task.wait(0.1)
		end
	end)
end

local function setupFogGate(gate)
	if not gate:IsA("BasePart") then
		return
	end
	for _, g in ipairs(fogGates) do
		if g == gate then
			return
		end
	end
	table.insert(fogGates, gate)
	gate.CanCollide = false -- passable fog until a fight commits the player

	gate.Touched:Connect(function(hit)
		if fightActive or bossDefeated then
			return -- one trigger per arena entry; never re-trigger
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player and humanoid and humanoid.Health > 0 then
			startFight(player)
		end
	end)
end

for _, model in ipairs(CollectionService:GetTagged(BOSS_TAG)) do
	setupBoss(model)
end
CollectionService:GetInstanceAddedSignal(BOSS_TAG):Connect(setupBoss)

for _, gate in ipairs(CollectionService:GetTagged(FOGGATE_TAG)) do
	setupFogGate(gate)
end
CollectionService:GetInstanceAddedSignal(FOGGATE_TAG):Connect(setupFogGate)
