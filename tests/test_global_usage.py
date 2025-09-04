#!/usr/bin/env python3
"""
Pytest module to validate that 'global' variable is not assigned to in Lua files.

It's acceptable to read from settings.global, but direct assignments to global
should use 'storage' instead.
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


def check_global_usage(filepath: Path) -> List[Tuple[str, int, str]]:
    """
    Check that 'global' variable is not assigned to in a Lua file.
    
    It's acceptable to read from settings.global, but direct assignments to global
    should use 'storage' instead.
    
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
            
            # Look for global assignments (global = or global[)
            # But exclude settings.global usage
            if re.search(r'\bglobal\s*[=\[]', line_no_comments):
                # Check if it's settings.global (acceptable usage)
                if not re.search(r'settings\.global\s*\[', line_no_comments):
                    # Make sure it's not inside a string literal
                    global_match = re.search(r'\bglobal\s*[=\[]', line_no_comments)
                    if global_match and not is_in_string_literal(line_no_comments, global_match.start()):
                        error_msg = "Use 'storage' instead of assigning to 'global' variable"
                        errors.append((str(filepath), line_num, error_msg))
                        
    except Exception as e:
        errors.append((str(filepath), 0, f"Failed to read file: {e}"))
    
    return errors


def test_no_global_usage():
    """
    Test that 'global' variable is not assigned to in any Lua files.
    
    It's acceptable to read from settings.global, but direct assignments to global
    should use 'storage' instead.
    """
    lua_files = find_lua_files()
    all_errors = []
    
    for lua_file in lua_files:
        file_errors = check_global_usage(lua_file)
        all_errors.extend(file_errors)
    
    if all_errors:
        error_message = f"Found {len(all_errors)} global assignment violations:\n"
        error_message += format_validation_errors(all_errors)
        pytest.fail(error_message)


if __name__ == "__main__":
    # Allow running this test directly for debugging
    test_no_global_usage()
    print("✓ Global usage validation passed")