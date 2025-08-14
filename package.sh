#!/bin/bash

# This script packages the Factorio mod for release.
# It reads the mod name and version from info.json, creates a zip file
# named quality-control_<version>.zip, and excludes the .git directory.
# It also attempts to copy the package to the system's Factorio mods folder.

set -e

# Print timestamp
echo "========================================="
echo "Factorio Mod Packaging Script"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================="

# Run validation before packaging
echo ""
echo "Running pre-packaging validation..."
if ! ./validate.sh --changelog; then
    echo ""
    echo "❌ Validation failed! Fix the errors above before packaging."
    exit 1
fi
echo ""

# Read mod name and version from info.json
MOD_NAME=$(jq -r .name info.json)
MOD_VERSION=$(jq -r .version info.json)

if [ -z "$MOD_NAME" ] || [ -z "$MOD_VERSION" ]; then
  echo "Error: Could not read mod name or version from info.json."
  echo "Please ensure info.json is present and contains 'name' and 'version' fields."
  exit 1
fi

# Create a temporary directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TMP_DIR"' EXIT

# The name of the directory inside the zip file
PACKAGE_DIR="$MOD_NAME"_"$MOD_VERSION"
FULL_PACKAGE_DIR="$TMP_DIR/$PACKAGE_DIR"
mkdir -p "$FULL_PACKAGE_DIR"

# Copy all files to the temporary directory, excluding .git
rsync -av --exclude='.git' --exclude='assets*' --exclude='plan*.md' --exclude='mod-description.md' --exclude='.DS_Store' --exclude='AGENTS.md' --exclude='CLAUDE.md' --exclude='.gitignore' --exclude='package.sh' --exclude='*.zip' --exclude='.claude*' --exclude='tests*' --exclude='validate*' ./ "$FULL_PACKAGE_DIR/"

# Create archive folder if it doesn't exist
mkdir -p archive

# Move any existing version zip files to archive folder
if ls quality-control_*.zip 1> /dev/null 2>&1; then
    echo "Moving existing version files to archive folder..."
    mv quality-control_*.zip archive/
fi

# Create the zip file
(
  cd "$TMP_DIR"
  zip -r "$PACKAGE_DIR".zip "$PACKAGE_DIR"
)

# Move the zip file to the current directory
mv "$TMP_DIR/$PACKAGE_DIR.zip" ./

echo "Successfully created package: $PACKAGE_DIR.zip"

# Detect Factorio mods folder and copy package
detect_and_copy_to_mods_folder() {
    local package_file="$PACKAGE_DIR.zip"
    local mods_folder=""

    # Detect operating system and set appropriate mods folder path
    case "$(uname -s)" in
        Darwin*)
            # macOS
            mods_folder="$HOME/Library/Application Support/factorio/mods"
            ;;
        Linux*)
            # Linux
            if [ -d "$HOME/.factorio/mods" ]; then
                mods_folder="$HOME/.factorio/mods"
            elif [ -d "$HOME/.local/share/factorio/mods" ]; then
                mods_folder="$HOME/.local/share/factorio/mods"
            fi
            ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*)
            # Windows (Git Bash, MSYS2, etc.)
            if [ -d "$APPDATA/Factorio/mods" ]; then
                mods_folder="$APPDATA/Factorio/mods"
            elif [ -d "$HOME/AppData/Roaming/Factorio/mods" ]; then
                mods_folder="$HOME/AppData/Roaming/Factorio/mods"
            fi
            ;;
    esac

    if [ -n "$mods_folder" ] && [ -d "$mods_folder" ]; then
        echo ""
        echo "Found Factorio mods folder: $mods_folder"
        if cp "$package_file" "$mods_folder/"; then
            echo "✓ Successfully copied $package_file to Factorio mods folder"
            echo "  The mod is now ready for testing in Factorio!"
        else
            echo "✗ Failed to copy to mods folder (check permissions)"
            echo "  You can manually copy $package_file to: $mods_folder"
        fi
    else
        echo ""
        echo "ℹ️  Factorio mods folder not found automatically"
        echo "   Please manually copy $package_file to your Factorio mods folder:"
        case "$(uname -s)" in
            Darwin*)
                echo "   macOS: ~/Library/Application Support/factorio/mods/"
                ;;
            Linux*)
                echo "   Linux: ~/.factorio/mods/ or ~/.local/share/factorio/mods/"
                ;;
            CYGWIN*|MINGW32*|MSYS*|MINGW*)
                echo "   Windows: %APPDATA%\\Factorio\\mods\\"
                ;;
        esac
    fi
}

# Call the detection and copy function
detect_and_copy_to_mods_folder

echo ""
echo "Mod installed at: $(date '+%Y-%m-%d %H:%M:%S %Z')"

# Check for debug mode in core.lua and show warning at the end
if grep -q "debug_enabled = true" scripts/core.lua; then
    echo ""
    echo "========================================="
    echo "⚠️  WARNING: DEBUG MODE IS ENABLED!"
    echo "========================================="
    echo ""
    echo "Found 'debug_enabled = true' in scripts/core.lua"
    echo "This will cause excessive logging in production."
    echo ""
    echo "Please set 'debug_enabled = false' before packaging"
    echo "for release to users."
    echo ""
    echo "========================================="
fi
