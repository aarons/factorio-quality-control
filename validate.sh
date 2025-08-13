#!/bin/bash

# Factorio Mod Validation Suite
# Validates various aspects of the mod before packaging or deployment

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANGELOG_FILE="${SCRIPT_DIR}/changelog.txt"

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

# Function to check if Python is available
check_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        # Check if it's Python 3
        if python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
            echo "python"
        else
            print_status $RED "Error: Python 3 is required but not found"
            exit 1
        fi
    else
        print_status $RED "Error: Python 3 is required but not found"
        exit 1
    fi
}

# Function to validate changelog
validate_changelog() {
    local python_cmd=$(check_python)
    print_status $YELLOW "Validating changelog..."
    
    if [ ! -f "$CHANGELOG_FILE" ]; then
        print_status $RED "Error: changelog.txt not found"
        return 1
    fi
    
    if $python_cmd "${SCRIPT_DIR}/validate_changelog.py" "$CHANGELOG_FILE"; then
        print_status $GREEN "✓ Changelog validation passed"
        return 0
    else
        print_status $RED "✗ Changelog validation failed"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Factorio Mod Validation Suite"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --changelog     Validate changelog.txt only"
    echo "  -a, --all          Run all validations (default)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run all validations"
    echo "  $0 --changelog     # Validate only changelog"
}

# Main function
main() {
    local validate_changelog_only=false
    local run_all=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--changelog)
                validate_changelog_only=true
                run_all=false
                shift
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
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
    
    local exit_code=0
    
    print_status $YELLOW "🔍 Running Factorio mod validation..."
    echo ""
    
    # Run changelog validation
    if [ "$validate_changelog_only" = true ] || [ "$run_all" = true ]; then
        if ! validate_changelog; then
            exit_code=1
        fi
    fi
    
    # Future validations can be added here
    # if [ "$run_all" = true ]; then
    #     # Add more validation functions here
    #     # validate_info_json
    #     # validate_locale_files
    #     # validate_lua_syntax
    # fi
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "🎉 All validations passed!"
    else
        print_status $RED "❌ Some validations failed"
    fi
    
    exit $exit_code
}

# Run main function with all arguments
main "$@"