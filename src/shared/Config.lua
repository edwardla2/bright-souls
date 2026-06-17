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
	REGEN_RATE = 35, -- stamina restored per second once regen resumes
	REGEN_DELAY = 1.0, -- seconds of "no spending" required before regen kicks in
	ATTACK_COST = 20, -- stamina spent per swing
	DODGE_COST = 30, -- stamina spent per dodge roll

	-- Offense
	ATTACK_DAMAGE = 25, -- damage applied to each unique humanoid hit
	HITBOX_SIZE = Vector3.new(6, 4, 5), -- width / height / depth of the swing volume
	HITBOX_REACH = 3.5, -- studs in front of the HumanoidRootPart to center the hitbox
	ATTACK_ANIM_ID = "rbxassetid://522635514", -- built-in R15 slash animation (client-side playback only)

	-- Dodge
	DODGE_SPEED = 52, -- BodyVelocity speed of the dodge burst
	DODGE_DURATION = 0.28, -- seconds the dodge velocity (and i-frames) last

	-- Enemy AI (Phase 1: one melee enemy)
	ENEMY_HP = 100, -- starting Humanoid MaxHealth/Health for a tagged enemy
	ENEMY_WALK_SPEED = 8, -- WalkSpeed while idle / returning home
	ENEMY_CHASE_SPEED = 14, -- WalkSpeed while aggroed and chasing
	ENEMY_AGGRO_RANGE = 35, -- studs; player closer than this trips IDLE -> AGGRO
	ENEMY_ATTACK_RANGE = 6, -- studs; close enough to begin a swing
	ENEMY_LEASH_RANGE = 60, -- studs from spawn; beyond this the enemy gives up and RETURNs
	ENEMY_DAMAGE = 20, -- damage a landed enemy swing deals to the player
	ENEMY_ATTACK_COOLDOWN = 1.0, -- seconds between enemy attacks
	ENEMY_WINDUP_TIME = 0.3, -- telegraph duration before the hit lands (the dodge window)
	ENEMY_RUNE_REWARD = 50, -- runes dropped on death (stored as a model attribute for Phase 2)
}
