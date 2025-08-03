#!/bin/bash

# This script packages the Factorio mod for release.
# It reads the mod name and version from info.json, creates a zip file
# named quality-control_<version>.zip, and excludes the .git directory.

set -e

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
rsync -av --exclude='.git' --exclude='AGENTS.md' --exclude='CLAUDE.md' --exclude='.gitignore' --exclude='package.sh' --exclude='*.zip' --exclude='.claude*' ./ "$FULL_PACKAGE_DIR/"

# Create the zip file
(
  cd "$TMP_DIR"
  zip -r "$PACKAGE_DIR".zip "$PACKAGE_DIR"
)

# Move the zip file to the current directory
mv "$TMP_DIR/$PACKAGE_DIR.zip" ./

echo "Successfully created package: $PACKAGE_DIR.zip"