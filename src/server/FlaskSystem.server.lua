--[[
	FlaskSystem.server.lua  (ServerScriptService)

	Phase 3 of Bright Souls: the Ember Flask — the Estus equivalent. A limited pool of
	charges (refilled at Sites of Grace) that heal a chunk of HP. Drinking is slow and
	leaves you VULNERABLE on purpose: no i-frames, no damage protection — healing is
	itself a risk/reward decision.

	Server-authoritative: the client only requests a drink (FlaskDrink) and displays
	the charge count we sync back (FlaskSync). GraceSystem refills charges via the
	RefillFlasks bindable on rest.

	Additive: does not touch combat, stamina, dodge, enemy, or rune systems.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FlaskDrink = Remotes:WaitForChild("FlaskDrink")
local FlaskSync = Remotes:WaitForChild("FlaskSync")

local Bindables = ServerStorage:WaitForChild("Bindables")
local RefillFlasks = Bindables:WaitForChild("RefillFlasks")

local charges = {} -- [player] = number of charges remaining
local drinking = {} -- [player] = true while a drink is in progress (server guard)

local function syncCharges(player)
	if charges[player] == nil then
		return
	end
	FlaskSync:FireClient(player, charges[player], Config.FLASK_MAX_CHARGES)
end

Players.PlayerAdded:Connect(function(player)
	charges[player] = Config.FLASK_MAX_CHARGES
	syncCharges(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	charges[player] = Config.FLASK_MAX_CHARGES
	syncCharges(player)
end
Players.PlayerRemoving:Connect(function(player)
	charges[player] = nil
	drinking[player] = nil
end)

-- GraceSystem requests a full refill when the player rests.
RefillFlasks.Event:Connect(function(player)
	if charges[player] == nil then
		return
	end
	charges[player] = Config.FLASK_MAX_CHARGES
	syncCharges(player)
end)

-- A drink: slow, vulnerable, then heals on success.
FlaskDrink.OnServerEvent:Connect(function(player)
	if drinking[player] then
		return -- already mid-drink; ignore spam
	end
	local n = charges[player]
	if not n or n <= 0 then
		return -- no charges to spend
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return -- dead / not loaded
	end

	drinking[player] = true

	-- Slow drink — the player is deliberately exposed for the whole duration. We do
	-- NOT grant i-frames or block damage here; vulnerability is the point.
	task.wait(Config.FLASK_DRINK_TIME)

	-- Re-validate after the wait: the player may have died mid-drink.
	character = player.Character
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and (charges[player] or 0) > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + Config.FLASK_HEAL_AMOUNT)
		charges[player] = charges[player] - 1
		syncCharges(player)
	end

	drinking[player] = nil
end)
