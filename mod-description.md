This adds a chance for machines to upgrade in quality as they work. The harder they work, the more opportunities they get to change quality levels.

If you feel extra spicy you can change the settings to degrade in quality instead.


## Gacha-style progression
---
Individual machines roll for quality upgrades when they hit work milestones, similar to the chance-based progression of Factorio's quality system. By default there's a 1% chance per attempt, but you can adjust this up to 100% for guaranteed upgrades.

If an upgrade attempt fails, the machine tries again when it reaches the next milestone.

## Fair assembler treatment
___
Every assembler progresses at the same rate when actively working. An assembler making iron gears will upgrade just as fast as one making science packs - what matters is the time spent working, not what they're making.

Crafting speed does impact progression though; an assembler with crafting speed of 2 will change twice as fast as an assembler with crafting speed 1.

## Works with the whole base
___
Just about all entity types are supported. Here's the full list:

- Manufacturing: assembling machines, furnaces, rocket silos
- Mining: mining drills, agricultural towers
- Fluids: pumps, offshore pumps
- Power: electric poles, solar panels, accumulators, generators, reactors, boilers, heat pipes, power switches, lightning rods
- Combat: turrets, artillery turrets, walls, gates, radar
- Logistics: inserters, beacons, roboports
- Space Age: asteroid collectors, thrusters
- Other: labs, combinators, programmable speakers, lamps

They can be toggled off in the settings if you want to avoid affecting certain items.

Secondary entities do not have a way to track their work (like solar panels or inserters). These receive upgrade attempts proportional to the primary entities, ensuring they evolve at about the same rate.

## Customization options
---

- Work time needed: How many hours a machine must work for each upgrade attempt (default: 3 hours)
- Upgrade chance: Base probability of success per attempt (default: 1%)
- Luck accumulation: Failed attempts slightly increase future chances (optional)
- Quality scaling: Higher quality levels can require more work time (optional)
- Entity selection: Choose which types of entities are eligible

## Other Features
---
**Notifications**

A silent map ping is on by default, which highlights entities that change. This should be a non-obtrusive way to know that things are happening. It can be toggled off in player settings.

An aggregate report (off by default) is available which will ping the console with a breakdown of how many entities changed. It is displayed once every 5 minutes to avoid spamming. This one makes a console notification sound.

**In game commands**

Inspect entity: control-shift-q will inspect the entity under the cursor and print out stats about its current progression.

If you need to rebuild the cache (shouldn't be needed, but just in case), there is a console command available: `quality-control-init`

## High performance
---

Designed to run smoothly on massive bases. The mod processes a few machines each tick to avoid lag spikes, and includes settings (under the map tab) to tune the performance further.

Adding the mod to an existing save game may cause some lag as it scans everything. Once all the entities are scanned it will go back to normal.

## Compatibility
---

**Supported**

This works great with mods that add extra quality tiers. If you find one that doesn't work please let me know as it's generally quick to add support.

**Unsupported - but still fine**

Some modded items don't do well with quality changes. This mod is generally safe to use along side them, but their entities are filtered out to prevent issues. So far that includes:

- [Warp Drive Machine](https://mods.factorio.com/mod/Warp-Drive-Machine)
- [Quality Condenser](https://mods.factorio.com/mod/quality-condenser)
- [Realistic Reactors Reborn](https://mods.factorio.com/mod/RealisticReactorsReborn)
- ControlTech updated for Factorio 2
- Circuit-Controlled Routers
- Bulk Rail Loader 2.0 Temporary Patch
- Miniloader Redux

In general, this mod may not work well with modded entities that depart from factorio norms.

**Unsupported Entity Types**

There are a few entity types that are not supported: belts, pipes, rails, and storage containers.

There are several edge cases to handle (and test) before adding support. Things such as UPS impacts of belts with varying quality segments, rail signals being replaced at the wrong moment causing accidents, storage containers changing size and losing blocked slots etc. It's all do-able, just not a priority. If you are interested in beta testing changes though, let me know on the discussion page :)


## Inspiration
___

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)
[Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality)

--

*More technical details and performance info is available on the [github repo](https://github.com/aarons/factorio-quality-control)*
