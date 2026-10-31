# Upgrade celebration checklist

Add optional cosmetic effects for successful quality upgrades, one effect at a time.
Players choose individual effects and mix them freely. Stronger bundled presets are
deferred. Unchecked items are planned work, not implemented features.

## First pass (2026-10-31)

The current implementation adds seven independent opt-in styles using game assets
and rendering primitives: colorful chat, GPS pings, floating text, quality halos,
rainbow rings, spinning quality badges, and the built-in research-completed sound.
Both machine and independent module upgrades use them. Existing custom alerts and
five-minute summaries retain their own toggles and defaults. Delivery now respects
connected recipients and force membership.

Per the revised scope, announcement queues, batching, debounce, frequency limits,
concurrency caps, combos, and choreography are deferred. Each enabled style fires
immediately for every upgrade. Drawings have explicit 90-tick lifetimes and cleanup;
their positions are captured so entity replacement does not invalidate them.
Cosmetics do not consume gameplay randomness. Modded quality names, colors, and
icons come from their prototypes.

The implementation and automated checks are separate from visual/audio review.
Appearance, timing, and sound levels still need a client-side playtest before the
effects below can be marked fully reviewed. Custom artwork, voices, HUDs, and the
other unimplemented effects remain future work.

## Agreed design

- Every new effect has an independent per-player toggle. Keep existing map alerts and
  aggregate summaries independently selectable too.
- Separate visual effects, chat/map messages, sound effects, and announcer controls.
- Sequence enabled effects as anticipation, reveal, celebration, then fade. Skip disabled
  stages naturally; no effect should require enabling another effect.
- Apply the actual upgrade immediately. Any reveal presents an already determined result.
- Keep cosmetics separate from progression, including random number generation.
- Use explicit effect lifetimes. Queues and concurrency limits are deferred for
  the first pass; revisit them if upgrade bursts warrant it.
- Implement and review one effect at a time before moving to the next.

## Shared foundation

- [ ] Route successful upgrades through one notification entry point, carrying the old
  quality, new quality, upgraded entity, position, surface, force, and event tick.
- [ ] Deliver notifications to eligible players using their own settings, replacing the
  current `game.players[1]` assumption. Define recipient scope so unrelated forces do not
  receive upgrade information.
- [ ] Add independent per-player toggles as each effect is implemented; preserve existing
  notification preferences and keep new effects opt-in.
- [ ] Prefer player-filtered rendering for world effects so multiplayer preferences work
  independently. Avoid shared surface particles for effects that must be player-specific.
- [ ] Attach effects to the replacement entity or a captured position; handle entities
  being destroyed, replaced again, or moved to another surface.
- [ ] Separate cosmetic randomness from the random stream used for upgrade outcomes.
- [ ] Add explicit lifetimes and cleanup for rendering objects, GUI elements, and queued
  work, including save/load, disconnects, and settings changes.
- [ ] Set per-player and overall limits for concurrent visuals and queued work. Merge or
  expire excess celebrations without losing counts needed for summaries.
- [ ] Add reduced-motion controls and separate sound-effect and announcer volume controls.
- [ ] Let celebration strength respond to the resulting quality within enabled effects.
  Support modded qualities and configured maximums without assuming legendary is the end.

## Queue and announcement timing

- [ ] Add a bounded per-player announcement queue that combines bursts into counts such
  as `×20 UPGRADES` instead of replaying every announcement separately.
- [ ] Decide which channels use aggregation and which world effects remain immediate.
  Keep announcement batching separate from the short choreography of a visual effect.
- [ ] Add a configurable grouping/debounce period; consider the proposed 0–600 second
  range. Define 0 as no intentional grouping delay while retaining concurrency limits.
- [ ] Define whether the period is a fixed collection window or resets after each upgrade.
  If it resets, enforce a maximum wait so continuous upgrades cannot postpone delivery forever.
- [ ] Add a frequency limiter and serialize announcer playback to avoid overlapping voices.
- [ ] Preserve counts and notable quality results when merging events. Define what an
  announcement says when a group contains different machines or quality levels.
- [ ] Define combo windows and phrase priority separately from batching. A long summary
  interval should not automatically count as a rapid upgrade streak.
- [ ] Keep queue servicing independent of new upgrades so the final pending announcement
  is delivered even if no further upgrades occur.
- [ ] Define expiry and overflow behavior so long waits cannot produce an endless backlog
  of stale sounds or visual reveals.

## Chat and map effects

- [ ] Preserve the existing entity-linked custom alert as its own toggle.
- [ ] Preserve the existing five-minute aggregate console summary as its own toggle;
  define its relationship to the new configurable announcement queue to avoid duplicates.
- [ ] Add native GPS map pings through location-tagged messages, independently of custom
  alerts. Explain that the native ping includes a console message.
- [ ] Add individual upgrade chat messages with localized machine and quality names/icons.
- [ ] Add optional static rainbow lettering to chat announcements. Animated rainbow text
  belongs in world text or a HUD, not ordinary console messages.
- [ ] Add grouped chat announcements such as `×20 UPGRADES`, with useful quality highlights.

## World visual effects

- [ ] Floating quality text or icon: rising `RARE!`, `LEVEL UP!`, or the resulting quality badge.
- [ ] Floating combo text: `×5 COMBO!` or another grouped count with a defined location policy.
- [ ] Single quality-colored expanding halo around the upgraded machine.
- [ ] Multiple expanding rainbow rings.
- [ ] Rotating arcs around the machine.
- [ ] Brief color and opacity pulses.
- [ ] Starburst or outward rays.
- [ ] Rising sparkles or stars.
- [ ] Confetti burst.
- [ ] Spinning quality badge above the machine.
- [ ] Cosmetic flame crown around the machine.
- [ ] Expanding harmless fire wave originating at the machine.
- [ ] Rainbow coloring for the fire wave, fading into stars when both effects are enabled.
- [ ] Animated rainbow world text or badge coloring.

Use rendering primitives where practical and custom animation artwork where necessary.
Fire effects must remain cosmetic: no damage, ignition, collision, or progression changes.
Specific reusable vanilla artwork still needs verification before choosing assets.

## Sound effects and retro announcers

- [ ] Short upgrade chime.
- [ ] Distinct quality-dependent sound variants.
- [ ] Brighter arcade upgrade sound.
- [ ] Fanfare for a notable upgrade.
- [ ] Jackpot sound for an exceptional result.
- [ ] Chest/reel anticipation sound followed by a reveal accent.
- [ ] Retro announcer system using supplied voice assets, independent of non-voice sounds.
- [ ] `DOUBLE UPGRADE!` for two upgrades within the chosen combo window.
- [ ] `QUALITY SPREE!` for an ongoing chain; define threshold and repeat behavior.
- [ ] `ULTRA GRADE!` for a major result; define qualification across vanilla and modded qualities.
- [ ] `PERFECTION!` for reaching the configured maximum; define behavior for unlimited settings.
- [ ] Dramatic quality reveal announcement such as `LEGENDARY!`, with a fallback for
  modded quality names that have no recorded voice line.
- [ ] Grouped count announcements such as `×20 UPGRADES`; decide whether the count is
  displayed alongside a generic voice cue or spoken through prepared audio assets.

Each effect or announcer phrase should be individually selectable. Final voice style,
assets, thresholds, default timing, and volume levels are chosen during implementation.

## HUD effects and sequencing

- [ ] Large quality-result banner with the machine and quality icons.
- [ ] Chest-opening reveal using a scripted sequence of GUI sprites.
- [ ] Spinning quality reel reveal as a separate selectable effect.
- [ ] Reveal rays or starburst artwork around the HUD result.
- [ ] Animated rainbow HUD lettering.
- [ ] Combo counter that grows as additional upgrades arrive.
- [ ] Coordinate enabled visuals and sounds into anticipation, reveal, celebration, and fade.
  Define composition when both chest and reel effects are enabled.
- [ ] Keep overlays brief, dismissible where appropriate, and clear of essential controls;
  allow gameplay interaction through decorative portions.

An initial choreography to evaluate in-game is roughly two seconds: badge appears,
world wave expands, chest/reel reveals the result, banner and fanfare celebrate it,
then everything fades. Treat this as a starting point, not a fixed timing requirement.

## Later visibility-aware delivery

- [ ] Research which APIs can establish whether the player can actually see the machine,
  including remote view, map view, zoom, and different surfaces. Do not equate proximity
  with on-screen visibility.
- [ ] Consider holding selected world graphics until the machine enters view.
- [ ] Define an expiry and fallback for machines that never enter view, without delaying
  the upgrade itself or replaying old celebrations indefinitely.
- [ ] Decide how deferred graphics coordinate with already delivered sounds and announcements.

Visibility-aware delivery is deferred and is not a prerequisite for the first effects.

## Completion checklist for each implementation

- [ ] Choose one effect and only the shared foundation needed to support it.
- [ ] Add its independent toggle and English localization; leave other locales to translators.
- [ ] Verify the effect by itself and mixed with previously completed effects.
- [ ] Verify two players can choose different effects without receiving each other's visuals
  or sounds, and confirm recipient scope works across forces and surfaces.
- [ ] Check isolated upgrades, sustained bursts, grouping boundaries, zero delay, long waits,
  queue expiry, and concurrency limits where relevant.
- [ ] Check entity removal/replacement, save/load, disconnects, and changing settings while
  effects or announcements are pending where relevant.
- [ ] Confirm cosmetics do not change upgrade results, manufacturing progress, or gameplay.
- [ ] Run `./validate.sh` and perform in-game visual/audio review; inspect performance under
  upgrade bursts. New locale-key failures in non-English files are expected per AGENTS.md.
- [ ] Review appearance, timing, sound levels, and reduced-motion behavior before marking
  the effect complete and moving to another item.

## Implementation references

- Existing delivery: `scripts/notifications.lua`.
- Successful upgrade hook: `scripts/core.lua`, immediately after `entity.apply_upgrade()`.
- [Player alerts, local flying text, and sound](https://lua-api.factorio.com/latest/classes/LuaPlayer.html).
- [Rendering and recipient filters](https://lua-api.factorio.com/latest/classes/LuaRendering.html).
- [Mutable render objects](https://lua-api.factorio.com/latest/classes/LuaRenderObject.html).
- [Animation prototypes](https://lua-api.factorio.com/latest/prototypes/AnimationPrototype.html).
- [Per-player GUI](https://lua-api.factorio.com/latest/classes/LuaGui.html).
- [GUI elements and sprites](https://lua-api.factorio.com/latest/classes/LuaGuiElement.html).
- [Sound assets](https://lua-api.factorio.com/latest/types/Sound.html).
- [Runtime playback options](https://lua-api.factorio.com/latest/concepts/PlaySoundSpecification.html).
- [Rich text](https://wiki.factorio.com/Rich_text).
- [Wube explanation of GPS pings](https://forums.factorio.com/viewtopic.php?t=110021).
