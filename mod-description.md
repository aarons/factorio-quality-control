This mod introduces a small chance to update the quality of machines based on how hard they work. You can choose whether they get better over time, or worse.

**Retains gacha mechanic**

The default settings will retain the gacha spirit of Factorio's quality mechanic; machines have a chance to change quality each time a certain number of hours worked is met. If the attempt fails then the quality will stay stable until the next threshold is passed.

The chance for a change to occur is configurable up to 100%, for a more level up type experience.

**Fair assembler treatment**

The mod tracks manufacturing hours by accounting for recipe duration, ensuring fair treatment regardless of what an assembler is working on. An assembler making gears will change at the same rate as one making science packs, as long as they are both working.

**Support for most entities**

Some entities, such as solar panels or inserters, do not have a way to track how hard they are working. This mod tracks the rate that assemblers and furnaces change in your base, and applies that to secondary entities that don't have tracking. This way other entities will change at about the same rate as your assemblers.

Assemblers that are at max quality and can no longer change will not impact the rate, but machines that are sitting around idle will lower the overall rate.

You can select which entities should be included or excluded in the settings.

![settings example image](settings.png)

There are a few entities that aren't supported right now: belts, pipes, and storage items. These should be fine to add in if desired; some performance work was completed recently that should make adding these a non-issue.

**Gameplay experience**

There are several settings that can tune the overall gameplay experience.

Manufacturing hours needed - this will set how many hours an assembler needs to work for an attempted quality change. Their crafting speed impacts how quickly they work through those hours. So for example, if 3 hours are needed, then an assembler with crafting speed 0.5 needs to work for 6 real-time hours for each attempt to change. An assembler with crafting speed of 6 would need 30 minutes.

Chance accumulation - optionally increases the chance that a change will occur over time. This will bump up the chance for an entity after each attempt on it fails. By default this is set to low, which will increase the chance by 20% of the base rate after each failure.

At the default rate of 1% chance and low accumulation, there will usually be a change after 22 attempts. Or another way to look at it is that 22 assemblers with crafting speed 1 will experience one change every 3 hours. With chance accumulation turned off then the 1% chance will stay steady, and it will take about 69 attempts before seeing a change.

Cost increase per quality level - this will make higher quality levels more sticky; assemblers will need to work longer before seeing a change. This will stabilize things at later stages and slow down progression if desired. Default is set to 50% (compounding), and it can be set to most any value (including 0%). At 50%, if manufacturing hours are set to 3 for normal quality, then this will scale up to about 10 manufacturing hours needed per attempt at Epic quality.

If you use mods that add quality levels, then 50% compounding will bump the hours needed for each attempt beyond legendary extremely fast (level 10 == 170 hours per attempt). A lower value of 7% will double the cost every 10 levels, and 3.5% doubles every 20 levels. 0% is also fine to use, it just means higher crafting speed machines will progress very quickly.

**Optional notifications**

By default, a silent map ping is turned on to highlight entities that change. This should be a non-obtrusive way to know that things were happening.

![notification image](map.png)

There is an optional aggregate report (default off), which will ping the console with a breakdown of how many entities changed (maximum of 1 report every 5 minutes, so you don't get spammed). This one does make some noise.

**In game commands**

Inspect entity: control-shift-q will inspect the entity under the cursor and print out some stats about its current progression, attempts to change quality, and chance that the next attempt will succeed.

If you want to forcefully rebuild the cache (shouldn't ever be needed, but just in case), there is a console command available: `quality-control-init`

**Good performance**

The mod has been tuned to perform well on large bases, it shouldn't impact UPS or gameplay noticeably.

There are map settings that can be used to optimize things further if you do notice an impact. The settings are:
- number of units processed at once (default 10)
- how often they are processed (default every tick)

The default is 10 units every 1 tick. From testing, it's better to do few units more often, instead of a huge batch infrequently, otherwise you may experience lag spikes in the late game.

More performance info is available on the [github repo](https://github.com/aarons/factorio-quality-control)

When adding the mod to an existing save game it will take a moment to scan everything; this can introduce an initial lag spike that lasts a few seconds. Once all the entities are scanned it will go back to normal.

**Compatibility with other mods**

This works well with mods that add quality levels. Please let me know if I missed one, it's easy to add support.

It may not work with mods that replace or change entities already in the game in non-standard ways. It shouldn't error out either, just may not track them properly.

**Inspiration**

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)

After implementing this I found [Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality), which has a few similarities to this mod.
