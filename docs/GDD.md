# BRIGHT SOULS — Game Design Document

A difficult, lore-driven action-RPG for Roblox, built in the tradition of FromSoftware's
Souls games (Elden Ring especially). Punishing combat, environmental storytelling,
a runes-on-death economy, and bosses that demand pattern recognition over button mashing.

---

## 1. CORE PILLARS

These four principles decide every design argument. When a feature is in question,
ask: does it serve a pillar? If not, cut it.

1. **Death is the teacher.** Dying is frequent, fair, and informative. Every death
   should feel like the player's fault, never the game's. No fake difficulty (no
   unavoidable damage, no input-eating).
2. **The world tells the story.** No exposition dumps. Lore lives in item descriptions,
   environment, NPC fragments, and boss arenas. The player assembles meaning themselves.
3. **Risk is rewarded.** Aggression, exploration, and greed are all gambles that can pay
   out big — or kill you. The rune economy (lose everything on death, recover it once)
   makes every run tense.
4. **Mastery is visible.** A skilled player looks different from a new one — tighter
   dodges, no wasted stamina, reading boss tells. The skill ceiling is high and the game
   never hides it behind stats alone.

---

## 2. STORYLINE & WORLD

### Premise

The world of **Aurelne** was lit by the **First Ember** — a divine flame that gave the
land warmth, memory, and order. Generations ago the Ember began to die. As it faded, the
dead stopped staying dead: they rise again, hollowed, repeating the last act of their
lives forever. This is **the Dimming**.

You are a **Cinderless** — one of the undying, but unlike the hollowed, you have not yet
lost your **self**. You wake at the edge of the dying world with no memory of who you were,
drawn by an instinct you can't name toward the cold heart of the kingdom, where the Ember's
last coals still smolder.

Your purpose, revealed slowly: the Ember can be **rekindled** — but only by feeding it a
soul that has not hollowed. Yours. Every Site of Grace you light is a fragment of the
Ember responding to your presence. The closer you get, the more the world remembers you —
and the more it wants you to take the place of the flame.

### The Central Question (the player's real choice)

By the end, the player learns the truth: rekindling the Ember restores order to Aurelne
but requires the player to burn themselves into it forever — becoming the next slow-dying
god, dooming a future Cinderless to the same journey. The alternative is to let the Ember
die completely, plunging the world into the **Long Dark** — a world without memory, but
also without the cycle of suffering.

This is the **two-ending fork** (a third, hidden ending exists for players who find all
lore fragments — see §8). The game never tells you which is "right." That ambiguity is the
point.

### Tone

Melancholic, beautiful, lonely. The world is gorgeous and dying. NPCs are few, strange,
and mostly doomed. Humor is rare and dark. The player should feel small.

---

## 3. THE WORLD MAP (MVP SCOPE: 3 AREAS)

The full game would have 6–8 areas. The MVP ships **three**, in a linear-with-shortcuts
structure (Souls games loop back on themselves; even the MVP should have one unlockable
shortcut).

### Area 1 — The Ashen Shore (tutorial + first boss)
- Where you wash up. Grey beaches, broken ships, a half-sunk cathedral.
- Teaches: movement, attack, dodge, stamina, first Site of Grace, runes, death/recovery.
- Enemies: **Hollow Drifters** (slow, telegraphed, easy to read — the "training dummy"
  enemy with real AI).
- Boss: **The Tide-Drowned Knight** — a slow, heavy, deeply telegraphed boss. Teaches
  dodge-timing and punish windows. The "Margit-but-gentler" gatekeeper.

### Area 2 — The Emberwood (exploration + verticality)
- A vast dead forest lit by floating embers. Branching paths, a hidden Site of Grace,
  the first NPC questline, an optional mini-boss.
- Enemies: **Ashen Stalkers** (fast, flank you, punish greed), **Ember Wisps** (ranged).
- Mini-boss (optional): **The Hollow Chorus** — three weak enemies that must be fought
  together; teaches crowd control and positioning.
- Boss: **Mother of Cinders** — fast, aggressive, two-phase. Phase 2 adds fire. The
  "now you're really playing Souls" difficulty spike.

### Area 3 — The Coldhearth (climax)
- The frozen throne of the dead kingdom. The Ember's last coals. Final approach.
- Enemies: **Wraith Sentinels** (elite, combo-heavy).
- Final Boss: **The First Flame, Hollowed** — three phases, the mechanical and narrative
  climax. The ending fork triggers after this fight.

---

## 4. COMBAT SYSTEM (already partially built)

You've built the foundation: stamina, light attack, dodge with i-frames. Here's the full
target spec the combat should grow into.

### Already built ✅
- Stamina bar (drain on action, delayed regen)
- Light attack (hitbox + damage, dedupe, i-frame respect)
- Dodge roll (directional, i-frames)
- Attack animation (built-in, in progress)

### Combat roadmap (post-MVP-combat)
- **Heavy attack** (right click): slower, more stamina, more damage, poise-breaking.
- **Blocking** (if shield equipped): reduces damage, costs stamina, can be guard-broken.
- **Backstabs / ripostes**: positional bonus damage; ripostes after a guard-break.
- **Poise**: enemies (and player) have a hidden stagger meter. Heavy hits stagger.
- **Lock-on targeting**: camera locks to nearest enemy; dodge becomes relative to target.
- **Weapon movesets**: different weapon types (straight sword, greatsword, dagger, spear)
  have distinct attack speeds, ranges, and stamina costs.

### Combat feel targets (the numbers that matter)
- Dodge i-frames: ~0.28s (tune live)
- Attack commitment: you cannot cancel an attack mid-swing (this is core Souls feel)
- Stamina punishes spam but recovers fast enough to stay aggressive
- Enemies telegraph every attack with a visible wind-up the player can react to

---

## 5. CHARACTER PROGRESSION

### Stats (Souls-style, level them at Sites of Grace with runes)
- **Vigor** — max HP
- **Endurance** — max stamina + equip load
- **Strength** — scaling for heavy weapons
- **Dexterity** — scaling for fast weapons
- **Faith/Arcane** (post-MVP) — scaling for miracles/sorcery

### Leveling
- Spend **runes** at a Site of Grace to raise a stat by 1.
- Cost scales: each level costs more runes than the last (soft level cap via economy).
- Stats are permanent (no respec in MVP; a respec item is a post-MVP NPC reward).

### Equip load
- Armor and weapons have weight. Total weight vs. Endurance determines roll type:
  - Light (<30%): fast roll, long i-frames
  - Medium (30–70%): normal roll
  - Heavy (>70%): slow fat-roll, short i-frames
  - Over 100%: cannot roll, only stagger-step

---

## 6. THE RUNE ECONOMY (the heart of the tension)

This is the single most important system after combat. It's what makes Souls *Souls*.

- Kill enemies → earn **runes** (the universal currency: XP *and* money).
- Spend runes on: leveling stats, buying items from NPCs, upgrading weapons.
- **On death**: you drop ALL your runes where you died and respawn at the last Site of
  Grace. All regular enemies respawn too.
- You get **one chance** to recover your dropped runes. Die again before reaching them →
  they're gone forever.
- This creates the core loop: *greed vs. caution*. Do you push deeper with 5,000 runes on
  you, or bank them by leveling up first?

### Sites of Grace (checkpoints)
- Resting at a Grace: refills HP/stamina, refills healing flasks, **respawns all enemies**.
- Acts as: spawn point, level-up menu, fast-travel node (between discovered Graces),
  the warm safe beat between dangerous stretches.

### Healing
- **Ember Flask** (the Estus equivalent): limited charges, refilled at Graces. Drinking is
  a slow animation that leaves you vulnerable — healing is itself a risk/reward decision.
- Charges increase by finding upgrade items in the world.

---

## 7. ENEMY & BOSS DESIGN

### Enemy AI state machine (the spec for every enemy)
```
IDLE → (player enters aggro range) → AGGRO
AGGRO → CHASE (pathfind toward player)
CHASE → (player in attack range) → WINDUP (telegraph) → ATTACK → RECOVERY → CHASE
any state → (player leaves leash range) → RETURN (walk back to spawn, reset)
any state → (HP <= 0) → DEAD (drop runes, despawn)
```

### Boss design rules (what makes a good Souls boss)
1. **Readable tells.** Every attack has a wind-up animation the player can learn.
2. **Punish windows.** After a boss attack/combo, there's a window to deal 1–2 hits. Greed
   beyond that gets punished.
3. **Phase transitions.** Bosses gain new moves at HP thresholds (e.g. 50%). Keeps the
   fight escalating and the player adapting.
4. **A fog gate.** Bosses live behind a fog wall; entering commits you. A Grace sits just
   outside for quick retries (fast death-to-retry loop is essential).
5. **Health bar + name.** Boss UI appears on engage. Defeat = dramatic moment + big rune
   reward + permanent world change.

---

## 8. STORYTELLING SYSTEMS

- **Item descriptions**: every weapon, armor, and consumable has flavor text that drops
  a fragment of lore. This is the primary storytelling channel.
- **Environmental**: the cathedral half-sunk in the shore, the embers in the dead forest,
  the frozen throne — the world's state IS the backstory.
- **NPCs**: 3–4 in the MVP. Each has a short questline that ends, usually tragically. They
  move through the world as you progress. (e.g. a hollowing knight you meet at the shore,
  encounter again in the wood going mad, and find dead at the throne.)
- **The three endings**:
  - **Rekindle** — restore the Ember, sacrifice yourself. (Order, at a cost.)
  - **The Long Dark** — let it die. (Freedom, at a cost.)
  - **The Usurper** (hidden) — find all lore fragments + complete a specific NPC quest to
    unlock a third path: take the Ember's power for yourself without burning. The "true
    ending" for thorough players.

---

## 9. ART & AESTHETIC DIRECTION

- **Palette**: desaturated, cold. Greys, ash-blues, bone-whites. The ONLY warm color is
  the Ember — gold/amber light. Embers, Graces, and fire should *glow* against the cold,
  drawing the eye and meaning the same thing everywhere: warmth, safety, the goal.
- **Lighting**: heavy use of Roblox's lighting (Future lighting, bloom on embers, fog for
  atmosphere and to hide draw distance). Dark, moody, volumetric where possible.
- **Sound**: sparse. Wind, distant bells, the crackle of Graces. Music ONLY in boss fights
  and at Graces — silence everywhere else makes the world feel dead and lonely.
- **UI**: minimal, diegetic where possible. Thin, elegant, gold-on-dark. Restrained
  typography. The HUD fades when not in combat.

---

## 10. MVP BUILD SEQUENCE (how to actually ship this)

The full vision above is the north star. Here's the order to BUILD it, each step
independently testable. Do NOT skip ahead — each builds on a tested foundation.

**Phase 0 — Combat core** ✅ (done: stamina, attack, dodge) + animation (in progress)

**Phase 1 — One real enemy.** A single melee enemy with the full AI state machine
(idle→aggro→chase→windup→attack→recovery→leash→death) that drops runes. THIS is the next
prompt. Get one enemy feeling great before anything else.

**Phase 2 — The rune economy + death loop.** Runes earned on kill, dropped on death,
recoverable once. Player HP + death + respawn.

**Phase 3 — Sites of Grace.** Checkpoint that heals, respawns enemies, and is your spawn
point. Add the Ember Flask healing system.

**Phase 4 — Stats + leveling.** Vigor/Endurance/Strength/Dex, level-up menu at Grace,
runes as the cost.

**Phase 5 — First boss.** The Tide-Drowned Knight: fog gate, boss health bar, telegraphed
moves, punish windows, one phase transition, big rune reward.

**Phase 6 — Build Area 1.** Actually construct the Ashen Shore: terrain, lighting,
enemy placement, the Grace, the fog gate. The first *playable slice*.

**Phase 7+ — Content scaling.** Areas 2 & 3, more enemies, bosses, NPCs, items, the
ending fork. This is where it becomes a game rather than a demo.

The MVP "done" line: **Phase 6.** A player can wash up on the shore, fight enemies, manage
the rune economy, rest at a Grace, level up, and beat the first boss. That's a complete,
difficult, atmospheric vertical slice that proves the whole game — and it's small enough
to actually finish.
