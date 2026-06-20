--[[
	Weapons.lua  (ReplicatedStorage.Shared)

	Phase 5.7a: weapon definitions, keyed by id. Tuned HERE (not Config). PlayerData
	publishes the equipped weapon's stats onto the player as attributes; CombatServer
	reads those (with Config fallback) so combat pulls damage/range/cost from the
	equipped weapon instead of flat constants.

	DEFAULT "broken_sword" reproduces the current Config light/heavy numbers EXACTLY, so
	equipping it = today's behaviour (no regression). Schema note: each weapon carries
	BOTH a light (hitboxSize/hitboxReach) and heavy (heavyHitboxSize/heavyHitboxReach)
	box, because current combat uses a bigger box for heavy — needed to stay byte-identical.

	scaling{}/weight are stored for later (5.7c scaling, equip-load) but NOT applied yet.
	weaponType drives 5.7b movesets. modelAssetId is nil → the hand visual uses a Part.
]]

return {
	broken_sword = {
		id = "broken_sword",
		displayName = "Broken Sword",
		lightDamage = 25,
		heavyDamage = 55,
		lightStaminaCost = 20,
		heavyStaminaCost = 35,
		hitboxSize = Vector3.new(6, 4, 5),
		hitboxReach = 3.5,
		heavyHitboxSize = Vector3.new(8, 5, 7),
		heavyHitboxReach = 4.5,
		attackSpeed = 1.0,
		poiseDamageLight = 25,
		poiseDamageHeavy = 60,
		weight = 8,
		scaling = { Strength = 0.5, Dexterity = 0.2 },
		weaponType = "straightsword",
		modelAssetId = nil,
	},

	greatsword = {
		id = "greatsword",
		displayName = "Greatsword",
		lightDamage = 40,
		heavyDamage = 80,
		lightStaminaCost = 35,
		heavyStaminaCost = 55,
		hitboxSize = Vector3.new(9, 5, 7),
		hitboxReach = 5,
		heavyHitboxSize = Vector3.new(12, 6, 9),
		heavyHitboxReach = 6.5,
		attackSpeed = 0.7,
		poiseDamageLight = 45,
		poiseDamageHeavy = 90,
		weight = 18,
		scaling = { Strength = 0.8, Dexterity = 0.1 },
		weaponType = "greatsword",
		modelAssetId = nil,
	},

	dagger = {
		id = "dagger",
		displayName = "Dagger",
		lightDamage = 14,
		heavyDamage = 28,
		lightStaminaCost = 12,
		heavyStaminaCost = 22,
		hitboxSize = Vector3.new(4, 3, 4),
		hitboxReach = 2.5,
		heavyHitboxSize = Vector3.new(5, 3, 5),
		heavyHitboxReach = 3,
		attackSpeed = 1.5,
		poiseDamageLight = 12,
		poiseDamageHeavy = 25,
		weight = 3,
		scaling = { Strength = 0.2, Dexterity = 0.9 },
		weaponType = "dagger",
		modelAssetId = nil,
	},
}
