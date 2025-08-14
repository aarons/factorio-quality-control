## Project Overview

This is a Factorio mod called "Quality Control" that automatically changes machine quality over time based on manufacturing hours. The mod tracks how long machines have been producing items and applies quality upgrades or downgrades based on configurable settings.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

Factorio's API documentation is available via context7 with this library ID: "context7/lua-api_factorio-stable"

### Core Files
- `control.lua` - Main mod entry point and event handlers
- `scripts/core.lua` - Core processing logic for quality control, entity tracking, and batch processing
- `scripts/data-setup.lua` - Data structure initialization, settings parsing, and entity type configuration
- `scripts/notifications.lua` - Notification system for alerts and UI display functionality
- `settings.lua` - Mod settings definitions for quality direction, timing, and notifications
- `data.lua` - Data stage definitions and prototypes
- `info.json` - Mod metadata including name, version, dependencies, and Factorio version requirements
- `locale/en/locale.cfg` - Localization strings for settings and alert messages

## Development Validation

The project includes comprehensive validation tools for local development:
- `./validate.sh` - Run all validations (default)
- `./validate.sh --changelog` - Run changelog validation only

### Validation Checks
- **Luacheck**: Lua code linting (if luacheck is installed via `luarocks install luacheck`)
- **info.json**: Validates JSON structure and required fields
- **Locale files**: Checks for proper locale.cfg structure
- **Changelog**: Validates changelog.txt format and test examples

### Automated Validation
Claude Code is configured with PostTool hooks (via `.claude_code_settings.json`) to automatically run `./validate.sh` after file modifications. This ensures code quality is maintained during development.
