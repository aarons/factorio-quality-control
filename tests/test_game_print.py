#!/usr/bin/env python3
"""
Pytest module to validate that 'game.print' is not used in Lua files.

Use 'log' instead of 'game.print' for logging.
"""

import pytest
import re
from pathlib import Path
from typing import List, Tuple

from conftest import (
    find_lua_files,
    read_file_lines,
    format_validation_errors,
    remove_comments_from_line,
    is_multiline_comment_start,
    is_multiline_comment_end,
    is_single_line_comment,
    is_in_string_literal
)


def check_game_print_usage(filepath: Path) -> List[Tuple[str, int, str]]:
    """
    Check that 'game.print' is not used in a Lua file.

    Use 'log' instead of 'game.print' for logging.

    Args:
        filepath: Path to the Lua file to check

    Returns:
        List of (filepath, line_number, error_message) tuples for any violations
    """
    errors = []
    in_multiline_comment = False

    try:
        for line_num, line in read_file_lines(filepath):
            stripped = line.strip()

            # Handle multi-line comments
            if is_multiline_comment_start(line):
                in_multiline_comment = True
            if in_multiline_comment:
                if is_multiline_comment_end(line):
                    in_multiline_comment = False
                continue

            # Skip single-line comments
            if is_single_line_comment(stripped):
                continue

            # Remove inline comments for parsing
            line_no_comments = remove_comments_from_line(line)

            # Look for game.print usage
            if re.search(r'\bgame\.print\s*\(', line_no_comments):
                # Make sure it's not inside a string literal
                match = re.search(r'\bgame\.print\s*\(', line_no_comments)
                if match and not is_in_string_literal(line_no_comments, match.start()):
                    error_msg = "Use 'log' instead of 'game.print' for logging"
                    errors.append((str(filepath), line_num, error_msg))

    except Exception as e:
        errors.append((str(filepath), 0, f"Failed to read file: {e}"))

    return errors


def test_no_game_print():
    """
    Test that 'game.print' is not used in any Lua files.

    Use 'log' instead of 'game.print' for logging.

    migrations/1.3.0.lua is excluded as it needs game.print for user communication.
    """
    lua_files = find_lua_files()
    all_errors = []

    for lua_file in lua_files:
        # Skip migrations/1.3.0.lua - it needs game.print for user communication
        if lua_file.name == '1.3.0.lua' and 'migrations' in lua_file.parts:
            continue

        file_errors = check_game_print_usage(lua_file)
        all_errors.extend(file_errors)

    if all_errors:
        error_message = f"Found {len(all_errors)} game.print usage violations:\n"
        error_message += format_validation_errors(all_errors)
        pytest.fail(error_message)


if __name__ == "__main__":
    # Allow running this test directly for debugging
    test_no_game_print()
    print("✓ game.print validation passed")
