# Quality Control - Factorio Mod

A Factorio mod that automatically changes machine quality based on how hard they are working. You choose whether they should upgrade, downgrade, or a mix of both.

Quality Control tracks manufacturing hours by accounting for recipe duration, ensuring fair quality progression regardless of recipe speed. This approach means that two assemblers: one producing fast recipes (gears), and one producing slow recipes (science), will experience quality changes at a similar rate as long as they are working full time.

Upgraded assemblers with modules and beacons will progress and experience changes faster.

## Key Features

- **Manufacturing Hours Tracking**: Machines accumulate hours based on actual production time (items crafted x recipe duration)
- **Configurable Quality Direction**: Choose whether machines improve or degrade with use
- **Maintains Gacha Spirit**: Quality changes are based on small random chance; staying spiritually adjacent to factorio's quality system
- **Highly Configurable**: Adjust many parameters on how the mod will impact gameplay
- **Optional Chance Accumulation System**: Failed quality change attempts increase the likelihood of future changes
- **Comprehensive Entity Support**: Works with most placeable entities
- **Optional Alerts**: Console messages and/or map pings when quality changes occur
- **Entity Inspection**: Hotkey (default: Ctrl+Shift+Q) to inspect any tracked entity's quality metrics

## How It Works

1. Machines accumulate "manufacturing hours" as they produce items
2. Once the configured threshold is reached, a quality change attempt occurs
3. The change succeeds based on the configured percentage chance
4. Failed attempts can accumulate, increasing future success chances
5. Higher quality levels can require more hours to change (configurable cost scaling)

## Mod Settings

All settings are configurable at game startup:

- **Quality Change Direction**: Increase or decrease quality over time
- **Manufacturing Hours for Change**: Base hours required before a quality change (0.001 - 1000 hours)
- **Percentage Chance**: Likelihood of quality change when hours are met (0.0001% - 100%)
- **Quality Increase Cost**: Compounds the hour requirement at higher quality levels
- **Chance Accumulation Rate**: How much the chance increases after failed attempts (None/Low/Medium/High)
- **Check Frequency**: How often to scan machines (1 - 3600 seconds)
- **Alert Settings**: Toggle console messages and/or map pings for quality changes

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
4. Automatically detect your Factorio mods folder based on your OS
5. Copy the packaged mod to your mods folder (if found)

### Manual Installation

If the script can't auto-detect your mods folder, it will provide the correct path for your OS:
- **macOS**: `~/Library/Application Support/factorio/mods/`
- **Linux**: `~/.factorio/mods/` or `~/.local/share/factorio/mods/`
- **Windows**: `%APPDATA%\Factorio\mods\`

Simply copy the generated zip file to the appropriate folder.

### Development Tips

1. After making changes, run `./package.sh` to build and deploy
2. Restart Factorio or reload mods to test your changes
3. Use the in-game console (`~` key) to check for errors
4. Enable debug mode in `control.lua` (set `debug = true`) for detailed logging
5. Use Ctrl+Shift+Q in-game to inspect entity quality metrics

### Project Structure

```
quality-control/
├── control.lua          # Main mod logic and event handlers
├── settings.lua         # Mod settings definitions
├── info.json           # Mod metadata and dependencies
├── locale/
│   └── en/
│       └── locale.cfg  # English localization strings
├── changelog.txt       # Version history
├── package.sh          # Build and deployment script
└── README.md          # This file
```


