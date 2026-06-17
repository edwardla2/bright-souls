--[[
	GraceSystem.server.lua  (ServerScriptService)

	Phase 3 of Bright Souls: Sites of Grace — the warm, safe checkpoints between
	dangerous stretches. Resting at a Grace (via its ProximityPrompt):
	  * heals the player to full and refills stamina + Ember Flasks,
	  * sets that Grace as the player's respawn point,
	  * respawns every defeated enemy (classic Souls behaviour),
	  * flashes a brief "Grace restored" visual on the client.

	This script also OWNS respawn placement (the single source of truth): on death the
	player returns to their last-rested Grace, or the default SpawnLocation if they
	have not rested yet. PlayerData no longer decides where players respawn.

	Additive: it does not modify the stamina system, enemy state machine, dodge
	handler, or rune/bloodstain logic. It REQUESTS refills (stamina via CombatServer's
	RefillStamina bindable, flasks via FlaskSystem's RefillFlasks bindable) and
	re-introduces enemy models for EnemyAI to adopt — never rewriting those systems.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config) -- kept for convention / future tuning

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GraceRested = Remotes:WaitForChild("GraceRested")

local Bindables = ServerStorage:WaitForChild("Bindables")
local RefillStamina = Bindables:WaitForChild("RefillStamina")
local RefillFlasks = Bindables:WaitForChild("RefillFlasks")

local GRACE_TAG = "Grace"
local ENEMY_TAG = "Enemy"
local RIG_NAME = "Rig"
local RESPAWN_Y_OFFSET = 5 -- studs above the Grace to place a respawned character

-- Per-player respawn position (Vector3), set when they rest at a Grace.
local respawnPos = {}

-- Respawnable enemy spawn points captured at server start:
-- { template = Model (pristine clone), cframe = CFrame, current = Model? }
local enemySpawns = {}

----------------------------------------------------------------------
-- Enemy respawn (re-introduce missing enemies for EnemyAI to adopt)
----------------------------------------------------------------------

-- Capture a pristine clone + spawn CFrame for an enemy present at server start.
local function snapshotEnemy(model)
	if not model:IsA("Model") then
		return
	end
	if not (model:FindFirstChildOfClass("Humanoid") and model:FindFirstChild("HumanoidRootPart")) then
		return
	end
	for _, spawn in ipairs(enemySpawns) do
		if spawn.current == model then
			return -- already captured (e.g. both tagged "Enemy" and named "Rig")
		end
	end
	table.insert(enemySpawns, {
		template = model:Clone(), -- pristine copy, kept unparented
		cframe = model:GetPivot(),
		current = model,
	})
end

-- On rest, re-clone any enemy that has died or despawned. Living enemies are left
-- alone (never duplicated). The clone keeps its "Enemy" tag / "Rig" name, so simply
-- parenting it to the workspace makes EnemyAI adopt it — no EnemyAI changes needed.
local function respawnEnemies()
	for _, spawn in ipairs(enemySpawns) do
		local current = spawn.current
		local humanoid = current and current:FindFirstChildOfClass("Humanoid")
		local alive = current and current.Parent ~= nil and humanoid and humanoid.Health > 0
		if not alive then
			if current and current.Parent then
				current:Destroy() -- clear a lingering corpse before re-spawning
			end
			local clone = spawn.template:Clone()
			clone:PivotTo(spawn.cframe)
			clone.Parent = workspace
			spawn.current = clone
		end
	end
end

----------------------------------------------------------------------
-- Resting at a Grace
----------------------------------------------------------------------

local function onRest(player, gracePart)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return -- can't rest while dead / not loaded
	end

	-- Heal to full (HP is the Humanoid's own value — no combat logic touched).
	humanoid.Health = humanoid.MaxHealth

	-- Request full stamina + flask refills from the systems that own those values.
	RefillStamina:Fire(player)
	RefillFlasks:Fire(player)

	-- This Grace becomes the player's respawn point.
	respawnPos[player] = gracePart.Position + Vector3.new(0, RESPAWN_Y_OFFSET, 0)

	-- Classic Souls: resting respawns all defeated enemies.
	respawnEnemies()

	-- Brief client-side "Grace restored" visual.
	GraceRested:FireClient(player)
end

----------------------------------------------------------------------
-- Grace detection + ProximityPrompt
----------------------------------------------------------------------

local function setupGrace(graceInstance)
	local part = graceInstance:IsA("BasePart") and graceInstance
		or graceInstance:FindFirstChildWhichIsA("BasePart")
	if not part then
		return -- nothing to attach a prompt to
	end
	if part:FindFirstChild("GracePrompt") then
		return -- already set up
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GracePrompt"
	prompt.ActionText = "Rest"
	prompt.ObjectText = "Site of Grace"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		onRest(player, part)
	end)
end

for _, grace in ipairs(CollectionService:GetTagged(GRACE_TAG)) do
	setupGrace(grace)
end
CollectionService:GetInstanceAddedSignal(GRACE_TAG):Connect(setupGrace)

----------------------------------------------------------------------
-- Respawn placement (single source of truth — see PlayerData's note)
----------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local pos = respawnPos[player]
	if not pos then
		return -- never rested → leave them at the default SpawnLocation
	end
	-- Wait for the body, then move it to the last-rested Grace.
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		character:PivotTo(CFrame.new(pos))
	end
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	respawnPos[player] = nil
end)

----------------------------------------------------------------------
-- Snapshot enemies present at server start (before any are killed)
----------------------------------------------------------------------

for _, model in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
	snapshotEnemy(model)
end
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("Model") and inst.Name == RIG_NAME then
		snapshotEnemy(inst)
	end
end
