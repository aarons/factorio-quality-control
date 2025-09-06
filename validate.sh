#!/bin/bash

# Factorio Mod Validation Suite
# Validates various aspects of the mod before packaging or deployment

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


# Function to setup validation environment
setup_validation_env() {
    local tests_dir="${SCRIPT_DIR}/tests"
    local venv_dir="${tests_dir}/venv"

    # Create virtual environment if it doesn't exist
    if [ ! -d "$venv_dir" ]; then
        print_status $YELLOW "Setting up validation environment..."
        python3 -m venv "$venv_dir"
        source "$venv_dir/bin/activate"
        pip install -r "${tests_dir}/requirements.txt" >/dev/null 2>&1
        deactivate
    fi
}


# Function to run luacheck
run_luacheck() {
    local output
    output=$(luacheck . --quiet --exclude-files references/ 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "✅ Luacheck passed"
        return 0
    else
        print_status $RED "❌ Luacheck failed"
        echo "$output"
        return 1
    fi
}

# Function to run pytest validations
run_pytest_validations() {
    setup_validation_env

    local tests_dir="${SCRIPT_DIR}/tests"
    cd "$tests_dir"

    # Activate virtual environment and run pytest
    source venv/bin/activate
    local output
    output=$(python -m pytest --tb=short 2>&1)
    local exit_code=$?
    deactivate

    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "✅ Pytests passed"
        return 0
    else
        print_status $RED "❌ Pytests failed"
        echo "$output"
        return 1
    fi
}

# Function to run comprehensive validation
run_comprehensive_validation() {
    # Run luacheck
    if ! run_luacheck; then
        return 1
    fi

    # Run all pytest tests (includes Lua syntax validation)
    if ! run_pytest_validations; then
        return 1
    fi

    return 0
}

# Function to show usage
show_usage() {
    echo "Factorio Mod Validation Suite"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run all validations"
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

    local exit_code=0

    print_status $YELLOW "Running Quality Control mod validation..."

    # Run whitespace cleanup first
    local whitespace_output
    whitespace_output=$("${SCRIPT_DIR}/cleanup-whitespace.sh" 2>&1)
    if [ -n "$whitespace_output" ]; then
        echo "$whitespace_output"
        echo ""
    fi

    # Run comprehensive validation tests
    if ! run_comprehensive_validation; then
        exit_code=1
    fi

    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "✅ All validations passed"
    else
        print_status $RED "❌ Some validations failed"
    fi

    exit $exit_code
}

# Run main function with all arguments
main "$@"