# BRIGHT SOULS — Build Checklist

Companion to GDD.md. One phase at a time. Do NOT start a phase until the
previous one's "Definition of done" is fully checked. Each phase ends with a git commit
so you can always roll back to a working state.

Legend:
- `[ ]` Code task (Claude Code does this)
- `(STUDIO)` You do this in Roblox Studio — Claude Code can't
- `(TEST)` Verification step — must pass before moving on

---

## PHASE 0 — Combat Core ✅ (DONE)

- [x] Rojo project + Config.lua + RemoteEvents
- [x] Stamina system (drain, delayed regen, throttled sync)
- [x] Light attack (hitbox, damage, dedupe, i-frame respect)
- [x] Dodge roll (directional, i-frames, LinearVelocity)
- [x] Attack animation (built-in ID, client-side playback, respawn-safe)
- (TEST) Left-click drains stamina + damages a dummy
- (TEST) Q dodges with a visible dash
- (TEST) Animation plays on attack
- [x] `git commit -m "Phase 0: combat core + attack animation"`

---

## PHASE 1 — One Real Enemy

**Goal:** A single melee enemy with a full AI state machine that feels great to fight.

- [x] Create `src/server/EnemyAI.server.lua`
- [x] Add enemy Config values (HP, speeds, ranges, damage, windup, rune reward)
- [x] CollectionService "Enemy" tag detection (existing + GetInstanceAddedSignal)
- [x] Per-enemy state table (state, spawnPos, target, lastAttack)
- [x] State machine: IDLE → AGGRO → CHASE → WINDUP → ATTACK → RECOVERY
- [x] LEASH/RETURN behavior (walks home if player flees past leash range)
- [x] WINDUP telegraph (sets "Telegraphing" attribute, waits, then damages only if
      player still in range — the dodge payoff)
- [x] DEATH handler (drop runes attribute, wait 3s, despawn, clean up state)
- [x] Confirm existing player hitbox damages the enemy (do NOT duplicate damage logic)
- (STUDIO) Place a dummy rig in the workspace
- (STUDIO) Tag it "Enemy" via the Tag Editor (View → Tag Editor)
- (TEST) Enemy is idle until you approach within aggro range
- (TEST) Enemy chases you, telegraphs before swinging
- (TEST) Dodging the telegraph means you take NO damage
- (TEST) Running away past leash range makes it walk home and reset
- (TEST) Killing it makes it despawn (check it had a Runes attribute set)
- [x] `git commit -m "Phase 1: melee enemy AI state machine"`

---

## PHASE 2 — Rune Economy + Death Loop

**Goal:** The core Souls tension — earn runes, lose them on death, recover them once.

- [ ] Create `src/server/PlayerData.server.lua` — per-player runes, HP tracking
- [ ] Award runes on enemy death (read the enemy's Runes attribute, add to killer)
- [ ] Create `src/client/RuneUI.client.lua` — rune counter on screen
- [ ] StaminaSync-style remote to sync rune count to client
- [ ] On player death: spawn a "bloodstain" part at death location holding the runes
- [ ] Player drops ALL runes into the bloodstain on death
- [ ] Touching the bloodstain returns the runes (and removes it)
- [ ] If player dies again before recovering: delete the old bloodstain (runes lost)
- [ ] Respawn handling (player returns to a spawn point — temp spawn for now)
- (TEST) Killing an enemy increases your rune count on screen
- (TEST) Dying drops a bloodstain with your runes; counter resets to 0
- (TEST) Walking back to the bloodstain restores the runes
- (TEST) Dying twice in a row permanently loses the first bloodstain
- [ ] `git commit -m "Phase 2: rune economy + death/recovery loop"`

---

## PHASE 3 — Sites of Grace + Healing

**Goal:** Checkpoints that heal, respawn enemies, and become your spawn point.

- [ ] Create `src/server/GraceSystem.server.lua`
- [ ] CollectionService "Grace" tag for checkpoint parts
- [ ] Interact prompt (ProximityPrompt) on each Grace
- [ ] Resting: refill HP + stamina, refill Ember Flasks, set this Grace as spawn point
- [ ] Resting respawns all "Enemy"-tagged enemies (re-clone from stored originals)
- [ ] Create `src/client/FlaskUI.client.lua` — flask charge counter
- [ ] Ember Flask healing: limited charges, slow drink animation, heals a chunk of HP
- [ ] Flask drinking leaves you vulnerable (no i-frames, can be interrupted by damage)
- [ ] Respawn on death now sends player to last-rested Grace
- (STUDIO) Place a Grace part in the workspace, tag it "Grace", give it a glow
- (TEST) Interacting with a Grace heals you and refills flasks
- (TEST) Resting respawns dead enemies
- (TEST) Drinking a flask heals but locks you in a vulnerable animation
- (TEST) Dying returns you to the last Grace you rested at
- [ ] `git commit -m "Phase 3: sites of grace + ember flask healing"`

---

## PHASE 4 — Stats + Leveling

**Goal:** Spend runes at a Grace to permanently raise stats.

- [ ] Add stats to PlayerData: Vigor, Endurance, Strength, Dexterity (start at base)
- [ ] Vigor → max HP, Endurance → max stamina (wire into existing stamina/HP systems)
- [ ] Rune cost formula (each level costs more than the last)
- [ ] Create `src/client/LevelUpUI.client.lua` — level-up menu opened from a Grace
- [ ] Spend runes to +1 a stat; deduct runes, apply stat effect, close menu
- [ ] Equip load groundwork: roll type (light/medium/heavy) based on Endurance (stub
      armor weight as 0 for now — full equipment is post-MVP)
- (STUDIO) Add a "Level Up" option to the Grace ProximityPrompt menu
- (TEST) Leveling Vigor raises and refills your max HP
- (TEST) Leveling Endurance raises your max stamina
- (TEST) Rune cost increases each level; can't level without enough runes
- [ ] `git commit -m "Phase 4: stats + leveling at grace"`

---

## PHASE 5 — First Boss: The Tide-Drowned Knight

**Goal:** A real boss fight — fog gate, health bar, telegraphs, punish windows, a phase.

- [ ] Create `src/server/BossAI.server.lua` (extends the enemy state machine)
- [ ] Boss config: high HP, multiple attacks, telegraph times, punish windows
- [ ] Multiple attack patterns (e.g. overhead slam, horizontal sweep, lunge) chosen
      semi-randomly, each with its own telegraph + recovery
- [ ] Phase transition at 50% HP — gains a new move / faster recovery
- [ ] Create `src/client/BossUI.client.lua` — boss name + health bar on engage
- [ ] Fog gate: a wall part that the player walks through to start the fight; seals
      behind them (removed on boss death or player death)
- [ ] Big rune reward on boss death + remove fog gate permanently
- (STUDIO) Build/place the boss rig (a larger dummy for now), tag appropriately
- (STUDIO) Place the fog gate part + a Grace just outside it (fast retry loop)
- (TEST) Walking through the fog gate starts the fight + shows the boss bar
- (TEST) Each boss attack has a readable telegraph you can dodge
- (TEST) There's a window to land hits after the boss attacks
- (TEST) Boss changes behavior at 50% HP
- (TEST) Death-to-retry is fast (Grace right outside the fog)
- (TEST) Killing the boss grants runes + opens the gate
- [ ] `git commit -m "Phase 5: first boss - tide-drowned knight"`

---

## PHASE 6 — Build Area 1: The Ashen Shore (MVP DONE LINE)

**Goal:** Assemble everything into the first playable slice.

- [ ] (mostly STUDIO) Most of this phase is level building, not code
- (STUDIO) Terrain: grey beach, broken ships, the half-sunk cathedral
- (STUDIO) Lighting: cold palette, fog for atmosphere, Future lighting, bloom on embers
- (STUDIO) Place 4–6 Hollow Drifter enemies along the path, tagged "Enemy"
- (STUDIO) Place the first Site of Grace near the start
- (STUDIO) Place the fog gate + boss arena at the end of the area
- (STUDIO) Set the player's initial spawn at the shore
- [ ] Any glue code needed to tie spawn → path → boss together
- [ ] Sound: ambient wind, Grace crackle (post if time allows)
- (TEST) Full loop: spawn → fight enemies → earn runes → rest at Grace → level up →
        beat the boss. End to end, no soft-locks.
- (TEST) Dying anywhere returns you to the Grace with the rune-recovery loop intact
- [ ] `git commit -m "Phase 6: Ashen Shore playable slice (MVP complete)"`

**🎯 MVP COMPLETE.** A difficult, atmospheric vertical slice that proves the whole game.

---

## PHASE 7+ — Content Scaling (post-MVP)

Once the MVP slice is solid and fun, expand. Each is its own mini-project:

- [ ] Heavy attack, blocking, backstabs/ripostes, poise
- [ ] Lock-on targeting
- [ ] Weapon movesets + the equipment/inventory system
- [ ] Area 2 (Emberwood) + Mother of Cinders boss
- [ ] Area 3 (Coldhearth) + final boss
- [ ] NPC questlines + item-description lore
- [ ] The three-ending fork
- [ ] Fast-travel between discovered Graces
- [ ] Save system (DataStore) — persist runes, stats, lit Graces, beaten bosses

---

## WORKING RULES (for every phase)

1. **One phase at a time.** Finish the Definition of done before the next prompt.
2. **Test in Studio after every generation.** Code that compiles can still misbehave
   in-engine (rigs, animations, physics are runtime-only).
3. **Commit at each phase boundary.** Working checkpoints you can roll back to.
4. **Tune from Config, not from logic.** Feel problems (too hard, too fast, too floaty)
   are almost always a number in Config.lua — change it, Rojo re-syncs, retest.
5. **Additive prompts.** Tell Claude Code what NOT to touch ("don't change CombatServer")
   so it doesn't rewrite working systems.
6. **Report behavior, not just errors.** When something feels off in a playtest, describe
   what happened — that's how the numbers get dialed in.
