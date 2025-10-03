#!/bin/bash
set -euo pipefail

# Update locale translations using Claude Code
# This script prompts Claude Code to update locale translations for each language
# Usage: ./update-locales.sh [language_code]
#        ./update-locales.sh --start-at [language_code]
# Examples: ./update-locales.sh de (to update only German)
#           ./update-locales.sh --start-at ko (to start from Korean and continue)

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Reference file
REFERENCE_FILE="quality-control/locale/en/locale.cfg"

# Check if reference file exists
if [ ! -f "$REFERENCE_FILE" ]; then
    echo "Error: Reference file $REFERENCE_FILE not found!"
    exit 1
fi

# Language mapping: code:name pairs
LANGUAGES=(
    "be:Belarusian"
    "ca:Catalan"
    "cs:Czech"
    "de:German"
    "el:Greek"
    "es-419:Spanish (Latin America)"
    "es-ES:Spanish (Spain)"
    "fi:Finnish"
    "fr:French"
    "hu:Hungarian"
    "it:Italian"
    "ja:Japanese"
    "ka:Georgian"
    "kk:Kazakh"
    "ko:Korean"
    "lv:Latvian"
    "nl:Dutch"
    "no:Norwegian"
    "pl:Polish"
    "pt-BR:Portuguese (Brazil)"
    "pt-PT:Portuguese (Portugal)"
    "ro:Romanian"
    "ru:Russian"
    "sv:Swedish"
    "th:Thai"
    "tr:Turkish"
    "uk:Ukrainian"
    "vi:Vietnamese"
    "zh-CN:Chinese (Simplified)"
    "zh-TW:Chinese (Traditional)"
)

# Function to validate a single locale file using pytest
validate_locale() {
    local lang_code="$1"
    local lang_name="$2"
    local locale_file="$3"
    local attempt="$4"

    echo -e "${BLUE}Validating $lang_name translation...${NC}"

    # Run pytest on the specific locale file only
    cd "$(dirname "$0")"
    if [ -d "tests/venv" ]; then
        source tests/venv/bin/activate
        validation_output=$(python -m pytest tests/test_locale.py -v -k "$lang_code/locale.cfg" 2>&1 || true)
        deactivate
    else
        validation_output=$(python -m pytest tests/test_locale.py -v -k "$lang_code/locale.cfg" 2>&1 || true)
    fi

    # Check if validation passed
    if echo "$validation_output" | grep -q "0 selected"; then
        echo -e "${RED}No tests found for $lang_name locale file. Check test configuration.${NC}"
        return 1
    elif echo "$validation_output" | grep -q "FAILED\|ERROR"; then
        echo -e "${YELLOW}Validation failed for $lang_name. Attempting to fix (attempt $attempt/2)...${NC}"

        # Extract relevant error messages
        error_msg=$(echo "$validation_output" | grep -A 10 -B 5 "$lang_code/locale.cfg\|$locale_file")

        # Create prompt to fix the validation errors
        fix_prompt="We recently modified this $lang_name translation in $locale_file - and it now has the following validation error:

$error_msg

Please fix the error problem in $locale_file.

Additional Context:
This is a locale file for a factorio mod called Quality Control. AGENTS.md and mod-description.md have more context if helpful, and source code is located mostly in .lua files.

The English translation file is at quality-control/locale/en/locale.cfg and is the source reference. Focus on fixing the failure for the $lang_name translation in $locale_file."

        echo -e "${BLUE}Prompting Claude Code to fix validation errors...${NC}"
        claude --allowedTools "Bash(git log:*) Bash(git show:*) Glob Grep Read Edit($locale_file) Write($locale_file) MultiEdit($locale_file)" -p "$fix_prompt"

        return 1  # Indicate validation failed
    else
        echo -e "${GREEN}✓ Validation passed for $lang_name${NC}"
        return 0  # Validation passed
    fi
}

# Parse command line arguments
SINGLE_LANGUAGE=""
START_AT_LANGUAGE=""

if [ $# -eq 1 ]; then
    if [[ "$1" == --start-at* ]]; then
        START_AT_LANGUAGE="${1#--start-at=}"
        if [ -z "$START_AT_LANGUAGE" ]; then
            echo -e "${RED}Error: --start-at flag requires a language code (e.g., --start-at=ko)${NC}"
            exit 1
        fi
    else
        SINGLE_LANGUAGE="$1"
    fi
elif [ $# -eq 2 ] && [ "$1" = "--start-at" ]; then
    START_AT_LANGUAGE="$2"

fi

# Validate language codes if provided
for target_lang in "$SINGLE_LANGUAGE" "$START_AT_LANGUAGE"; do
    if [ -n "$target_lang" ]; then
        found_language=false
        for lang_pair in "${LANGUAGES[@]}"; do
            lang_code="${lang_pair%%:*}"
            if [ "$lang_code" = "$target_lang" ]; then
                found_language=true
                break
            fi
        done

        if [ "$found_language" = false ]; then
            echo -e "${RED}Error: Language code '$target_lang' not found.${NC}"
            echo -e "Available language codes:"
            for lang_pair in "${LANGUAGES[@]}"; do
                lang_code="${lang_pair%%:*}"
                lang_name="${lang_pair#*:}"
                echo "  $lang_code ($lang_name)"
            done
            exit 1
        fi
    fi
done

if [ -n "$SINGLE_LANGUAGE" ]; then
    echo -e "${BLUE}Single language mode: Processing only $SINGLE_LANGUAGE${NC}"
elif [ -n "$START_AT_LANGUAGE" ]; then
    echo -e "${BLUE}Starting from language: $START_AT_LANGUAGE${NC}"
fi

echo -e "${BLUE}Quality Control Locale Update Script${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo -e "This script will prompt Claude Code to update locale translations."
echo -e "Reference file: ${GREEN}$REFERENCE_FILE${NC}"
if [ -n "$SINGLE_LANGUAGE" ]; then
    echo -e "Target language: ${GREEN}$SINGLE_LANGUAGE${NC}"
elif [ -n "$START_AT_LANGUAGE" ]; then
    echo -e "Starting from: ${GREEN}$START_AT_LANGUAGE${NC}"
fi
echo ""

# Iterate through each language
start_processing=false
if [ -z "$START_AT_LANGUAGE" ]; then
    start_processing=true
fi

for lang_pair in "${LANGUAGES[@]}"; do
    lang_code="${lang_pair%%:*}"
    lang_name="${lang_pair#*:}"
    locale_dir="quality-control/locale/$lang_code"
    locale_file="$locale_dir/locale.cfg"

    # Skip if single language mode and this isn't the target language
    if [ -n "$SINGLE_LANGUAGE" ] && [ "$lang_code" != "$SINGLE_LANGUAGE" ]; then
        continue
    fi

    # Handle start-at logic
    if [ -n "$START_AT_LANGUAGE" ]; then
        if [ "$lang_code" = "$START_AT_LANGUAGE" ]; then
            start_processing=true
        fi
        if [ "$start_processing" = false ]; then
            continue
        fi
    fi

    echo -e "${YELLOW}Processing language: $lang_name ($lang_code)${NC}"

    # Create locale directory if it doesn't exist
    if [ ! -d "$locale_dir" ]; then
        echo "Creating directory: $locale_dir"
        mkdir -p "$locale_dir"
    fi

    # Check if locale file exists to determine prompt intro
    if [ -f "$locale_file" ]; then
        intro="We made some recent changes to quality-control/locale/en/locale.cfg. Please evaluate the $lang_name translation in $locale_file and apply updates if needed. Use quality-control/locale/en/locale.cfg as the reference."
    else
        intro="We're introducing $lang_name language support for my factorio mod. We need to add a translation file to $locale_file. Please use quality-control/locale/en/locale.cfg as the reference."
    fi

    # Header
    header="The $lang_name translation in $locale_file should have a comment at the top, roughly: 'This translation was generated by an AI. Corrections are very welcome! Please add feedback to the mod discussion forum (https://mods.factorio.com/mod/quality-control/discussion) or as an issue on the github repo (https://github.com/aarons/factorio-quality-control/issues). Please forgive me for the mistakes!' - The comment should be in $lang_name obviously :)"

    # Common translation guidelines
    guidelines="Important notes:
  - Always keep the section headers [mod-name], [mod-setting-name], etc. in English
  - Only translate the values after the = sign
  - Keep technical terms consistent (always translate 'belt' the same way)
  - Preserve formatting codes and placeholders (__1__, __ITEM__, etc.)
  - For context on the mod's functionality, refer to AGENTS.md and mod-description.md"

    prompt="$intro

$header

$guidelines"

    echo -e "${BLUE}Prompting Claude Code for $lang_name translation...${NC}"
    echo ""

    # Execute claude command with proper allowed tools
    claude --allowedTools "Bash(git log:*) Bash(git show:*) Glob Grep Read Edit($locale_file) Write($locale_file) MultiEdit($locale_file)" -p "$prompt"

    echo ""

    # Validation step with retry logic
    attempt=1
    max_attempts=3
    validation_passed=false

    while [ $attempt -le $max_attempts ]; do
        if validate_locale "$lang_code" "$lang_name" "$locale_file" "$attempt"; then
            validation_passed=true
            break
        fi

        # If validation failed and we have attempts left, try again
        if [ $attempt -lt $max_attempts ]; then
            echo -e "${YELLOW}Retrying validation for $lang_name (attempt $((attempt + 1))/$max_attempts)...${NC}"
            attempt=$((attempt + 1))

            # Run validation again after Claude's fix attempt
            continue
        else
            echo -e "${RED}⚠ Validation failed for $lang_name after $max_attempts attempts${NC}"
            break
        fi
    done

    if [ "$validation_passed" = true ]; then
        echo -e "${GREEN}✓ Completed processing for $lang_name [$lang_code] with validation${NC}"
    else
        echo -e "${YELLOW}⚠ Completed processing for $lang_name [$lang_code] but validation issues remain${NC}"
    fi
    echo "----------------------------------------"
    echo ""
done

echo -e "${GREEN}All locale updates completed!${NC}"
echo ""
echo "Verify the translations and make any necessary adjustments."