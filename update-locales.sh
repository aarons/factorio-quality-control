#!/bin/bash

# Update locale translations using Claude Code
# This script prompts Claude Code to update locale translations for each language

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Reference file
REFERENCE_FILE="locale/en/locale.cfg"

# Check if reference file exists
if [ ! -f "$REFERENCE_FILE" ]; then
    echo "Error: Reference file $REFERENCE_FILE not found!"
    exit 1
fi

# Language mapping: code -> full name
declare -A LANGUAGES=(
    ["de"]="German"
    ["fr"]="French"
    ["es-ES"]="Spanish (Spain)"
    ["es-419"]="Spanish (Latin America)"
    ["it"]="Italian"
    ["pl"]="Polish"
    ["pt-PT"]="Portuguese (Portugal)"
    ["pt-BR"]="Portuguese (Brazil)"
    ["ru"]="Russian"
    ["ja"]="Japanese"
    ["ko"]="Korean"
    ["zh-CN"]="Chinese (Simplified)"
    ["zh-TW"]="Chinese (Traditional)"
    ["tr"]="Turkish"
    ["cs"]="Czech"
    ["nl"]="Dutch"
    ["uk"]="Ukrainian"
    ["hu"]="Hungarian"
    ["no"]="Norwegian"
    ["fi"]="Finnish"
    ["sv"]="Swedish"
    ["ro"]="Romanian"
    ["el"]="Greek"
    ["th"]="Thai"
    ["vi"]="Vietnamese"
    ["be"]="Belarusian"
    ["ca"]="Catalan"
    ["kk"]="Kazakh"
    ["ka"]="Georgian"
)

echo -e "${BLUE}Quality Control Locale Update Script${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo -e "This script will prompt Claude Code to update locale translations."
echo -e "Reference file: ${GREEN}$REFERENCE_FILE${NC}"
echo ""

# Iterate through each language
for lang_code in "${!LANGUAGES[@]}"; do
    lang_name="${LANGUAGES[$lang_code]}"
    locale_dir="locale/$lang_code"
    locale_file="$locale_dir/locale.cfg"
    
    echo -e "${YELLOW}Processing language: $lang_name ($lang_code)${NC}"
    
    # Create locale directory if it doesn't exist
    if [ ! -d "$locale_dir" ]; then
        echo "Creating directory: $locale_dir"
        mkdir -p "$locale_dir"
    fi
    
    # Prepare the prompt for Claude Code
    prompt="We made some recent changes to locale/en/locale.cfg

Now we need to update the $lang_name translation in $locale_file

It should use locale/en/locale.cfg as the reference."
    
    echo -e "${BLUE}Prompting Claude Code for $lang_name translation...${NC}"
    echo ""
    
    # Execute claude command with proper allowed tools
    claude --allowedTools "Read" "Edit" "Write" "MultiEdit" "$prompt"
    
    echo ""
    echo -e "${GREEN}Completed processing for $lang_name ($lang_code)${NC}"
    echo "----------------------------------------"
    echo ""
done

echo -e "${GREEN}All locale updates completed!${NC}"
echo ""
echo "Verify the translations and make any necessary adjustments."