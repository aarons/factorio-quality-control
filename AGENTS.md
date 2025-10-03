## Project Overview

This is a Factorio mod called "Quality Control" that upgrades machine quality over time based on manufacturing hours.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

Factorio's API and best practices are available via answer-agent.

## Repository Structure

All mod files are located in the `quality-control/` subdirectory.

### Configuration & Metadata
- `quality-control/info.json` - metadata including name, version, dependencies, and version requirements
- `quality-control/settings.lua` - configurable options available to the end user
- `quality-control/data.lua` - custom input prototypes (keyboard shortcuts bound to mod functions)
- `quality-control/locale/en/locale.cfg` - localization strings

### Main Entry Point
- `quality-control/control.lua` - main entry point, event handlers, initialization, and configuration setup

### Core Modules
- `quality-control/scripts/core.lua` - consolidated entity tracking, quality upgrade management, and batch processing
- `quality-control/scripts/notifications.lua` - manages notifications and alerts

### Development & Testing
- `validate.sh` - runs all validations and tests
- `package.sh` - packages the mod for distribution
- `quality-control/migrations/` - database migration scripts for version updates
- `tests/test_*.py` - various pytests

## Core Functionality

The mod assigns upgrade attempts based on manufacturing hours - a normalized measure of actual work completed.

When entities reach manufacturing hour thresholds, they attempt quality upgrades:
- Random roll compared against configured percentage chance (default 1%)
- Failed attempts don't reset progress - entities continue accumulating hours
- Maintains Factorio's random quality upgrade spirit

The mod distinguishes between two entity categories:

Primary Entities (assemblers, furnaces) which have a way to track exact manufacturing hours, and secondary entities which have no way to measure work (power poles, inserters, etc.)

Primary entities generate upgrade credits that are used by themselves and secondary entities. Secondary entities consume these in a round-robin process. This ensures infrastructure upgrades at a similar pace to production machines without requiring complex tracking for non-crafting entities.

## Mod Exclusion Logic

The mod filters out entities that are incompatible with upgrades:
- Non-selectable entities
- Indestructible entities
- Entities from certain mods

## Development Testing

**IMPORTANT**: Always use `./validate.sh` for testing and validation. This is the single command that runs all required checks including luacheck and pytest validations. Do NOT run `luacheck` or `pytest` directly use `validate.sh`
