This mod introduces a small chance to update the quality of machines based on how hard they are working. You can choose whether they get better over time, or worse.

**Retains gacha mechanic**

The default settings will retain the gacha spirit of Factorio's quality mechanic; machines have a chance to change quality each time the hours worked threshold is passed. If the change fails then the quality will stay stable until the next threshold is passed.

If you prefer to have changes guaranteed then you can set the percentage chance to 100.

**Fair assembler treatment**

The mod tracks manufacturing hours by accounting for recipe duration, ensuring fair treatment regardless of what an assembler is working on. An assembler making gears will change at the same rate as one making science packs, as long as they are actively working.

**Support for most entities**

Some entities, such as solar panels or inserters, do not have a way to track how hard they are working. This mod tracks the rate that assemblers and furnaces are changing in your base, and applies that to secondary entities that don't have tracking. This way other entities will change at about the same rate as your assemblers.

Assemblers that are at max quality and can no longer change will not impact the rate, but machines that are sitting around idle will lower the overall rate.

You can select which entities should be included or excluded in the settings.

![settings example image](settings.png)

There are a few entities that aren't supported right now: belts, pipes, and storage items. These should be fine to add in if desired; some performance work was completed that should make adding these a non-issue.

**Gameplay experience**

There are settings available that can tune the overall gameplay experience. These are also explained in the tooltips in game.

Manufacturing hours for change - set how many hours an assembler needs to work to be eligible for a quality bump. Their crafting speed impacts how quicly they work through the hours needed. If hours needed is set to 3, then an assembler with crafting speed 0.5 needs to work 6 real hours of gameplay before a quality change is attempted. An assembler with crafting speed of 6 would take 30 minutes of gameplay before a change is attempted.

Chance accumulation - optional setting that increases the chance that a change will occur over time. After a quality change fails this will then bump up the chance for the next attempt. By default this is set to low, which will increase the chance by 20% of the base rate each time.

At the default rate of 1% chance and low accumulation, there will usually be a change after 22 attempts. Or another way to look at it is that 22 assemblers with crafting speed 1 will experience one change every 3 hours. With chance accumulation turned off then the 1% chance will stay steady, and it will take about 69 attempts before seeing a change.

Cost increase per quality level - this will make higher quality levels more sticky; assemblers will need to work longer before seeing a change. This will stabilize the base at later stages and slow down progression if desired. Default is set to 50% (compounding), and it can be set to most any value (including 0%). At 50%, if manufacturing hours is set to 3 for normal quality, then this will scale up to about 10 manufacturing hours needed per attempt at Epic quality.

If you use mods that add quality levels, then 50% compounding will bump the hours needed for each attempt beyond legendary extremely fast (level 10 == 170 hours per attempt). A lower value of 7% will double the cost every 10 levels, and 3.5% doubles every 20 levels. 0% is also fine to use, it just means higher crafting speed machines will progress very quickly.

**Optional notifications**

By default, a silent map ping is turned on to highlight entities that change. This should be a non-obtrusive way to know that things were happening.

![notification image](map.png)

There is an optional aggregate report, which will ping the console with a breakdown of how many entities changed (maximum of 1 report every 5 minutes, so you don't get spammed). This one does make noise.

**In game commands**

Default shortcut key: control-shift-q will inspect the entity under the cursor and print out some stats about it's current progression, attempts to change quality, and chance that the next attempt will succeed.

If you want to forcefully rebuild the cache (shouldn't ever be needed, but just in case), there is a console command available: `quality-control-init`

**Has good performance**

The mod has been tuned to perform well on large bases, it shouldn't impact UPS or gameplay noticeably.

There are map settings that can be used to optimize things further if you do notice an impact. The settings are:
- number of units processed at once (default 10)
- how often they are processed (default every tick)

The default is 10 units every 1 tick. From testing, it's better to do few units more frequently, instead of a huge batch every once in awhile, otherwise you may experience lag spikes in the late game.

A late game base doing 1,000 spm can have ~100,000 units. At the default rate it would take about 3 minutes to check everything. If a unit has passed several thresholds between checks it's fine; no progress will be lost. All the attempted upgrades/downgrades it has earned will be applied at once. So a fast machine can be upgraded multiple times in a single pass.

More performance info is available on the [github repo](https://github.com/aarons/factorio-quality-control)

When adding the mod to an existing save game it will take a moment to scan everything; this can introduce an initial lag spike that lasts a few seconds. Once all the entities are scanned it will go back to normal.

**Compatibility with other mods**

This works well with mods that add quality levels. Please let me know if I missed one, it's easy to add support.

It may not work well with mods that replace or change entities already in the game in non-standard ways. If they have

**Inspiration**

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)

After implementing this I found [Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality), which has a few similarities to this mod.


