This adds a chance for machines to upgrade in quality as they work. The harder they work, the more opportunities they get to change quality levels.

If you feel extra spicy you can change the settings to degrade in quality instead.


**Gacha-style progression**

Individual machines roll for quality upgrades when they hit work milestones, similar to the chance-based progression of Factorio's quality system. By default there's a 1% chance per attempt, but you can adjust this up to 100% for guaranteed upgrades.

If an upgrade attempt fails, the machine stays the same quality until it reaches the next milestone and tries again.


**Fair assembler treatment**

Every assembler progresses at the same rate when actively working. An assembler making iron gears will upgrade just as fast as one making science packs - what matters is the time spent working, not what they're making.

Crafting speed does impact progression though; an assembler with crafting speed of 2 will change twice as fast as an assembler with crafting speed 1.


**Works with the whole base**

Just about all unit types are supported. Here's the full list:

- Manufacturing: assembling machines, furnaces, rocket silos
- Mining: mining drills, agricultural towers
- Fluids: pumps, offshore pumps
- Power: electric poles, solar panels, accumulators, generators, reactors, boilers, heat pipes, power switches, lightning rods
- Combat: turrets, artillery turrets, walls, gates, radar
- Logistics: inserters, beacons, roboports
- Space Age: asteroid collectors, thrusters, cargo landing pads
- Other: labs, combinators, programmable speakers, lamps

They can be toggled off in the settings if you want to avoid affecting certain items.

Some entities do not have direct way to track their work (like solar panels or inserters). These use the average progression rate of the assemblers, so that they evolve at about the same rate.

Assemblers that are sitting around idle will lower the overall progression rate. Assemblers that have reached max quality will NOT lower the rate, regardless of what they are doing.


**Customization options**

- Work time needed: How many hours a machine must work before each upgrade attempt (default: 3 hours)
- Upgrade chance: Base probability of success per attempt (default: 1%)
- Luck accumulation: Failed attempts slightly increase future chances (optional)
- Quality scaling: Higher quality levels can require more work time (optional)
- Entity selection: Choose which machine types participate

**Notifications**

A silent map ping is on by default, which highlights entities that change. This should be a non-obtrusive way to know that things are happening. It can be toggled off in player settings.

An aggregate report is off by default, it will ping the console with a breakdown of how many entities changed (displayed once every 5 minutes). This one does make a sound, it can be turned on or off in the player settings.

**In game commands**

Inspect entity: control-shift-q will inspect the entity under the cursor and print out stats about its current progression.

If you need to rebuild the cache (shouldn't be needed, but just in case), there is a console command available: `quality-control-init`


**High performance**

Designed to run smoothly on massive bases. The mod processes a few machines each tick to avoid lag spikes, and includes settings (under the map tab) to tune the performance further.

Adding the mod to an existing save game may cause some lag as it scans everything. Once all the entities are scanned it will go back to normal.

**Unsupported Entity Types**

There are a few entity types that are not supported by the mod currently: belts, pipes, rails, and storage containers.

Belts tend to have very high counts; performance testing shows that it should be fine to add them, but I wanted to wait and see if anyone wants these. Also, I'm not sure if there is a performance impact of items on a belt transitioning between different quality segments

Pipes are similar, it should be fine to add but haven't tested to see if there are any weird edge cases with lots of quality changes in a single pipeline.

Storage containers change size when their quality adjusts, so that may cause issues. Some testing is needed to see how things like reserved slots or blocked slots work. Also if quality degrades - should extra items spill out?

Finally rails... I don't know what would happen if a rail changed under a train, or if a rail signal was replaced when in a certain state; it feels like a lot of shenanigans to try and test all the scenarios.

**Compatibility**

Works great with mods that add extra quality tiers. Please let me know if I missed one, it's easy to add support.

It may not work with mods that replace entities in a non-standard way. It shouldn't error out, it just may not track them properly.

**Inspiration**

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)

After implementing this I found [Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality), which has a few similarities to this mod.

--

*More technical details and performance info is available on the [github repo](https://github.com/aarons/factorio-quality-control)*
