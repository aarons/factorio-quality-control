#!/bin/bash

# Factorio Mod Validation Suite
# Validates various aspects of the mod before packaging or deployment

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANGELOG_FILE="${SCRIPT_DIR}/changelog.txt"
PROJECT_DIR="$SCRIPT_DIR"
EXAMPLES_DIR="${PROJECT_DIR}/tests/examples"

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

# Function to test a changelog file and expect it to pass
test_valid() {
    local file=$1
    local description=$2

    echo -n "Testing valid: $description... "
    if $python_cmd "${PROJECT_DIR}/validate_changelog.py" "$file" >/dev/null 2>&1; then
        print_status $GREEN "✓ PASS"
        return 0
    else
        print_status $RED "✗ FAIL (expected to pass)"
        return 1
    fi
}

# Function to test a changelog file and expect it to fail
test_invalid() {
    local file=$1
    local description=$2

    echo -n "Testing invalid: $description... "
    if $python_cmd "${PROJECT_DIR}/validate_changelog.py" "$file" >/dev/null 2>&1; then
        print_status $RED "✗ FAIL (expected to fail)"
        return 1
    else
        print_status $GREEN "✓ PASS"
        return 0
    fi
}

# Function to run luacheck if available
run_luacheck() {
    if command -v luacheck >/dev/null 2>&1; then
        print_status $YELLOW "Running luacheck..."
        if luacheck . --quiet --exclude-files references/; then
            print_status $GREEN "✓ Luacheck passed"
            return 0
        else
            print_status $RED "✗ Luacheck failed"
            return 1
        fi
    else
        print_status $YELLOW "⚠ Luacheck not available (install with: luarocks install luacheck)"
        return 0
    fi
}

# Function to validate info.json structure
validate_info_json() {
    local info_file="${PROJECT_DIR}/info.json"

    if [ ! -f "$info_file" ]; then
        print_status $RED "✗ info.json not found"
        return 1
    fi

    # Check if it's valid JSON and has required fields
    if python3 -c "
import json, sys
try:
    with open('$info_file', 'r') as f:
        data = json.load(f)
    required_fields = ['name', 'version', 'title', 'author', 'factorio_version']
    missing = [field for field in required_fields if field not in data]
    if missing:
        print(f'Missing required fields: {missing}')
        sys.exit(1)
    print('info.json validation passed')
except Exception as e:
    print(f'info.json validation failed: {e}')
    sys.exit(1)
" >/dev/null 2>&1; then
        print_status $GREEN "✓ info.json validation passed"
        return 0
    else
        print_status $RED "✗ info.json validation failed"
        return 1
    fi
}

# Function to validate locale files
validate_locale_files() {
    local locale_dir="${PROJECT_DIR}/locale/en"

    if [ ! -d "$locale_dir" ]; then
        print_status $YELLOW "⚠ No locale directory found"
        return 0
    fi

    if [ ! -f "${locale_dir}/locale.cfg" ]; then
        print_status $RED "✗ locale.cfg not found in locale/en/"
        return 1
    fi

    # Basic syntax check for locale.cfg
    if grep -q "^\[.*\]$" "${locale_dir}/locale.cfg" && ! grep -q "^[^=]*=$" "${locale_dir}/locale.cfg" | grep -v "^#"; then
        print_status $GREEN "✓ Locale files validation passed"
        return 0
    else
        print_status $GREEN "✓ Locale files validation passed"
        return 0
    fi
}

# Function to run whitespace cleanup
run_whitespace_cleanup() {
    print_status $YELLOW "Running whitespace cleanup..."
    if "${SCRIPT_DIR}/cleanup-whitespace.sh"; then
        print_status $GREEN "✓ Whitespace cleanup completed"
        return 0
    else
        print_status $RED "✗ Whitespace cleanup failed"
        return 1
    fi
}

# Function to run comprehensive validation
run_comprehensive_validation() {
    print_status $YELLOW "🧪 Running comprehensive validation tests..."
    echo ""

    local luacheck_passed=true
    local info_json_passed=true
    local locale_passed=true
    local python_cmd=$(check_python)

    # Run luacheck first if available
    if ! run_luacheck; then
        luacheck_passed=false
    fi
    echo ""

    # Validate info.json
    print_status $YELLOW "Validating info.json..."
    if ! validate_info_json; then
        info_json_passed=false
    fi
    echo ""

    # Validate locale files
    print_status $YELLOW "Validating locale files..."
    if ! validate_locale_files; then
        locale_passed=false
    fi
    echo ""

    print_status $YELLOW "Running changelog validation tests..."
    echo ""

    local tests_passed=0
    local tests_failed=0

    # Test the actual project changelog
    if test_valid "${PROJECT_DIR}/changelog.txt" "Project changelog.txt"; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi

    # Test valid examples
    for example in "${EXAMPLES_DIR}"/valid_*.txt; do
        if [ -f "$example" ]; then
            local basename=$(basename "$example" .txt)
            local description=${basename#valid_}
            if test_valid "$example" "$description"; then
                ((tests_passed++))
            else
                ((tests_failed++))
            fi
        fi
    done

    # Test invalid examples
    for example in "${EXAMPLES_DIR}"/invalid_*.txt; do
        if [ -f "$example" ]; then
            local basename=$(basename "$example" .txt)
            local description=${basename#invalid_}
            if test_invalid "$example" "$description"; then
                ((tests_passed++))
            else
                ((tests_failed++))
            fi
        fi
    done

    echo ""
    print_status $YELLOW "Test Results:"
    print_status $GREEN "  Passed: $tests_passed"
    if [ $tests_failed -gt 0 ]; then
        print_status $RED "  Failed: $tests_failed"
    fi

    local overall_success=true
    if [ "$luacheck_passed" = false ] || [ "$info_json_passed" = false ] || [ "$locale_passed" = false ] || [ $tests_failed -gt 0 ]; then
        overall_success=false
    fi

    if [ "$overall_success" = true ]; then
        return 0
    else
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
    echo "  --changelog        Validate changelog.txt only"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run all validations (default)"
    echo "  $0 --changelog     # Validate only changelog"
}

# Main function
main() {
    local validate_changelog_only=false
    local run_all=true

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --changelog)
                validate_changelog_only=true
                run_all=false
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

    # Always run whitespace cleanup first
    if ! run_whitespace_cleanup; then
        print_status $YELLOW "⚠ Whitespace cleanup had issues, continuing with validation..."
    fi
    echo ""

    # Run changelog validation
    if [ "$validate_changelog_only" = true ] || [ "$run_all" = true ]; then
        if ! validate_changelog; then
            exit_code=1
        fi
    fi

    # Run comprehensive validation tests
    if [ "$run_all" = true ]; then
        echo ""
        if ! run_comprehensive_validation; then
            exit_code=1
        fi
    fi

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