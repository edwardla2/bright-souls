--[[
	PlayerData.server.lua  (ServerScriptService)

	Phase 2 of Bright Souls: the rune economy and death/recovery loop — the core
	Souls tension. Runes are the universal currency (XP + money). You earn them by
	killing enemies, drop ALL of them where you die, and get exactly ONE chance to
	recover them: die again before reclaiming and they're gone forever.

	Responsibilities (server-authoritative; the client only displays what we send):
	  * Owns each player's rune total in `playerData`, surviving respawns (keyed by
	    Player, not character). Pushes changes to the HUD via the RuneSync remote.
	  * Awards runes on a kill. The enemy AI stamps a "Runes" attribute on a dying
	    enemy; CombatServer stamps a "LastAttacker" ObjectValue on whoever hit it.
	    We watch for that ObjectValue appearing, then react to the Runes attribute
	    being set (the death-drop) and pay out the killer. This keeps EnemyAI and
	    CombatServer's hit logic untouched.
	  * On death: drops a glowing "Bloodstain" holding the player's runes, zeroes
	    their total, and destroys any PREVIOUS bloodstain first (the die-twice rule).
	  * Recovery: touching your OWN bloodstain returns its runes and removes it.

	Additive: does not change the stamina system, dodge handler, enemy state
	machine, or Config tuning. CombatServer's only change is the attacker tag above.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RuneSync = Remotes:WaitForChild("RuneSync")

local GOLD = Color3.fromRGB(212, 175, 55) -- the Ember/rune colour; matches the HUD

-- Per-player state, keyed by the Player instance (so it survives respawns).
-- playerData[player] = { runes = number, bloodstain = Part? }
local playerData = {}

----------------------------------------------------------------------
-- Rune total + HUD sync
----------------------------------------------------------------------

local function syncRunes(player)
	local data = playerData[player]
	if not data then
		return
	end
	RuneSync:FireClient(player, data.runes)
end

local function awardRunes(player, amount)
	local data = playerData[player]
	if not data or amount <= 0 then
		return
	end
	data.runes = data.runes + amount
	syncRunes(player)
end

----------------------------------------------------------------------
-- Awarding runes on a kill
----------------------------------------------------------------------
-- CombatServer adds a "LastAttacker" ObjectValue to any enemy a player damages.
-- When that value appears we start watching the enemy's "Runes" attribute; the
-- enemy AI sets it once, at the moment of death (its rune drop). That set is our
-- cue to pay the killer. Only enemies ever get a Runes attribute, so a damaged
-- *player* character carrying a LastAttacker is harmlessly ignored.

workspace.DescendantAdded:Connect(function(instance)
	if not (instance:IsA("ObjectValue") and instance.Name == "LastAttacker") then
		return
	end
	local enemyModel = instance.Parent
	if not enemyModel then
		return
	end

	-- The enemy's "Runes" attribute is stamped exactly once, on death. React to it.
	enemyModel:GetAttributeChangedSignal("Runes"):Connect(function()
		local reward = enemyModel:GetAttribute("Runes")
		if not reward or reward <= 0 then
			return
		end
		local killer = instance.Value -- the last player to hit it
		if killer and killer:IsA("Player") and playerData[killer] then
			awardRunes(killer, reward)
		end
		-- No valid attacker (e.g. they left the game) → award nobody.
	end)
end)

----------------------------------------------------------------------
-- Bloodstain: drop on death, recover on touch
----------------------------------------------------------------------

-- A glowing gold marker dropped where the player died, carrying their runes.
local function spawnBloodstain(position, runes)
	local part = Instance.new("Part")
	part.Name = "Bloodstain"
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(7, 3, 3) -- 7 tall, 3 wide once stood upright (below)
	-- Rotate the cylinder's axis from local-X to world-Y so it stands as a pillar,
	-- tall enough that a player walking over the spot reliably triggers Touched.
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Material = Enum.Material.Neon
	part.Color = GOLD
	part.Transparency = 0.55
	part:SetAttribute("Runes", runes)

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 6
	light.Range = 18
	light.Parent = part

	part.Parent = workspace
	return part
end

-- Reclaim a bloodstain when its OWNER (and only its owner) touches it.
local function bindRecovery(part, owner)
	part.Touched:Connect(function(hit)
		local data = playerData[owner]
		-- Ignore if this player's bloodstain is no longer this part (already
		-- recovered, or replaced by a newer death).
		if not data or data.bloodstain ~= part then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local toucher = character and Players:GetPlayerFromCharacter(character)
		if toucher ~= owner then
			return
		end

		local reward = part:GetAttribute("Runes") or 0
		data.bloodstain = nil
		part:Destroy()
		awardRunes(owner, reward) -- fires RuneSync with the restored total
	end)
end

local function onDeath(player, character)
	local data = playerData[player]
	if not data then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position or character:GetPivot().Position

	-- Die-twice rule: any existing bloodstain (and its runes) is lost forever.
	if data.bloodstain then
		data.bloodstain:Destroy()
		data.bloodstain = nil
	end

	-- Drop everything carried. Only bother spawning a marker if there's something
	-- in it to recover.
	local dropped = data.runes
	if dropped > 0 then
		local part = spawnBloodstain(position, dropped)
		data.bloodstain = part
		bindRecovery(part, player)
	end

	data.runes = 0
	syncRunes(player)
end

----------------------------------------------------------------------
-- Player / character lifecycle
----------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	-- Re-bound every respawn so death is always detected; rune state itself lives
	-- in playerData (keyed by Player) and is untouched by the respawn.
	humanoid.Died:Connect(function()
		onDeath(player, character)
	end)
end

local function onPlayerAdded(player)
	playerData[player] = { runes = 0, bloodstain = nil }
	syncRunes(player)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player) -- adopt players already in-game when this script starts
end

Players.PlayerRemoving:Connect(function(player)
	local data = playerData[player]
	if data and data.bloodstain then
		data.bloodstain:Destroy()
	end
	playerData[player] = nil
end)

--[[
	PHASE 3 NOTE — RESPAWN POINT IS TEMPORARY.
	Right now we rely on Roblox's default respawn (the workspace SpawnLocation).
	In Phase 3, respawn must instead send the player to the last Site of Grace they
	rested at. When that lands, set the player's RespawnLocation (or teleport the new
	character) to the active Grace here in onCharacterAdded, and remove this note.
]]
