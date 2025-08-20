#!/bin/bash

# Factorio Mod Whitespace Cleanup Script
# Automatically fixes end-of-line whitespace issues in source files

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to clean up whitespace in files
cleanup_whitespace() {
    local files_cleaned=0

    print_status $YELLOW "Cleaning up end-of-line whitespace..."

    # Find and clean up whitespace in relevant source files
    # Include Lua files, JSON files, configuration files, and text files
    local file_patterns=(
        "*.lua"
        "*.json"
        "*.cfg"
        "*.txt"
        "*.md"
        "*.sh"
    )

    for pattern in "${file_patterns[@]}"; do
        # Use find to locate files matching the pattern
        while IFS= read -r -d '' file; do
            # Skip if file doesn't exist (in case find returns nothing)
            [ ! -f "$file" ] && continue

            # Check if file has trailing whitespace
            if grep -q '[[:space:]]\+$' "$file"; then
                print_status $YELLOW "  Cleaning: $file"
                # Remove trailing whitespace using sed
                if sed -i '' 's/[[:space:]]*$//' "$file" 2>/dev/null; then
                    ((files_cleaned++))
                else
                    print_status $YELLOW "  Skipped (permission denied): $file"
                fi
            fi
        done < <(find "$SCRIPT_DIR" -name "$pattern" -type f -not -path "*/references/*" -print0 2>/dev/null || true)
    done

    if [ $files_cleaned -gt 0 ]; then
        print_status $GREEN "✓ Cleaned trailing whitespace from $files_cleaned file(s)"
        return 0
    else
        print_status $GREEN "✓ No trailing whitespace found"
        return 0
    fi
}

# Function to show usage
show_usage() {
    echo "Factorio Mod Whitespace Cleanup Script"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "This script automatically removes trailing whitespace from:"
    echo "  - Lua files (*.lua)"
    echo "  - JSON files (*.json)"
    echo "  - Configuration files (*.cfg)"
    echo "  - Text files (*.txt, *.md)"
    echo "  - Shell scripts (*.sh)"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_status $RED "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    print_status $YELLOW "🧹 Running whitespace cleanup..."
    echo ""

    if cleanup_whitespace; then
        echo ""
        print_status $GREEN "🎉 Whitespace cleanup completed!"
        exit 0
    else
        echo ""
        print_status $RED "❌ Whitespace cleanup failed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"