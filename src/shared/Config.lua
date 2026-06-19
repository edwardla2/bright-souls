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

	-- Ember Flask (Phase 3: healing)
	FLASK_MAX_CHARGES = 4, -- charges available, refilled at a Site of Grace
	FLASK_HEAL_AMOUNT = 50, -- HP restored per drink (clamped to MaxHealth)
	FLASK_DRINK_TIME = 1.1, -- seconds; slow on purpose — you're vulnerable while drinking
	FLASK_KEY = Enum.KeyCode.R, -- key the client binds to drink

	-- Stats + leveling (Phase 4)
	BASE_STAT = 10, -- starting value for every stat (Vigor/Endurance/Strength/Dexterity)
	BASE_HP = 100, -- max HP at base Vigor (matches the default Humanoid MaxHealth)
	VIGOR_HP_PER_POINT = 20, -- max HP gained per Vigor point above base
	ENDURANCE_STAMINA_PER_POINT = 10, -- max stamina gained per Endurance point above base
	LEVEL_BASE_COST = 50, -- rune cost of the first level
	LEVEL_COST_GROWTH = 1.1, -- each level costs this factor more than the last

	-- Boss: The Tide-Drowned Knight (Phase 5)
	BOSS_HP = 600,
	BOSS_WALK_SPEED = 10,
	BOSS_CHASE_SPEED = 16,
	BOSS_AGGRO_RANGE = 80,
	BOSS_ATTACK_RANGE = 9, -- close-attack range; Lunge reaches further (see BOSS_ATTACKS)
	BOSS_ATTACK_COOLDOWN = 1.2, -- base seconds between boss attacks
	BOSS_RUNE_REWARD = 1000,
	BOSS_PHASE2_THRESHOLD = 0.5, -- fraction of HP that triggers phase 2
	BOSS_PHASE2_RECOVERY_FACTOR = 0.6, -- phase 2 shortens recovery + cooldown (smaller punish window)

	-- Three attack patterns. Each: telegraph (windup), damage, reach (range),
	-- recovery (the vulnerable punish window), and the swing's hitbox volume.
	BOSS_ATTACKS = {
		Overhead = { windup = 0.8, damage = 40, range = 9, recovery = 1.0, hitboxSize = Vector3.new(8, 6, 8) },
		Sweep = { windup = 0.7, damage = 30, range = 11, recovery = 0.9, hitboxSize = Vector3.new(14, 5, 8) },
		Lunge = { windup = 0.9, damage = 50, range = 18, recovery = 1.2, hitboxSize = Vector3.new(6, 5, 14) },
	},

	-- Game feel / juice (Phase 5.5) — all dial-by-feel; changes feedback, not mechanics.
	HITSTOP_DURATION = 0.1, -- seconds the hit enemy/boss freezes (anchored) on a connecting hit
	HIT_SOUND_ID = "rbxassetid://3744370691", -- PLACEHOLDER melee impact — VERIFY / REPLACE
	HIT_SOUND_VOLUME = 0.9,
	HIT_FLASH_DURATION = 0.1, -- white Highlight flash on a hit enemy/boss
	SPARK_LIFETIME = 0.3, -- hit-spark part lifetime (seconds)
	TELEGRAPH_SOUND_ID = "rbxassetid://1837835729", -- PLACEHOLDER windup "tell" cue — VERIFY / REPLACE
	TELEGRAPH_SOUND_VOLUME = 0.6,
	TELEGRAPH_PULSE_CYCLES = 4, -- enemy telegraph throbs per windup (loudness only — timing unchanged)

	-- Camera shake events: { intensity = stud offset, duration = seconds }
	SHAKE_DEAL = { intensity = 0.35, duration = 0.18 }, -- you LAND a hit
	SHAKE_TAKE = { intensity = 0.9, duration = 0.3 }, -- you TAKE a hit (any source)
	SHAKE_HEAVY = { intensity = 1.2, duration = 0.35 }, -- boss heavy attack (Overhead / Lunge)
	SHAKE_ROAR = { intensity = 1.8, duration = 0.5 }, -- boss phase-2 roar

	-- Movement weight (Phase 5.5 item 5) is intentionally NOT implemented: Roblox has
	-- no clean accel/decel without custom movement that risks the dodge dash feel and
	-- responsiveness. Per the brief, responsiveness wins — so it is skipped on purpose.

	-- Lock-on targeting (Phase 5.6a). Q=dodge, R=flask, F=Grace prompt, LeftShift=sprint
	-- are taken, so lock-on uses the middle mouse button; the wheel switches targets.
	LOCKON_KEY = Enum.UserInputType.MouseButton3, -- toggle lock-on
	LOCKON_RANGE = 60, -- studs; max range to acquire a target
	LOCKON_BREAK_RANGE = 70, -- studs; lock auto-breaks beyond this
	LOCKON_CAM_DISTANCE = 14, -- studs the locked camera sits behind the player
	LOCKON_CAM_HEIGHT = 6, -- studs the locked camera sits above the player
	LOCKON_CAM_SMOOTH = 0.15, -- camera lerp alpha per frame (smaller = smoother/slower)

	-- Sprint (Phase 5.6a) — drains the SAME stamina pool as attacks/dodges.
	BASE_WALK_SPEED = 16, -- default character WalkSpeed (the Roblox default)
	SPRINT_SPEED = 24,
	SPRINT_STAMINA_DRAIN = 15, -- stamina per second while sprinting + moving
	SPRINT_KEY = Enum.KeyCode.LeftShift,
	SPRINT_MIN_STAMINA = 5, -- can't START a sprint below this (but may continue down to 0)
}
