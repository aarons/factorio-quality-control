## Project Overview

This is a Factorio mod called "Quality Control" that upgrades machine quality over time based on manufacturing hours.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

## Repository Structure

- `info.json` - metadata including name, version, dependencies, and version requirements
- `settings.lua` - configurable options available to the end user
- `data.lua` - custom input prototypes (keyboard shortcuts bound to mod functions)
- `control.lua` - main entry point, event handlers, initialization, and configuration setup
- `scripts/core.lua` - consolidated entity tracking, quality upgrade management, and batch processing
- `scripts/notifications.lua` - manages notifications and alerts
- `validate.sh` - runs all validations and tests
- `update_locales.py` - updates non-English locale files via an LLM (see `--help` and `locale-config.example.json` for options)
- `package.sh` - packages the mod for distribution
- `migrations/` - database migration scripts for version updates
- `tests/test_*.py` - various pytests

Always use `./validate.sh` for testing and validation. This is the single command that runs all required checks including luacheck and pytest validations. Do not run `luacheck` or `pytest`.
`
### Localizations

Only update the English localization at `locale/en/locale.cfg` unless specifically asked. Generally we have others manage the non-english localizations. When adding new locale keys (e.g. for a new setting), locale test failures for non-English files are expected and can be ignored — translations are handled by another developer.

## Core Functionality

The mod assigns upgrade attempts based on manufacturing hours - a normalized measure of work completed.

When entities reach manufacturing hour thresholds, they attempt quality upgrades:
- Random roll compared against configured percentage chance (default 1%)
- Failed attempts don't reset progress - entities continue accumulating hours

This mod makes a distinction between primary entities (those whose hours of work can be tracked) and secondary entities (those that have no way to track work done). Primary entities generate credits that all other entities utilize for upgrade attempts.
