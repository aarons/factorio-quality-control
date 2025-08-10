## Project Overview

This is a Factorio mod called "Quality Control" that automatically changes machine quality over time based on manufacturing hours. The mod tracks how long machines have been producing items and applies quality upgrades or downgrades based on configurable settings.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

Factorio's API documentation is available via context7 with this library ID: "context7/lua-api_factorio-stable"

### Core Files
- `control.lua` - Main mod logic handling quality changes, machine tracking, and event handlers
- `settings.lua` - Mod settings definitions for quality direction, timing, and notifications
- `info.json` - Mod metadata including name, version, dependencies, and Factorio version requirements
- `locale/en/locale.cfg` - Localization strings for settings and alert messages
