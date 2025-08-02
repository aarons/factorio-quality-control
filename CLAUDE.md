# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Factorio mod called "Quality Control" that automatically changes machine quality over time based on manufacturing hours. The mod tracks how long machines have been producing items and applies quality upgrades or downgrades based on configurable settings.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

Correct use of factorio's API is vital; it's very important to validate assumptions about the API because it changes over time.

The API documentation is available via context7 with this library ID: "context7/lua-api_factorio-stable"

## Architecture

### Core Files
- `control.lua` - Main mod logic handling quality changes, machine tracking, and event handlers
- `settings.lua` - Mod settings definitions for quality direction, timing, and notifications
- `info.json` - Mod metadata including name, version, dependencies, and Factorio version requirements
- `locale/en/locale.cfg` - Localization strings for settings and alert messages

### Key Systems

**Quality Management System** (`control.lua:39-86`):
- Builds quality prototype cache on mod initialization
- Handles quality chain navigation (increase/decrease directions)
- Supports base quality levels (normal to legendary) as well as modded qualities (beyond legendary)

Notes:
- factorio does not have built in quality.next or quality.previous functions, so we have to create these functions
- other mods can add arbitrary quality levels, so we have to dynamically build the chain on initilization
- we ensure this mod runs after mods that add more qualities by specifying those mods as optional requirements in `info.json`

**Machine Tracking System** (`control.lua:299-397`):
- Tracks manufacturing hours per machine using `products_finished` and recipe energy
- Uses threshold-based checking to avoid redundant quality attempts
- Maintains persistent storage of machine data across game sessions

**Entity Coverage**:
- Primary: Assembling machines and furnaces (manufacturing hour based)
- Secondary: Mining drills, labs, inserters, pumps, radars, roboports (ratio based)

**Notification System** (`control.lua:222-297`):
- Player-configurable alerts and console messages
- Supports per-entity-type change reporting
- Alert icons use the upgraded entity as the icon

## Development Commands

### Packaging
```bash
./package.sh
```
Creates a properly named zip file for Factorio mod installation. The script:
- Reads version from `info.json`
- Creates `quality-control_<version>.zip`
- Excludes development files (.git, AGENTS.md, package.sh, etc.)

### Testing
Install the generated zip file to your local Factorio mods folder for testing.

## Configuration

### Startup Settings (require game restart)
- `quality-change-direction`: "increase" or "decrease"
- `manufacturing-hours-for-change`: Base hours required (0.001-1000)
- `percentage-chance-of-change`: Success rate percentage (0.0001-100)
- `quality-level-modifier`: Exponential scaling per quality level (0-1000)

### Runtime Settings
- `upgrade-check-frequency-seconds`: How often to scan machines (1-3600)
- `quality-change-alerts-enabled`: Show map alerts (per-player)
- `quality-change-console-messages-enabled`: Show console messages (per-player)

## Key Implementation Details

- Manufacturing hours calculated as: `(products_finished * recipe_energy) / 3600`
- Quality level scaling: `base_hours * (1 + modifier)^quality_level`
- Secondary entities use ratio-based selection matching primary machine candidate rate
- Machine data cleanup on entity destruction prevents memory leaks
- Fisher-Yates shuffle ensures fair random selection for ratio-based changes
