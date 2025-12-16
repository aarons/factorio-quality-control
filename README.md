# Quality Control - Factorio Mod

A Factorio mod that adds a chance for machines to upgrade in quality as they work. The harder they work, the more opportunities they get to change quality levels.

## How It Works

Quality Control will attempt to upgrade machines based on how hard they are working. The mod tracks actual manufacturing hours by accounting for recipe duration, ensuring fair progression - an assembler making gears will advance at the same rate as one making science packs.

The default configuration retains the gacha spirit of Factorio's quality mechanic; machines have a chance to upgrade when the hours worked threshold is met; if the upgrade fails then its quality will stay stable until the next threshold of hours worked is passed.

The mod is highly configurable so that it's impact on gameplay can be tuned to your liking.

## Key Features

### Entity Support

The mod tracks two categories of entities with different quality management approaches:

**Primary Entities** (control.lua):
- Assembling machines and furnaces
- Track exact manufacturing hours based on items produced × recipe duration
- Quality upgrade attempts are based on accumulated work time
- Each machine independently tracks its progress toward the next attempt

**Secondary Entities** (control.lua):
- Entities that don't have a way to measure amount of work completed
- Infrastructure: mining drills, labs, inserters, pumps, radar, roboports
- Power: electric poles, solar panels, accumulators, generators, reactors
- Defense: turrets, walls, gates
- Logic: combinators, beacons, speakers
- Space Age: lightning rods, asteroid collectors, thrusters

Secondary entities use a credit-based system - when primary entities reach upgrade thresholds, they generate credits proportional to the ratio of secondary to primary entities. Secondary entities consume these credits for upgrade attempts. This ensures infrastructure upgrades at a similar pace to production machines without requiring complex tracking for non-crafting entities.

### Manufacturing Hours

The core metric for quality progression:

```
Manufacturing Hours = (Items Produced × Recipe Duration) / 3600
```

This approach ensures fairness:
- Fast recipes (e.g., gears at 0.5s) and slow recipes (e.g., science at 30s) progress equally when running continuously
- Machines with speed modules accumulate hours faster, reflecting their increased throughput
- Idle machines don't progress toward quality changes

The system tracks the delta between checks, allowing machines to accumulate multiple threshold crossings if left running for extended periods.

### Chance-Based Changes

When a machine reaches the hours worked threshold, an upgrade attempt occurs (scripts/core.lua):

1. A random roll (0-100) is compared against the configured percentage chance
2. If successful, the machine is replaced with the same type at the new quality level
3. Module quality changes depend on the `change-modules-with-entity` setting (see Module Upgrading section)
4. Failed attempts don't reset progress - the machine continues accumulating hours

This maintains Factorio's "gacha" spirit while providing predictable progression over time.

### Chance Accumulation

Optional system to ensure fairness over time (scripts/core.lua):

After each failed quality upgrade attempt, the chance increases by:
```
New Chance = Current Chance + (Base Chance × Accumulation Rate)
```

Accumulation rates:
- **None (0%)**: Pure randomness, no accumulation
- **Low (20%)**: Adds 20% of base chance per failure
- **Medium (50%)**: Adds 50% of base chance per failure
- **High (100%)**: Doubles the base chance per failure

Example with 10% base chance and Medium accumulation:
- Attempt 1: 10% chance
- Attempt 2: 15% chance (10% + 5%)
- Attempt 3: 20% chance (15% + 5%)

### Cost Scaling

Higher quality levels require more manufacturing hours (scripts/core.lua):

```
Required Hours = Base Hours × (1 + Cost Scaling Factor)^Quality Level
```

With a 0.5 cost scaling factor and 1 base hours:
- Normal → Uncommon: 10 hours
- Uncommon → Rare: 15 hours (10 × 1.5)
- Rare → Epic: 22.5 hours (10 × 1.5²)
- Epic → Legendary: 33.75 hours (10 × 1.5³)

This creates a natural progression curve where reaching legendary quality requires significant investment.

### Module Upgrading (Optional)

By default, only the entity itself upgrades - modules inside remain at their original quality level. However, there's an optional setting to automatically upgrade modules when their host entity's quality upgrades (scripts/core.lua).

The `change-modules-with-entity` setting has three options:

**Disabled** (Default):
- Modules keep their original quality when entities change

**Enabled**:
- Modules below the new entity quality move up one tier when entities upgrade
- Modules at or equal to the target entity quality remain unchanged

**Extra Enabled**:
- Modules are upgraded to match their host when their host's quality upgrades
- Ensures modules stay at the same quality as their host machine after upgrades


### In-Game Notifications

Two notification systems keep you informed:

**Entity-Specific Alerts**:
- Map pings at the machine's location when quality upgrades
- Shows entity icon with new quality level
- Customizable per-player setting

**Aggregate Console Messages**:
- Summarizes all quality upgrades with a 5-minute cooldown to prevent spam
- Accumulates upgrades across multiple processing cycles until cooldown expires
- Example: "3 assembling-machines upgraded, 2 inserters upgraded"
- Prevents console flooding while maintaining useful feedback

Both can be independently enabled/disabled in runtime settings.

### Inspection Tools

**Hotkey Inspection** (Ctrl+Shift+Q) (scripts/core.lua):
Select any tracked entity and press the hotkey to see:
- Current quality level and entity name
- Total quality change attempts
- Current success chance (including accumulation bonus)
- Manufacturing hours accumulated vs. required
- Progress percentage to next attempt

**Console Command** (control.lua):
```
/quality-control-init
```
Rebuilds the entire tracking cache from scratch. Useful if:
- Entities aren't being tracked properly after mod updates
- You've made significant factory changes while the mod was disabled
- Debugging tracking issues

The mod also automatically reinitializes if it detects corruption in the tracking data.

## Mod Settings

All settings are configurable at game startup:

- **Manufacturing Hours for Change**: Base hours required before a quality change (0.001 - 1000 hours)
- **Percentage Chance**: Likelihood of quality change when hours are met (0.0001% - 100%)
- **Cost Increases per Quality Level**: Compounds the hour requirement at higher quality levels
- **Chance Accumulation Rate**: How much the chance increases after failed attempts (None/Low/Medium/High)
- **Check Frequency**: How often to scan machines (1 - 3600 seconds)
- **Alert Settings**: Toggle console messages and/or map pings for quality changes

## Performance

A late game base doing 1,000 spm can have ~100,000 units. At the default rate of 10 units per tick, it would take about 3 minutes to check everything. If a unit has passed several thresholds between checks it's fine; no progress will be lost. All the attempted upgrades it has earned will be applied at once. So a fast machine can be upgraded multiple times in a single pass.

Some test results on an m2 mac:

- A base with 2,000spm (vanilla, not yet at promethium science) with 130,000 units was totally fine, UPS stayed steady at 60 UPS

- A base with 30,000spm (modded) was also fine: UPS stayed at about 60 (it was already fluctuating a bit before the mod, and adding it seemed about the same)

- Average milliseconds used over 100 ticks on my largest base fluctuated between 0.3ms to 0.7ms. Over those 100 ticks there was a max value of ~3ms, but I didn't notice lag spikes, and the average didn't change. I'm not sure where that small spike came from. For reference, 1 tick in the game is 16.67ms, and all game and mods share that; so the less used the better.

- Bumping up to 100 units per 1 tick had no noticeable impact.

- Bumping up to 1000 units introduced some noticeable lag, and higher values did even more so. Spreading out the units processed into large groups created lag spikes, which causes the game to stutter. So I wouldn't recommend something like 100k every 60 ticks. It's better to do fewer units more frequently.


## Technical Details: Secondary-Entity Upgrade Algorithm

This may be interesting to only a few, but here is how the upgrade system works.

The mod tracks two types of entities: primary entities (assemblers, furnaces, rocket silos) that have a way to measure their manufacturing time, and secondary entities (like inserters, power poles, etc.) that don't have a way to track work. The goal is to keep secondary entities upgrading at about the same rate, so that if all assemblers work their way up to legendary then other entities will also achieve legendary at about the same time.

When a primary entity reaches an upgrade threshold, it generates credits based on its current quality level: a normal quality entity would generate 1 credit and a legendary entity would generate 5 credits for example. These credits accumulate in a global pool that secondary entities pull from in a round-robin process.

Example for a base with 100 secondary entities:
- Assemblers and furnaces earn credits and add to the global pool, let's say there are 150 credits in the pool
- Each secondary entity gets 150 credits / 100 secondary entities = 1.50 credits
- The secondary entity get's 1.5 chances to upgrade it's quality

This credit system ensures secondary entities upgrade at a rate proportional to the activity and quality of primary entities, with higher quality primaries accelerating infrastructure upgrades.


## Developer Workflow

### Prerequisites

- Factorio installed on your system
- `jq` command-line tool (for parsing JSON)
- `rsync` (usually pre-installed on macOS/Linux)
- Basic shell environment (bash/zsh)

### Building and Testing

The mod includes a convenient packaging script that handles the entire build and deployment process:

```bash
./package.sh
```

This script will:
1. Read the mod name and version from `info.json`
2. Create a properly formatted zip file (`quality-control_<version>.zip`)
3. Exclude development files (.git, .DS_Store, AGENTS.md, CLAUDE.md, etc.)
4. Attempt to find your Factorio mods folder based on your OS
5. Copy the packaged mod to your mods folder (if found)

### Manual Installation

If the script can't auto-detect your mods folder, it will leave the zipped file in this mods directory. These are the folders it checks for:
- **macOS**: `~/Library/Application Support/factorio/mods/`
- **Linux**: `~/.factorio/mods/` or `~/.local/share/factorio/mods/`
- **Windows**: `%APPDATA%\Factorio\mods\`

Copy the generated zip file to the factorio mods folder to test any changes.

### Development Tips

0. Run `./validate.sh` to ensure there are no Lua issues
1. After making changes, run `./package.sh` to build and deploy
2. Restart Factorio to load the updated mod
3. Use Ctrl+Shift+Q in-game to inspect entity quality metrics

### Project Structure

```
quality-control/
├── control.lua          # Main entry point, event handlers, and configuration
├── data.lua             # Data stage definitions and prototypes
├── settings.lua         # Mod settings definitions
├── info.json            # Mod metadata and dependencies
├── scripts/             # Core mod logic (modular architecture)
│   ├── core.lua             # Entity tracking, quality upgrade management, and batch processing
│   ├── notifications.lua    # Notification and UI systems
│   ├── quality_selector.lua # Quality level selection logic
│   └── exclusions.lua       # Entity and surface exclusion rules
├── locale/
│   └── en/
│       └── locale.cfg  # English localization strings
├── migrations/          # Database migration scripts for version updates
├── changelog.txt       # Version history
├── package.sh          # Build and deployment script
└── README.md           # This file
```


