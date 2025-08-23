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

- Manufacturing: assembling machines, furnaces
- Mining: mining drills, agricultural towers
- Fluids: pumps, offshore pumps
- Power: electric poles, solar panels, accumulators, generators, reactors, boilers, heat pipes, power switches, lightning rods
- Combat: turrets, artillery turrets, walls, gates, radar
- Logistics: inserters, beacons, roboports
- Space Age: asteroid collectors, thrusters, cargo landing pads
- Other: labs, combinators, programmable speakers, lamps

They can be toggled off in the settings if you want to avoid affecting certain items.

Secondary entities do not have a way to track their work (like solar panels or inserters). These recieve upgrade attempts proportional to the primary entities, ensuring they evolve at about the same rate. Details on the algorithm can be found below.

**Customization options**

- Work time needed: How many hours a machine must work for each upgrade attempt (default: 3 hours)
- Upgrade chance: Base probability of success per attempt (default: 1%)
- Luck accumulation: Failed attempts slightly increase future chances (optional)
- Quality scaling: Higher quality levels can require more work time (optional)
- Entity selection: Choose which types of entities are eligible

**Notifications**

A silent map ping is on by default, which highlights entities that change. This should be a non-obtrusive way to know that things are happening. It can be toggled off in player settings.

An aggregate report (off by default) is available which will ping the console with a breakdown of how many entities changed. It is displayed once every 5 minutes to avoid spamming. This one makes a console notification sound.

**In game commands**

Inspect entity: control-shift-q will inspect the entity under the cursor and print out stats about its current progression.

If you need to rebuild the cache (shouldn't be needed, but just in case), there is a console command available: `quality-control-init`

**High performance**

Designed to run smoothly on massive bases. The mod processes a few machines each tick to avoid lag spikes, and includes settings (under the map tab) to tune the performance further.

Adding the mod to an existing save game may cause some lag as it scans everything. Once all the entities are scanned it will go back to normal.

**Compatibility**

Works great with mods that add extra quality tiers. Please let me know if I missed one, it's easy to add support.

It may not work with mods that replace entities in a non-standard way. It shouldn't error out, it just may not track them properly.

**Unsupported Entity Types**

There are a few entity types that are not supported yet: belts, pipes, rails, and storage containers.

Belts and rails tend to have very high counts; performance testing shows that it should be fine, but there may be memory impacts or file size impacts. Also unsure if there is a UPS impact for items on a belt that transition between quality segments, will need to do more testing.

Pipes are similar, it should be fine to add but haven't tested to see if there are any weird edge cases with lots of quality changes in a single pipeline.

Storage containers change size when their quality adjusts, so that may cause issues. Some testing is needed to see how things like reserved slots or blocked slots work. Also if quality degrades - should extra items spill out?

There may be some other edge cases with rails, like what happens if a rail is changed when a train is moving over it, or if a rail signal is replaced when in a certain state, will it retain that state? Overall, need to do some more testing.


**Inspiration**

This mod was inspired by a few others:

[Factory Levels](https://mods.factorio.com/mod/factory-levels)
[Experience for Buildings](https://mods.factorio.com/mod/xp-for-buildings)
[Level Up](https://mods.factorio.com/mod/levelup)

After implementing this I found [Upgradeable Quality](https://mods.factorio.com/mod/upgradeable-quality), which has a few similarities to this mod.

--

*More technical details and performance info is available on the [github repo](https://github.com/aarons/factorio-quality-control)*
