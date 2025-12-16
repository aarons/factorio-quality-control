## Project Overview

This is a Factorio mod called "Quality Control" that upgrades machine quality over time based on manufacturing hours.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

## Repository Structure

### Configuration & Metadata
- `info.json` - metadata including name, version, dependencies, and version requirements
- `settings.lua` - configurable options available to the end user
- `data.lua` - custom input prototypes (keyboard shortcuts bound to mod functions)
- `locale/en/locale.cfg` - localization strings

### Main Entry Point
- `control.lua` - main entry point, event handlers, initialization, and configuration setup

### Core Modules
- `scripts/core.lua` - consolidated entity tracking, quality upgrade management, and batch processing
- `scripts/notifications.lua` - manages notifications and alerts

### Development & Testing
- `validate.sh` - runs all validations and tests
- `package.sh` - packages the mod for distribution
- `migrations/` - database migration scripts for version updates
- `tests/test_*.py` - various pytests

## Core Functionality

The mod assigns upgrade attempts based on manufacturing hours - a normalized measure of work completed.

When entities reach manufacturing hour thresholds, they attempt quality upgrades:
- Random roll compared against configured percentage chance (default 1%)
- Failed attempts don't reset progress - entities continue accumulating hours

This mod makes a distinction between primary entities (those whose hours of work can be tracked) and secondary entities (those that have no way to track work done). Primary entities generate credits that all other entities utilize for upgrade attempts.

## Development Testing

**IMPORTANT**: Always use `./validate.sh` for testing and validation. This is the single command that runs all required checks including luacheck and pytest validations. Do NOT run `luacheck` or `pytest` directly use `validate.sh`
