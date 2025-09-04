#!/usr/bin/env python3
"""
Test suite for Lua syntax validation using luac -p.

This test ensures that all Lua files in the project have valid syntax
by using the Lua compiler's parse-only mode.
"""

import subprocess
import shutil
from pathlib import Path
from conftest import find_lua_files


def test_lua_syntax_with_luac():
    """
    Test that all Lua files have valid syntax using luac -p.

    This test uses the Lua compiler (luac) with the -p flag to perform
    parse-only checking, which catches syntax errors including:
    - Goto scope violations
    - Invalid syntax constructs
    - Parse errors
    """
    # Check if luac is available
    if not shutil.which("luac"):
        import pytest
        pytest.skip("luac not available - install Lua to run syntax validation")

    # Find all Lua files in the project
    lua_files = find_lua_files()

    if not lua_files:
        import pytest
        pytest.fail("No Lua files found in project")

    syntax_errors = []

    # Check each file with luac -p
    for lua_file in lua_files:
        try:
            # Run luac -p to check syntax only
            result = subprocess.run(
                ["luac", "-p", str(lua_file)],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode != 0:
                # Extract meaningful error message
                error_msg = result.stderr.strip() if result.stderr else "Unknown syntax error"
                syntax_errors.append((str(lua_file), error_msg))

        except subprocess.TimeoutExpired:
            syntax_errors.append((str(lua_file), "Timeout during syntax checking"))
        except Exception as e:
            syntax_errors.append((str(lua_file), f"Error running luac: {e}"))

    # Report any syntax errors found
    if syntax_errors:
        error_report = "\nLua syntax errors found:\n"
        for filepath, error in syntax_errors:
            error_report += f"  {filepath}: {error}\n"

        import pytest
        pytest.fail(error_report)


