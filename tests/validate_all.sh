#!/bin/bash

# Test runner for changelog validation
# Tests both valid and invalid changelog examples

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLES_DIR="${SCRIPT_DIR}/examples"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to test a changelog file and expect it to pass
test_valid() {
    local file=$1
    local description=$2
    
    echo -n "Testing valid: $description... "
    if python3 "${PROJECT_DIR}/validate_changelog.py" "$file" >/dev/null 2>&1; then
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
    if python3 "${PROJECT_DIR}/validate_changelog.py" "$file" >/dev/null 2>&1; then
        print_status $RED "✗ FAIL (expected to fail)"
        return 1
    else
        print_status $GREEN "✓ PASS"
        return 0
    fi
}

# Main test runner
main() {
    print_status $YELLOW "🧪 Running changelog validation tests..."
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
    
    if [ $tests_failed -eq 0 ]; then
        print_status $GREEN "🎉 All tests passed!"
        exit 0
    else
        print_status $RED "❌ Some tests failed"
        exit 1
    fi
}

main "$@"