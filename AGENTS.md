## Project Overview

This is a Factorio mod called "Quality Control" that automatically upgrades machine quality over time based on manufacturing hours. The mod tracks how long machines have been producing items and applies quality upgrades based on configurable chance-based mechanics.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

Factorio's API documentation is available via context7 with this library ID: "context7/lua-api_factorio-stable"

## Core Files
- `control.lua` - Main mod entry point and event handlers
- `scripts/core.lua` - Core processing logic for quality control, entity tracking, and batch processing
- `scripts/data-setup.lua` - Data structure initialization, settings parsing, and entity type configuration
- `scripts/notifications.lua` - Notification system for alerts and UI display functionality
- `settings.lua` - Mod settings definitions for quality direction, timing, and notifications
- `data.lua` - Data stage definitions and prototypes
- `info.json` - Mod metadata including name, version, dependencies, and Factorio version requirements
- `locale/en/locale.cfg` - Localization strings for settings and alert messages

## Core Functionality

### Manufacturing Hours System
The mod tracks "manufacturing hours" for entities - a normalized measure of actual work completed. For production entities like assemblers and furnaces, this accounts for items produced multiplied by recipe duration, ensuring fair progression regardless of what's being crafted. Fast recipes and slow recipes progress equally when running continuously.

### Chance-Based Quality Upgrades
When entities reach manufacturing hour thresholds, they attempt quality upgrades:
- Random roll compared against configured percentage chance (default 1%)
- Failed attempts don't reset progress - entities continue accumulating hours
- Maintains Factorio's "gacha" spirit while providing predictable progression

### Accumulation Mechanics
Optional system to ensure fairness over time. After failed upgrade attempts, the success chance increases by a configurable rate (none/low/medium/high). This prevents extremely unlucky streaks while preserving randomness.

### Cost Scaling
Higher quality levels require exponentially more manufacturing hours, creating a natural progression curve where reaching legendary quality requires significant investment.

## Entity System Architecture

### Primary vs Secondary Entities
The mod distinguishes between two entity categories:

**Primary Entities** (assemblers, furnaces):
- Track exact manufacturing hours based on items produced and recipe duration
- Generate quality upgrade attempts based on accumulated work time
- Each entity independently tracks progress toward next attempt

**Secondary Entities** (inserters, power poles, etc.):
- Infrastructure entities that don't have measurable work output
- Use credit-based system for upgrades
- Include: mining drills, labs, inserters, pumps, radar, roboports, power infrastructure, defense, logic entities, Space Age entities

### Credit-Based System for Secondary Entities
When primary entities reach upgrade thresholds, they generate credits proportional to the ratio of secondary to primary entities. Secondary entities consume these credits for upgrade attempts in a round-robin process. This ensures infrastructure upgrades at a similar pace to production machines without requiring complex tracking for non-crafting entities.

## Entity Exclusion Logic

The mod includes comprehensive filtering to maintain compatibility:

### Automatic Exclusions
- Non-selectable entities (`entity.prototype.selectable_in_game == false`)
- Indestructible entities (`entity.destructible == false`)
- Entities from incompatible mods (Warp-Drive-Machine, quality-condenser, RealisticReactorsReborn, miniloader-redux, etc.)

### Exclusion Detection
Uses `prototypes.get_history()` to identify entity origins and filter out problematic modded entities that don't work well with Factorio's `fast_replace` mechanism.

### Colocated Entity Handling
Detects complex modded entities that place multiple overlapping entities and excludes the entire group to prevent conflicts.

## Performance Tuning

### Batch Processing Architecture
The mod was designed with batch processing to handle massive bases (100k+ entities) without UPS impact:
- Processes configurable number of entities per tick (default: 10)
- Spreads processing across multiple ticks to avoid lag spikes
- Tested on bases up to 30k SPM with stable 60 UPS

### Configurable Processing Rates
- `batch-entities-per-tick`: How many entities to process each cycle
- `batch-ticks-between-processing`: Ticks between processing cycles
- Default settings handle ~100k entities with ~3 minute full scan time

### Performance Rationale
Large batches (1000+ entities/tick) cause noticeable stuttering. Frequent small batches provide smooth gameplay while ensuring no progress is lost - entities accumulating multiple thresholds between checks receive all earned upgrade attempts at once.

## Development Validation

The project includes comprehensive validation tools:
- `./validate.sh` - Run all validations (luacheck, info.json, locale files, changelog)
- `./validate.sh --changelog` - Run changelog validation only

## Development Workflow

### Building and Deployment
- `./package.sh` - Creates properly formatted zip file and deploys to Factorio mods folder
- Excludes development files (.git, AGENTS.md, CLAUDE.md, etc.)
- Auto-detects mods folder based on OS (macOS/Linux/Windows)

### Testing
- Use `./validate.sh` before committing changes
- Enable debug mode in `scripts/core.lua` for detailed logging
- Use Ctrl+Shift+Q in-game to inspect entity quality metrics
- Console command `/quality-control-init` rebuilds tracking cache

For additional details on features, compatibility, and technical implementation, see README.md.
