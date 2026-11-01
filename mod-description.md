This mod adds a chance for machines to upgrade in quality as they work.

Progression is based on the time spent working instead of the number of items completed; so an assembler making iron gears for an hour will upgrade at the same rate as an assembler making science packs.

The mod is highly configurable and comes with sensible defaults.

## Works with the whole factory
---
Nearly all entity types are supported:

- Manufacturing: assembling machines, furnaces, rocket silos
- Producers: mining drills, agriculture towers, water pumps
- Power: electric poles, solar panels, accumulators, generators, reactors, boilers, heat pipes, power switches, lightning rods
- Combat: turrets, artillery turrets, walls, gates, radar
- Logistics: inserters, beacons, roboports
- Space Age: asteroid collectors, thrusters
- Other: labs, combinators, programmable speakers, lamps, fluid pumps

## Customization options
---
Almost all settings can be enabled/disabled or min/maxed to extreme levels. Here are the main concepts:

**Work hours needed**
How many hours a machine must work for each upgrade attempt, with a broad range from as little as 3 seconds up to 1000 hours. The default is to require 1 hour of work.

**Upgrade chance**
By default, each upgrade attempt has a 3% chance of success, and grows by 0.2% with each failure.

**Difficulty scaling**
Higher quality levels can optionally require more work, if you want to slow down progression at the top end.

**Module upgrades**
Should modules in an entity be able to upgrade? By default it's off, but there are several options for controlling how these behave.

**Crafting speed affects progression**
You can decide if faster assemblers (those with beacons and speed modules) should earn upgrade attempts more quickly. By default this is off because it can compound the rate of progresion in the late game and is difficult to balance.

## Copy Paste Helper
---

The factory can end up with a lot of mixed quality entities scattered about. I made a companion mod that helps with copy pasting those elements.

[Quality Gardner](https://mods.factorio.com/mod/quality-gardener)

It will update ghosts to match items available in logistic storage. It can also automatically distribute upgraded buildings if there are higher quality ones in logistic storage just laying about.

## Turrets
---

New for version 2.1.0 - turrets generate upgrades by dealing damage. The default value is calculated as 36,000 damage, the equivalent of an hour of piercing ammo production at crafting speed 1.

## Notifications
---

These are unobtrusive by default, but you can enable more bling and whimsy courtesy of a feature suggestion from Lady_Lucina - thank you for the idea!!

Default settings that are turned on:
- A silent map ping
- Quality bubbles

Other notification options:
- Instrumental and Musical notes
- An aggregated summary report
- Spinning quality badge
- and more

Examples:

![bubbles](https://github.com/aarons/factorio-quality-control/blob/main/assets/notifications/bubbles.mp4?raw=true)

![badge](https://github.com/aarons/factorio-quality-control/blob/main/assets/notifications/badge.mp4?raw=true)


## Optimized performance
---

Designed to run smoothly on massive bases. The mod processes a few machines each tick to avoid lag spikes, and includes settings (under the map tab) to tune the performance further.

Adding the mod to an existing save game may cause an initial lag spike as it scans everything. Once all the entities are scanned it will go back to normal.


## Compatibility
---

**Supported**

This works well with mods that add extra quality tiers.

**Unsupported - but still fine to use alongside**

Some modded entities don't do well with quality changes. This mod is generally safe to use along side them, but their entities are filtered out to prevent issues. There may be some that are not discovered yet.

- [Warp Drive Machine](https://mods.factorio.com/mod/Warp-Drive-Machine)
- [Quality Condenser](https://mods.factorio.com/mod/quality-condenser)
- [Realistic Reactors Reborn](https://mods.factorio.com/mod/RealisticReactorsReborn)
- [Circuit-Controlled Routers](https://mods.factorio.com/mod/router)
- [Bulk Rail Loader 2.0 Temporary Patch](https://mods.factorio.com/mod/railloader2-patch)
- [Miniloader Redux](https://mods.factorio.com/mod/miniloader-redux)

In general, this mod avoids altering hidden or indestructible entities in the game.

**Unsupported Entity Types**

There are a few entity types that are not supported: belts, pipes, rails, and storage containers.

## Localization
---
The localizations are AI generated. Corrections are very welcome!

Supported languages: Belarusian, Catalan, Chinese (Simplified), Chinese (Traditional), Czech, Dutch, Finnish, French, Georgian, German, Greek, Hungarian, Italian, Japanese, Kazakh, Korean, Latvian, Norwegian, Polish, Portuguese (Brazil), Portuguese (Portugal), Romanian, Russian, Spanish (Latin America), Spanish (Spain), Swedish, Thai, Turkish, Ukrainian, Vietnamese.

## Inspiration
___

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)
[Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality)

