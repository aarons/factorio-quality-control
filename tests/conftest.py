#!/usr/bin/env python3
"""
Shared fixtures and utilities for the Factorio mod validation test suite.
"""

import os
import re
from pathlib import Path
from typing import List, Tuple, Generator


def find_lua_files(project_root: Path = None) -> List[Path]:
    """
    Find all Lua files in the project, excluding certain directories.
    
    Args:
        project_root: Root directory to search from. If None, uses parent of validation dir.
        
    Returns:
        List of Path objects for all Lua files found.
    """
    if project_root is None:
        # Default to parent directory of validation folder
        project_root = Path(__file__).parent.parent
        
    lua_files = []
    
    # Directories to exclude from search
    exclude_dirs = {'archive', 'test', 'tests', '.git', '__pycache__', 'node_modules', 'validation', 'references'}
    
    for root, dirs, files in os.walk(project_root):
        # Remove excluded directories from search
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        
        for file in files:
            if file.endswith('.lua'):
                lua_files.append(Path(root) / file)
    
    return lua_files


def read_file_lines(filepath: Path) -> Generator[Tuple[int, str], None, None]:
    """
    Read a file and yield (line_number, line) tuples.
    
    Args:
        filepath: Path to the file to read
        
    Yields:
        Tuple of (line_number, line_content) starting from line 1
        
    Raises:
        Exception if file cannot be read
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            yield line_num, line


def format_validation_errors(errors: List[Tuple[str, int, str]]) -> str:
    """
    Format a list of validation errors into a readable string.
    
    Args:
        errors: List of (filepath, line_number, message) tuples
        
    Returns:
        Formatted error message string
    """
    if not errors:
        return ""
        
    error_lines = [f"  {filepath}:{line_num}: {message}" for filepath, line_num, message in errors]
    return "\n".join(error_lines)


def is_in_string_literal(line: str, position: int) -> bool:
    """
    Check if a position in a line is inside a string literal.
    
    Args:
        line: The line of code to check
        position: The character position to check
        
    Returns:
        True if the position is inside a string literal, False otherwise
    """
    in_single = False
    in_double = False
    i = 0
    
    while i < position and i < len(line):
        if line[i] == '"' and not in_single and (i == 0 or line[i-1] != '\\'):
            in_double = not in_double
        elif line[i] == "'" and not in_double and (i == 0 or line[i-1] != '\\'):
            in_single = not in_single
        i += 1
        
    return in_single or in_double


def remove_comments_from_line(line: str) -> str:
    """
    Remove comments from a line of Lua code, preserving comments inside strings.
    
    Args:
        line: The line of code to process
        
    Returns:
        The line with comments removed
    """
    comment_pos = line.find('--')
    if comment_pos != -1 and not is_in_string_literal(line, comment_pos):
        return line[:comment_pos].rstrip()
    return line


def is_multiline_comment_start(line: str) -> bool:
    """Check if line starts a multiline comment."""
    return '--[[' in line


def is_multiline_comment_end(line: str) -> bool:
    """Check if line ends a multiline comment."""
    return ']]' in line


def is_single_line_comment(line: str) -> bool:
    """Check if line is a single-line comment."""
    return line.strip().startswith('--')