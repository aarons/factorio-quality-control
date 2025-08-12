This mod introduces a small chance to update the quality of machines based on how hard they are working. You can choose whether they get better over time, or worse.

**Retains gacha mechanic**

The default settings will retain the gacha spirit of Factorio's quality mechanic; machines have a chance to change quality each time the hours worked threshold is passed. If the change fails then the quality will stay stable until the next threshold is passed.

If you prefer to have changes guaranteed then you can set the percentage chance to 100.

**Fair assembler treatment**

The mod tracks manufacturing hours by accounting for recipe duration, ensuring fair treatment regardless of what an assembler is working on. An assembler making gears will change at the same rate as one making science packs, as long as they are actively working.

**Support for most entities**

Some entities, such as solar panels or inserters, do not have a way to track how hard they are working. This mod tracks the rate that assemblers and furnaces are changing in your base, and then applies that rate to secondary entities that don't have tracking. This way other entities will change at about the same rate as your assemblers.

Machines that are at max quality and can no longer change will not pull down the rate, but machines that are sitting around idle will lower the overall rate.

You can select which entities should be included or excluded in the settings.

![settings example image](settings.png)

There are a few entities that aren't supported: belts, pipes, and storage items. These should be fine to add in if desired; some performance work was completed that should make adding these a non-issue.

**Gameplay experience**

There are a number of settings that can tune the overall gameplay experience. These are also explained in the tooltips in game.

Manufacturing hours for change - set how many hours an assembler needs to work to be eligible for a quality bump. Their crafting speed impacts how quicly they work through the hours needed. If hours needed is set to 3, then an assembler with crafting speed 0.5 needs to work 6 real hours of gameplay before a quality change is attempted. An assembler with crafting speed of 6 would take 30 minutes of gameplay before a change is attempted.

Chance accumulation - optional setting that increases the chance that a change will occur over time. After a quality change fails this will then bump up the chance for the next attempt. By default this is set to low, which will increase the chance by 20% of the base rate each time.

At the default rate of 1% chance and low accumulation, there will usually be a change after 22 attempts. Or another way to look at it is that 22 assemblers with crafting speed 1 will experience one change every 3 hours. With chance accumulation turned off then the 1% chance will stay steady, and it will take about 69 attempts before seeing a change.

Cost increases per quality level - this will make higher quality levels more sticky; assemblers will need to work longer before seeing a change. This will stabilize the base at later stages and slow down progression if desired. Default is set to 50% (compounding). If manufacturing hours is set to 3 for normal quality, then this will scale up to about 10 manufacturing hours needed per attempt at Epic quality.

**Optional Notifications**

By default, a silent map ping is turned on to highlight entities that change. This should be a non-obtrusive way to know that things were happening.

![notification image](map.png)

There is an optional aggregate report, which will ping the console with a breakdown of how many entities changed (maximum of 1 report every 5 minutes, so you don't get spammed). This one does make noise.


**Performance**

A fair amount of performance tuning and testing went into this, it shouldn't impact UPS or gameplay noticeably for large bases on fast machines.

There are map settings that can be used to optimize things further if you do notice an impact. The settings available are number of units processed each time and how often they are processed. The default is 10 units per 1 tick.

Some testing on an m2 mac:

- A base with 2,000spm (vanilla, not yet at promethium science) was totally fine, UPS steady at 60
- A base with 30,000spm (modded, all sciences) was also fine: UPS stayed at about 60 (it was already fluctuating a bit before the mod, and adding it seemed about the same)
- Average milliseconds used over 100 ticks on my largest modded base was around 0.5ms. For reference, 1 tick in the game is 16.67ms, and all game and mods share that; so the less used the better.
- 100 units per 1 tick had no noticeable impact.
- 1000 units per 1 tick started to introduce noticeable lag.

When adding the mod to an existing save game it will take a moment to scan everything; this can introduce an initial lag spike that lasts a second or two. Once entities are scanned it will go back to normal.

**Other Quality Mods**

This works well with other mods that change quality levels (including infinite-quality). Please let me know if I missed one, it's easy to add support.

It may not work with mods that replace entities already in the game; it depends on if they call

**Inspiration**

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)

After implementing this I found [Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality), which has a few similarities to this mod.


