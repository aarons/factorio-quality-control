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

# Function to setup validation environment
setup_validation_env() {
    local validation_dir="${SCRIPT_DIR}/validation"
    local venv_dir="${validation_dir}/venv"
    local python_cmd=$(check_python)

    # Check if virtual environment exists
    if [ ! -d "$venv_dir" ]; then
        print_status $YELLOW "Setting up validation environment..."
        $python_cmd -m venv "$venv_dir"

        # Activate venv and install requirements
        source "$venv_dir/bin/activate"
        pip install -r "${validation_dir}/requirements.txt" >/dev/null 2>&1
        deactivate
    fi

    # Return path to venv python
    echo "${venv_dir}/bin/python"
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

# Function to run pytest validations
run_pytest_validations() {
    local python_cmd=$(setup_validation_env)
    print_status $YELLOW "Running pytest validations..."

    # Run all pytest tests in validation directory
    cd "${SCRIPT_DIR}/validation"
    $python_cmd -m pytest -v --tb=short
}

# Function to run comprehensive validation
run_comprehensive_validation() {
    print_status $YELLOW "🧪 Running comprehensive validation tests..."
    echo ""

    local luacheck_passed=true
    local pytest_passed=true

    # Run luacheck first if available
    if ! run_luacheck; then
        luacheck_passed=false
    fi
    echo ""

    # Run all pytest tests
    if ! run_pytest_validations; then
        pytest_passed=false
    fi
    echo ""

    local overall_success=true
    if [ "$luacheck_passed" = false ] || [ "$pytest_passed" = false ]; then
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

    print_status $YELLOW "🔍 Running Factorio mod validation..."
    echo ""

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