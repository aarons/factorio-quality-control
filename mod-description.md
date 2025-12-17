This mod adds a chance for machines to upgrade in quality as they work. The harder they work, the more opportunities they get to change quality levels.

## Gacha-style progression
---
Individual machines roll for quality upgrades when they hit work milestones, similar to the chance-based progression of Factorio's quality system. By default there's a 1% chance per attempt, but you can adjust this up to 100% for guaranteed upgrades.

If an upgrade attempt fails, the machine tries again when it reaches the next milestone. There's an optional luck parameter which increases the chance after each failure.

## Fair assembler treatment
___
Every assembler progresses at the same rate when actively working. An assembler making iron gears will upgrade just as fast as one making science packs - what matters is the time spent working, not what they're making.

Crafting speed impacts progression - an assembler with crafting speed of 2 will change twice as fast as an assembler with crafting speed 1.

## Works with the whole factory
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

These secondary entities do not have way to track their activity level (like solar panels or inserters). So these receive upgrade attempts based on the work that primary entities are doing.

## Customization options
---

- Work hours needed: How many hours a machine must work for each upgrade attempt (default: 3 hours)
- Upgrade chance: Chance of success per attempt (default: 1%)
- Luck accumulation: Whether failed attempts should increase future chances (optional)
- Cost scaling: Higher quality levels can require more work time (optional)

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

Adding the mod to an existing save game may cause an initial lag spike as it scans everything. Once all the entities are scanned it will go back to normal.

## Compatibility
---

**Supported**

This works great with mods that add extra quality tiers. If you find one that doesn't work please let me know as it's generally quick to add support.

**Unsupported - but still fine to use alongside**

Some modded entities don't do well with quality changes. This mod is generally safe to use along side them, but their entities are pro-actively filtered out to prevent issues. There may be some that are not discovered yet.

- [Warp Drive Machine](https://mods.factorio.com/mod/Warp-Drive-Machine)
- [Quality Condenser](https://mods.factorio.com/mod/quality-condenser)
- [Realistic Reactors Reborn](https://mods.factorio.com/mod/RealisticReactorsReborn)
- [Circuit-Controlled Routers](https://mods.factorio.com/mod/router)
- [Bulk Rail Loader 2.0 Temporary Patch](https://mods.factorio.com/mod/railloader2-patch)
- [Miniloader Redux](https://mods.factorio.com/mod/miniloader-redux)

In general, this mod avoids altering hidden or indestructible entities in the game.


**Unsupported Vanilla Entity Types**

There are a few entity types that are not supported: belts, pipes, rails, and storage containers.

It seems impractical to add those. It's very disruptive having mixed qualities on those kind of infrastructure items (makes it hard to copy/paste among other issues). Also not sure if there is a UPS impact if there are lots of quality changes on connected belts and pipes.

## Localization
---
There are several AI generated localizations. Corrections are very welcome!

Supported languages: Belarusian, Catalan, Chinese (Simplified), Chinese (Traditional), Czech, Dutch, Finnish, French, Georgian, German, Greek, Hungarian, Italian, Japanese, Kazakh, Korean, Latvian, Norwegian, Polish, Portuguese (Brazil), Portuguese (Portugal), Romanian, Russian, Spanish (Latin America), Spanish (Spain), Swedish, Thai, Turkish, Ukrainian, Vietnamese.

Please share any corrections on the [mod discussion page](https://mods.factorio.com/mod/quality-control/discussion) or to the [github issues](https://github.com/aarons/factorio-quality-control/issues) page.

## Inspiration
___

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)
[Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality)

