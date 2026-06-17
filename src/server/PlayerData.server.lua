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

	part.Parent = workspace -- parent LAST, once fully configured
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
		-- Only a LIVING character can reclaim. The bloodstain spawns on the exact
		-- spot the player died, so the owner's own CORPSE is touching it immediately —
		-- without this guard that corpse "recovers" and destroys the marker the same
		-- frame it appears (and hands the runes back). A respawned, living body
		-- walking back is what should reclaim it.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local reward = part:GetAttribute("Runes") or 0
		data.bloodstain = nil
		part:Destroy()
		awardRunes(owner, reward) -- restores the dropped runes to the player (fires RuneSync)
		print(owner.Name .. " recovered " .. reward .. " runes")
	end)
end

local function onDeath(player, character)
	local data = playerData[player]
	if not data then
		return
	end

	-- Use the position we tracked while the player was ALIVE. Reading the
	-- HumanoidRootPart here (inside Died) is unreliable — the character is being
	-- torn down, so the part may be gone or report a stale/origin position. Fall
	-- back to the live HRP only if we somehow never captured a position.
	local position = data.lastPos
	if not position then
		local root = character:FindFirstChild("HumanoidRootPart")
		position = root and root.Position or nil
	end

	-- Capture how many runes to drop FIRST, before anything can reset the total.
	-- The 0-runes rule below checks THIS captured amount (what the player had on
	-- death), never the post-reset count.
	local dropped = data.runes

	-- Die-twice rule: any PREVIOUS bloodstain (and its runes) is lost forever.
	-- Capture the OLD reference into a local and clear the field BEFORE we create the
	-- new marker, so this destroy can never touch the bloodstain we're about to spawn.
	local oldBloodstain = data.bloodstain
	data.bloodstain = nil
	if oldBloodstain then
		oldBloodstain:Destroy()
	end

	-- Drop the captured runes — only if there's something to recover AND a genuine
	-- position to place the marker. Dying with 0 runes intentionally drops nothing.
	if dropped > 0 and position then
		local part = spawnBloodstain(position, dropped)
		data.bloodstain = part
		bindRecovery(part, player)
	elseif dropped > 0 then
		warn("No valid death position for " .. player.Name .. " — bloodstain skipped, runes lost")
	end

	-- Only now, after the drop is placed, clear the carried total and sync the HUD.
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
	-- Initialise ONCE per player. Never recreate an existing entry — that would wipe
	-- runes already earned. The table is keyed by Player so it survives respawns
	-- (respawns go through onCharacterAdded, which never touches this table).
	if not playerData[player] then
		playerData[player] = { runes = 0, bloodstain = nil, lastPos = nil }
	end
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

-- Continuously remember each LIVING player's position (~4x/sec) so death always has
-- a reliable spot for the bloodstain. This sidesteps the cleanup race: the
-- HumanoidRootPart is unreliable by the time Humanoid.Died fires, so we never read
-- it then — we use this last-known-good position instead. The loop body never
-- yields, so it can't collide with PlayerRemoving mutating playerData.
task.spawn(function()
	while true do
		for player, data in pairs(playerData) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				data.lastPos = root.Position
			end
		end
		task.wait(0.25)
	end
end)

--[[
	PHASE 3 NOTE — RESPAWN POINT IS TEMPORARY.
	Right now we rely on Roblox's default respawn (the workspace SpawnLocation).
	In Phase 3, respawn must instead send the player to the last Site of Grace they
	rested at. When that lands, set the player's RespawnLocation (or teleport the new
	character) to the active Grace here in onCharacterAdded, and remove this note.
]]
