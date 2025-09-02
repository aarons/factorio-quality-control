#!/usr/bin/env python3
"""
Pytest module to validate require() statement placement in Lua files.

Ensures that require() statements only appear at top-level, not inside functions
or conditional blocks, as required by Factorio mods.
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
    is_single_line_comment
)


def check_require_placement(filepath: Path) -> List[Tuple[str, int, str]]:
    """
    Check that require() statements are only at top-level in a Lua file.
    
    Args:
        filepath: Path to the Lua file to check
        
    Returns:
        List of (filepath, line_number, error_message) tuples for any violations
    """
    errors = []
    in_function = False
    function_depth = 0
    function_name = None
    block_depth = 0
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
            stripped = remove_comments_from_line(line).strip()
            
            # Track function definitions
            if (re.match(r'^(local\s+)?function\s+(\w+)', stripped) or 
                re.search(r'(\w+)\s*=\s*function\s*\(', stripped) or 
                re.search(r'function\s*\(', stripped)):
                
                if not in_function:
                    # Extract function name if possible
                    func_match = re.match(r'^(?:local\s+)?function\s+(\w+)', stripped)
                    if func_match:
                        function_name = func_match.group(1)
                    else:
                        func_match = re.search(r'(\w+)\s*=\s*function\s*\(', stripped)
                        if func_match:
                            function_name = func_match.group(1)
                        else:
                            function_name = "<anonymous>"
                    in_function = True
                function_depth += 1
                block_depth += 1
            
            # Track other block constructs
            elif any(keyword in stripped.split() for keyword in ['if', 'for', 'while', 'repeat', 'do']):
                # Make sure these are actual keywords, not part of other identifiers
                for keyword in ['if', 'for', 'while', 'repeat', 'do']:
                    if (re.match(rf'^{keyword}\s', stripped) or 
                        re.search(rf'\s{keyword}\s', stripped) or 
                        re.search(rf'\s{keyword}$', stripped)):
                        block_depth += 1
                        break
            
            # Track end statements
            elif stripped.startswith('end') or stripped == 'end':
                if block_depth > 0:
                    block_depth -= 1
                    if in_function and function_depth > 0:
                        function_depth -= 1
                        if function_depth == 0:
                            in_function = False
                            function_name = None
            
            # Check for require statements
            if 'require' in stripped:
                # Match various require patterns
                require_patterns = [
                    r'require\s*\(',
                    r'require\s*"',
                    r"require\s*'",
                    r'local\s+\w+\s*=\s*require\s*\(',
                    r'local\s+\w+\s*=\s*require\s*"',
                    r"local\s+\w+\s*=\s*require\s*'",
                ]
                
                for pattern in require_patterns:
                    if re.search(pattern, stripped):
                        if in_function:
                            error_msg = f"require() must be at top-level, not inside function '{function_name}'"
                            errors.append((str(filepath), line_num, error_msg))
                        elif block_depth > 0:
                            error_msg = "require() must be at top-level, not inside conditional or loop blocks"
                            errors.append((str(filepath), line_num, error_msg))
                        break
                        
    except Exception as e:
        errors.append((str(filepath), 0, f"Failed to read file: {e}"))
    
    return errors


def test_require_statements_at_top_level():
    """
    Test that all require() statements in the project are at top-level only.
    
    This test validates that require() statements are not placed inside:
    - Functions
    - Conditional blocks (if/else)
    - Loop blocks (for/while/repeat)
    - Other nested constructs
    
    This is required by Factorio's mod loading system.
    """
    lua_files = find_lua_files()
    all_errors = []
    
    for lua_file in lua_files:
        file_errors = check_require_placement(lua_file)
        all_errors.extend(file_errors)
    
    if all_errors:
        error_message = f"Found {len(all_errors)} require() placement violations:\n"
        error_message += format_validation_errors(all_errors)
        pytest.fail(error_message)


if __name__ == "__main__":
    # Allow running this test directly for debugging
    test_require_statements_at_top_level()
    print("✓ Require placement validation passed")