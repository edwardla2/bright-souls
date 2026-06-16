--[[
	Config.lua  (ReplicatedStorage.Shared.Config)

	Shared tuning values for the souls-like combat system. This ModuleScript is
	required by BOTH the server (CombatServer) and the client (CombatClient) so
	that stamina costs, damage, hitbox geometry, and dodge feel stay in sync on
	every machine. Edit balance here in one place — never hard-code these numbers
	elsewhere.
]]

return {
	-- Stamina economy
	MAX_STAMINA = 100, -- ceiling each player regenerates toward
	REGEN_RATE = 20, -- stamina restored per second once regen resumes
	REGEN_DELAY = 1.2, -- seconds of "no spending" required before regen kicks in
	ATTACK_COST = 20, -- stamina spent per swing
	DODGE_COST = 30, -- stamina spent per dodge roll

	-- Offense
	ATTACK_DAMAGE = 25, -- damage applied to each unique humanoid hit
	HITBOX_SIZE = Vector3.new(6, 4, 5), -- width / height / depth of the swing volume
	HITBOX_REACH = 3.5, -- studs in front of the HumanoidRootPart to center the hitbox

	-- Dodge
	DODGE_SPEED = 52, -- BodyVelocity speed of the dodge burst
	DODGE_DURATION = 0.28, -- seconds the dodge velocity (and i-frames) last
}
