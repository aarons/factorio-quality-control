#!/usr/bin/env python3
"""
Pytest module to validate that functions called during on_load don't access forbidden globals.

During Factorio's on_load event, the game object is not available. This test ensures
that no functions in the on_load call chain attempt to access forbidden globals like
'game', 'rendering', etc.
"""

import pytest
import re
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional

from conftest import find_lua_files, format_validation_errors


# Globals that are forbidden during on_load
FORBIDDEN_ON_LOAD_GLOBALS = {'game', 'rendering'}


class LuaParser:
    """Unified parser for Lua code analysis."""
    
    def __init__(self, content: str):
        self.content = content
        self.lines = content.split('\n')
    
    def _is_in_comment(self, line_num: int, pos: int) -> bool:
        """Check if position is inside a comment."""
        line = self.lines[line_num]
        
        # Check for single-line comment
        comment_start = line.find('--')
        if comment_start != -1 and comment_start <= pos and not self._is_in_string(line, comment_start):
            return True
        
        # Check for multi-line comment (simplified - good enough for most cases)
        before_pos = self.content[:self._line_pos_to_absolute(line_num, pos)]
        multiline_starts = len(re.findall(r'--\[\[', before_pos))
        multiline_ends = len(re.findall(r'\]\]', before_pos))
        return multiline_starts > multiline_ends
    
    def _is_in_string(self, line: str, pos: int) -> bool:
        """Check if position is inside a string literal."""
        in_single = in_double = False
        for i in range(min(pos, len(line))):
            char = line[i]
            if char == '"' and not in_single and (i == 0 or line[i-1] != '\\'):
                in_double = not in_double
            elif char == "'" and not in_double and (i == 0 or line[i-1] != '\\'):
                in_single = not in_single
        return in_single or in_double
    
    def _line_pos_to_absolute(self, line_num: int, pos: int) -> int:
        """Convert line number and position to absolute content position."""
        return sum(len(line) + 1 for line in self.lines[:line_num]) + pos
    
    def find_function_definitions(self) -> Dict[str, int]:
        """Find all function definitions and their line numbers."""
        functions = {}
        
        # Unified pattern for all function definition styles
        pattern = r'(?:local\s+)?(?:function\s+(\w+(?:\.\w+)?)|(\w+(?:\.\w+)?)\s*=\s*function)\s*\('
        
        for line_num, line in enumerate(self.lines):
            if self._is_in_comment(line_num, 0):
                continue
                
            for match in re.finditer(pattern, line):
                if not self._is_in_string(line, match.start()):
                    func_name = match.group(1) or match.group(2)
                    functions[func_name] = line_num + 1
        
        return functions
    
    def find_on_load_functions(self) -> Optional[List[str]]:
        """Find functions called directly in the on_load handler."""
        pattern = r'script\.on_load\s*\(\s*function\s*\(\s*\)(.*?)end\s*\)'
        match = re.search(pattern, self.content, re.DOTALL)
        
        if not match:
            return None
        
        on_load_body = match.group(1)
        functions = []
        
        # Find function calls in the on_load body
        call_pattern = r'(\w+(?:\.\w+)?)\s*\('
        for call_match in re.finditer(call_pattern, on_load_body):
            func_name = call_match.group(1)
            if func_name != 'script':  # Exclude script.on_event calls
                functions.append(func_name)
        
        return functions
    
    def find_function_calls(self, function_name: str) -> List[str]:
        """Find all function calls within a specific function."""
        # Find the function boundaries
        func_pattern = rf'(?:local\s+)?(?:function\s+{re.escape(function_name)}|{re.escape(function_name)}\s*=\s*function)\s*\('
        
        start_pos = None
        for line_num, line in enumerate(self.lines):
            if re.search(func_pattern, line) and not self._is_in_comment(line_num, 0):
                start_pos = line_num
                break
        
        if start_pos is None:
            return []
        
        # Find function end by counting function/end pairs
        depth = 0
        end_pos = len(self.lines)
        
        for line_num in range(start_pos, len(self.lines)):
            line = self.lines[line_num]
            if self._is_in_comment(line_num, 0):
                continue
                
            depth += len(re.findall(r'\bfunction\b', line))
            depth -= len(re.findall(r'\bend\b', line))
            
            if depth == 0 and line_num > start_pos:
                end_pos = line_num
                break
        
        # Extract function calls from the function body
        function_body = '\n'.join(self.lines[start_pos:end_pos + 1])
        calls = []
        
        call_pattern = r'(\w+(?:\.\w+)?)\s*\('
        for match in re.finditer(call_pattern, function_body):
            func_name = match.group(1)
            if func_name not in ['function', 'if', 'for', 'while']:  # Exclude keywords
                calls.append(func_name)
        
        return calls
    
    def check_forbidden_globals(self, function_name: str) -> List[Tuple[int, str]]:
        """Check if a function uses forbidden globals."""
        errors = []
        
        # Find function boundaries (same logic as find_function_calls)
        func_pattern = rf'(?:local\s+)?(?:function\s+{re.escape(function_name)}|{re.escape(function_name)}\s*=\s*function)\s*\('
        
        start_pos = None
        for line_num, line in enumerate(self.lines):
            if re.search(func_pattern, line) and not self._is_in_comment(line_num, 0):
                start_pos = line_num
                break
        
        if start_pos is None:
            return errors
        
        # Find function end
        depth = 0
        end_pos = len(self.lines)
        
        for line_num in range(start_pos, len(self.lines)):
            line = self.lines[line_num]
            if self._is_in_comment(line_num, 0):
                continue
                
            depth += len(re.findall(r'\bfunction\b', line))
            depth -= len(re.findall(r'\bend\b', line))
            
            if depth == 0 and line_num > start_pos:
                end_pos = line_num
                break
        
        # Check each line in the function for forbidden globals
        # But skip lines that are inside event handler registrations
        in_event_handler = False
        event_handler_depth = 0
        
        for line_num in range(start_pos, end_pos + 1):
            line = self.lines[line_num]
            if self._is_in_comment(line_num, 0):
                continue
            
            # Check if we're entering an event handler registration
            if 'script.on_event' in line and 'function(' in line:
                in_event_handler = True
                event_handler_depth = 0
            
            # Track depth within the event handler
            if in_event_handler:
                event_handler_depth += len(re.findall(r'\bfunction\b', line))
                event_handler_depth -= len(re.findall(r'\bend\b', line))
                
                # If we've closed all functions within the event handler, we're out
                if event_handler_depth <= 0 and line_num > start_pos:
                    in_event_handler = False
                    continue
            
            # Skip forbidden global checks if we're inside an event handler
            if in_event_handler:
                continue
            
            for global_name in FORBIDDEN_ON_LOAD_GLOBALS:
                pattern = rf'\b{global_name}\s*\.'
                for match in re.finditer(pattern, line):
                    if not self._is_in_string(line, match.start()):
                        error_msg = f"Function '{function_name}' accesses forbidden global '{global_name}' during on_load"
                        errors.append((line_num + 1, error_msg))
        
        return errors


def trace_call_chain(initial_functions: List[str], lua_files: List[Path]) -> Set[str]:
    """Trace all functions reachable from initial functions."""
    # Parse all files once
    parsers = {}
    all_functions = {}
    
    for lua_file in lua_files:
        try:
            with open(lua_file, 'r', encoding='utf-8') as f:
                content = f.read()
            parser = LuaParser(content)
            parsers[lua_file] = parser
            
            # Map function names to their file
            functions = parser.find_function_definitions()
            for func_name in functions:
                all_functions[func_name] = lua_file
        except Exception:
            continue
    
    # Trace the call chain
    visited = set()
    to_visit = list(initial_functions)
    
    while to_visit:
        func_name = to_visit.pop(0)
        if func_name in visited or func_name not in all_functions:
            continue
        
        visited.add(func_name)
        
        # Find calls from this function
        lua_file = all_functions[func_name]
        if lua_file in parsers:
            calls = parsers[lua_file].find_function_calls(func_name)
            to_visit.extend(calls)
    
    return visited


def check_on_load_globals() -> List[Tuple[str, int, str]]:
    """Check for forbidden global access in on_load call chain."""
    errors = []
    lua_files = find_lua_files()
    
    # Find control.lua
    control_lua = None
    for lua_file in lua_files:
        if lua_file.name == 'control.lua':
            control_lua = lua_file
            break
    
    if not control_lua:
        return [("control.lua", 0, "control.lua not found")]
    
    # Parse control.lua to find on_load functions
    try:
        with open(control_lua, 'r', encoding='utf-8') as f:
            content = f.read()
        parser = LuaParser(content)
        on_load_functions = parser.find_on_load_functions()
    except Exception as e:
        return [("control.lua", 0, f"Failed to parse control.lua: {e}")]
    
    if not on_load_functions:
        return [("control.lua", 0, "on_load handler not found")]
    
    # Trace all functions in the call chain
    all_on_load_functions = trace_call_chain(on_load_functions, lua_files)
    
    # Check each function for forbidden globals
    parsers = {}
    for lua_file in lua_files:
        try:
            with open(lua_file, 'r', encoding='utf-8') as f:
                content = f.read()
            parsers[lua_file] = LuaParser(content)
        except Exception:
            continue
    
    for func_name in all_on_load_functions:
        for lua_file, parser in parsers.items():
            func_errors = parser.check_forbidden_globals(func_name)
            for line_num, error_msg in func_errors:
                errors.append((str(lua_file), line_num, error_msg))
    
    return errors


def test_no_forbidden_globals_in_on_load():
    """
    Test that functions called during on_load don't access forbidden globals.
    
    During on_load, the game object is not available, so accessing it will cause
    runtime errors.
    """
    errors = check_on_load_globals()
    
    if errors:
        error_message = f"Found {len(errors)} forbidden global access violations in on_load chain:\n"
        error_message += format_validation_errors(errors)
        pytest.fail(error_message)


if __name__ == "__main__":
    test_no_forbidden_globals_in_on_load()
    print("✓ on_load global validation passed")