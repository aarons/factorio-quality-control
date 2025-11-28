#!/bin/bash
set -euo pipefail

# Update locale translations using Claude Code
# This script prompts Claude Code to update locale translations for each language
# Usage: ./update-locales.sh [options] [language_code]
#
# Options:
#   --parallel N       Run N translations in parallel (default: 10)
#   --start-at CODE    Start from a specific language code and continue
#
# Examples:
#   ./update-locales.sh                    # Process all languages (10 parallel)
#   ./update-locales.sh de                 # Process only German
#   ./update-locales.sh --parallel 5       # Process all with 5 parallel jobs
#   ./update-locales.sh --start-at ko      # Start from Korean and continue

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default parallelism
MAX_PARALLEL=10

# Wrapper function to handle rate limiting with retry-after and exponential backoff
claude_with_retry() {
    local max_retries=5
    local attempt=1
    local output
    local exit_code

    while [ $attempt -le $max_retries ]; do
        # Run command, capture both stdout and stderr
        output=$("$@" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            echo "$output"
            return 0
        fi

        # Check if rate limited (429 or overloaded)
        if echo "$output" | grep -qi "429\|rate.limit\|overloaded"; then
            # Try to extract retry-after value from response
            local retry_after
            retry_after=$(echo "$output" | grep -oi 'retry-after[":= ]*[0-9]*' | grep -o '[0-9]*' | head -1)

            # Default to exponential backoff if no retry-after
            if [ -z "$retry_after" ]; then
                retry_after=$((2 ** attempt))
            fi

            # Add jitter (0-2 seconds) to avoid thundering herd
            local jitter=$((RANDOM % 3))
            local wait_time=$((retry_after + jitter))

            echo -e "${YELLOW}Rate limited, waiting ${wait_time}s (attempt $attempt/$max_retries)...${NC}" >&2
            sleep "$wait_time"
            attempt=$((attempt + 1))
        else
            # Non-rate-limit error, return immediately
            echo "$output"
            return $exit_code
        fi
    done

    echo "$output"
    return 1
}

# Reference file
REFERENCE_FILE="locale/en/locale.cfg"

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

The English translation file is at locale/en/locale.cfg and is the source reference. Focus on fixing the failure for the $lang_name translation in $locale_file."

        echo -e "${BLUE}Prompting Claude Code to fix validation errors...${NC}"
        claude_with_retry claude --allowedTools "Bash(git log:*) Bash(git show:*) Glob Grep Read Edit($locale_file) Write($locale_file) MultiEdit($locale_file)" -p "$fix_prompt"

        return 1  # Indicate validation failed
    else
        echo -e "${GREEN}✓ Validation passed for $lang_name${NC}"
        return 0  # Validation passed
    fi
}

# Parse command line arguments
SINGLE_LANGUAGE=""
START_AT_LANGUAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --parallel)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                MAX_PARALLEL="$2"
                shift 2
            else
                echo -e "${RED}Error: --parallel requires a number${NC}"
                exit 1
            fi
            ;;
        --parallel=*)
            MAX_PARALLEL="${1#--parallel=}"
            shift
            ;;
        --start-at)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                START_AT_LANGUAGE="$2"
                shift 2
            else
                echo -e "${RED}Error: --start-at requires a language code${NC}"
                exit 1
            fi
            ;;
        --start-at=*)
            START_AT_LANGUAGE="${1#--start-at=}"
            shift
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            exit 1
            ;;
        *)
            SINGLE_LANGUAGE="$1"
            shift
            ;;
    esac
done

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
echo -e "Parallel jobs: ${GREEN}$MAX_PARALLEL${NC}"
echo ""

# Create temp directory for results
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Process a single language (used by parallel execution)
process_language() {
    local lang_pair="$1"
    local lang_code="${lang_pair%%:*}"
    local lang_name="${lang_pair#*:}"
    local locale_dir="locale/$lang_code"
    local locale_file="$locale_dir/locale.cfg"
    local result_file="$TEMP_DIR/result_$lang_code"

    echo -e "${YELLOW}Processing language: $lang_name ($lang_code)${NC}"

    # Create locale directory if it doesn't exist
    if [ ! -d "$locale_dir" ]; then
        echo "Creating directory: $locale_dir"
        mkdir -p "$locale_dir"
    fi

    # Check if locale file exists to determine prompt intro
    local intro
    if [ -f "$locale_file" ]; then
        intro="We made some recent changes to locale/en/locale.cfg. Please evaluate the $lang_name translation in $locale_file and apply updates if needed. Use locale/en/locale.cfg as the reference."
    else
        intro="We're introducing $lang_name language support for my factorio mod. We need to add a translation file to $locale_file. Please use locale/en/locale.cfg as the reference."
    fi

    # Header
    local header="The $lang_name translation in $locale_file should have a comment at the top, roughly: 'This translation was generated by an AI. Corrections are very welcome! Please add feedback to the mod discussion forum (https://mods.factorio.com/mod/quality-control/discussion) or as an issue on the github repo (https://github.com/aarons/factorio-quality-control/issues). Please forgive me for the mistakes!' - The comment should be in $lang_name obviously :)"

    # Common translation guidelines
    local guidelines="Important notes:
  - Always keep the section headers [mod-name], [mod-setting-name], etc. in English
  - Only translate the values after the = sign
  - Keep technical terms consistent (always translate 'belt' the same way)
  - Preserve formatting codes and placeholders (__1__, __ITEM__, etc.)
  - For context on the mod's functionality, refer to AGENTS.md and mod-description.md"

    local prompt="$intro

$header

$guidelines"

    echo -e "${BLUE}Prompting Claude Code for $lang_name translation...${NC}"

    # Execute claude command with retry wrapper
    claude_with_retry claude --allowedTools "Bash(git log:*) Bash(git show:*) Glob Grep Read Edit($locale_file) Write($locale_file) MultiEdit($locale_file)" -p "$prompt"

    # Validation step with retry logic
    local attempt=1
    local max_attempts=3
    local validation_passed=false

    while [ $attempt -le $max_attempts ]; do
        if validate_locale "$lang_code" "$lang_name" "$locale_file" "$attempt"; then
            validation_passed=true
            break
        fi

        # If validation failed and we have attempts left, try again
        if [ $attempt -lt $max_attempts ]; then
            echo -e "${YELLOW}Retrying validation for $lang_name (attempt $((attempt + 1))/$max_attempts)...${NC}"
            attempt=$((attempt + 1))
            continue
        else
            echo -e "${RED}⚠ Validation failed for $lang_name after $max_attempts attempts${NC}"
            break
        fi
    done

    # Write result to temp file
    if [ "$validation_passed" = true ]; then
        echo -e "${GREEN}✓ Completed processing for $lang_name [$lang_code] with validation${NC}"
        echo "success:$lang_code:$lang_name" > "$result_file"
    else
        echo -e "${YELLOW}⚠ Completed processing for $lang_name [$lang_code] but validation issues remain${NC}"
        echo "failed:$lang_code:$lang_name" > "$result_file"
    fi
    echo "----------------------------------------"
}

# Build list of languages to process
LANGS_TO_PROCESS=()
start_processing=false
if [ -z "$START_AT_LANGUAGE" ]; then
    start_processing=true
fi

for lang_pair in "${LANGUAGES[@]}"; do
    lang_code="${lang_pair%%:*}"

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

    LANGS_TO_PROCESS+=("$lang_pair")
done

# Process languages in parallel using semaphore pattern
if [ ${#LANGS_TO_PROCESS[@]} -eq 0 ]; then
    echo -e "${RED}No languages to process${NC}"
    exit 0
fi

echo -e "${BLUE}Processing ${#LANGS_TO_PROCESS[@]} language(s) with up to $MAX_PARALLEL parallel jobs...${NC}"
echo ""

# Create semaphore using a fifo
mkfifo "$TEMP_DIR/sem"
exec 3<>"$TEMP_DIR/sem"

# Initialize semaphore with MAX_PARALLEL tokens
for ((i=0; i<MAX_PARALLEL; i++)); do
    echo >&3
done

# Export functions and variables for subshells
export -f process_language validate_locale claude_with_retry
export GREEN BLUE YELLOW RED NC TEMP_DIR REFERENCE_FILE

# Launch all jobs with semaphore control
for lang_pair in "${LANGS_TO_PROCESS[@]}"; do
    # Acquire semaphore (blocks if all slots are in use)
    read -u 3

    # Run in background, release semaphore when done
    (
        process_language "$lang_pair"
        echo >&3  # Release semaphore
    ) &
done

# Wait for all background jobs to complete
wait

# Close the semaphore fd
exec 3>&-

# Aggregate results
echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}=====================================${NC}"

success_count=0
failed_count=0
success_langs=""
failed_langs=""

for result_file in "$TEMP_DIR"/result_*; do
    [ -f "$result_file" ] || continue
    result=$(cat "$result_file")
    status="${result%%:*}"
    rest="${result#*:}"
    lang_code="${rest%%:*}"
    lang_name="${rest#*:}"

    if [ "$status" = "success" ]; then
        ((success_count++)) || true
        success_langs="$success_langs $lang_code"
    else
        ((failed_count++)) || true
        failed_langs="$failed_langs $lang_code"
    fi
done

echo -e "${GREEN}✓ Succeeded: $success_count${NC}${success_langs:+ ($success_langs )}"
if [ $failed_count -gt 0 ]; then
    echo -e "${YELLOW}⚠ Failed validation: $failed_count${NC} ($failed_langs )"
fi

echo ""
echo -e "${GREEN}All locale updates completed!${NC}"
echo ""
echo "Verify the translations and make any necessary adjustments."