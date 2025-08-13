#!/usr/bin/env python3
"""
Factorio Changelog Validator

Validates changelog.txt files against Factorio's strict formatting requirements.
Provides detailed error messages with line numbers for any violations.
"""

import sys
import re
from typing import List, Set, Tuple, Optional


class ChangelogError:
    def __init__(self, line_number: int, rule: str, message: str):
        self.line_number = line_number
        self.rule = rule
        self.message = message

    def __str__(self):
        return f"Line {self.line_number}: [{self.rule}] {self.message}"


class ChangelogValidator:
    def __init__(self):
        self.errors: List[ChangelogError] = []
        self.versions_seen: Set[str] = set()
        self.current_version: Optional[str] = None
        self.current_category: Optional[str] = None
        self.entries_in_current_category: Set[str] = set()
        
    def add_error(self, line_number: int, rule: str, message: str):
        """Add an error to the validation results"""
        self.errors.append(ChangelogError(line_number, rule, message))

    def validate_file(self, filepath: str) -> bool:
        """Validate a changelog file. Returns True if valid, False otherwise."""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except Exception as e:
            self.add_error(0, "FILE_READ", f"Could not read file: {e}")
            return False

        self._validate_lines(lines)
        return len(self.errors) == 0

    def _validate_lines(self, lines: List[str]):
        """Validate all lines in the changelog"""
        expecting_version_after_separator = False
        
        for i, line in enumerate(lines, 1):
            # Check for tabs and trailing spaces on all lines
            self._check_basic_formatting(line, i)
            
            # Handle empty lines
            if line.strip() == "":
                if expecting_version_after_separator:
                    self.add_error(i, "EMPTY_AFTER_SEPARATOR", 
                                 "Line after version separator cannot be empty")
                continue
            
            # Check what type of line this is
            if self._is_version_separator(line):
                self._validate_version_separator(line, i)
                expecting_version_after_separator = True
                self._reset_version_context()
            elif line.startswith("Version:"):
                if not expecting_version_after_separator:
                    self.add_error(i, "VERSION_WITHOUT_SEPARATOR", 
                                 "Version line must be preceded by version separator")
                self._validate_version_line(line, i)
                expecting_version_after_separator = False
            elif line.startswith("Date:"):
                self._validate_date_line(line, i)
            elif line.startswith("  ") and not line.startswith("    "):
                # Category line (2 spaces, not 4)
                self._validate_category_line(line, i)
            elif line.startswith("    "):
                # Entry line (4+ spaces)
                self._validate_entry_line(line, i)
            else:
                self.add_error(i, "INVALID_LINE_FORMAT", 
                             "Line does not match any valid changelog format")

    def _check_basic_formatting(self, line: str, line_number: int):
        """Check for tabs and trailing spaces"""
        if '\t' in line:
            self.add_error(line_number, "NO_TABS", "Tabs are not allowed")
        
        if line.rstrip('\n').endswith(' '):
            self.add_error(line_number, "NO_TRAILING_SPACES", 
                         "Trailing spaces are not allowed")

    def _is_version_separator(self, line: str) -> bool:
        """Check if line is a version separator"""
        return line.strip() == "-" * 99

    def _validate_version_separator(self, line: str, line_number: int):
        """Validate version separator has exactly 99 dashes"""
        stripped = line.strip()
        if stripped != "-" * 99:
            if set(stripped) == {'-'}:
                self.add_error(line_number, "SEPARATOR_LENGTH", 
                             f"Version separator must be exactly 99 dashes, got {len(stripped)}")
            else:
                self.add_error(line_number, "SEPARATOR_INVALID", 
                             "Version separator must contain only dashes")

    def _validate_version_line(self, line: str, line_number: int):
        """Validate version line format and content"""
        if not line.startswith("Version: "):
            self.add_error(line_number, "VERSION_FORMAT", 
                         "Version line must start with 'Version: ' (note space after colon)")
            return
        
        version_part = line[9:].strip()
        
        # Check version format: number.number.number
        version_pattern = r'^(\d+)\.(\d+)\.(\d+)$'
        match = re.match(version_pattern, version_part)
        
        if not match:
            self.add_error(line_number, "VERSION_PATTERN", 
                         "Version must be in format X.Y.Z where X, Y, Z are numbers")
            return
        
        major, minor, patch = map(int, match.groups())
        
        # Check number ranges (0-65535)
        for num, name in [(major, "major"), (minor, "minor"), (patch, "patch")]:
            if num > 65535:
                self.add_error(line_number, "VERSION_RANGE", 
                             f"Version {name} number {num} exceeds maximum of 65535")
        
        # Check for 0.0.0
        if major == 0 and minor == 0 and patch == 0:
            self.add_error(line_number, "VERSION_ZERO", 
                         "Version 0.0.0 is not considered valid")
        
        # Check for duplicate versions
        if version_part in self.versions_seen:
            self.add_error(line_number, "DUPLICATE_VERSION", 
                         f"Version {version_part} appears multiple times")
        else:
            self.versions_seen.add(version_part)
        
        self.current_version = version_part

    def _validate_date_line(self, line: str, line_number: int):
        """Validate date line format"""
        if not line.startswith("Date: "):
            self.add_error(line_number, "DATE_FORMAT", 
                         "Date line must start with 'Date: ' (note space after colon)")

    def _validate_category_line(self, line: str, line_number: int):
        """Validate category line format"""
        if not line.startswith("  "):
            self.add_error(line_number, "CATEGORY_INDENT", 
                         "Category line must start with exactly 2 spaces")
            return
        
        # Check that it doesn't start with 4 spaces (that would be an entry)
        if line.startswith("    "):
            return  # This will be handled as an entry line
        
        content = line[2:].strip()
        if not content.endswith(':'):
            self.add_error(line_number, "CATEGORY_COLON", 
                         "Category line must end with a colon")
        
        self.current_category = content.rstrip(':')
        self.entries_in_current_category.clear()

    def _validate_entry_line(self, line: str, line_number: int):
        """Validate entry line format"""
        if self.current_category is None:
            self.add_error(line_number, "ENTRY_NO_CATEGORY", 
                         "Entry line must be preceded by a category line")
            return
        
        if line.startswith("    - "):
            # First line of entry
            entry_content = line[6:].strip()
            self._check_duplicate_entry(entry_content, line_number)
        elif line.startswith("      "):
            # Continuation line (6 spaces)
            if not line[6:].strip():
                self.add_error(line_number, "EMPTY_CONTINUATION", 
                             "Continuation lines cannot be empty")
            # Check for duplicate individual lines in multiline entries
            line_content = line[6:].strip()
            self._check_duplicate_entry(line_content, line_number)
        else:
            # Wrong indentation for entry
            spaces = len(line) - len(line.lstrip())
            if spaces < 4:
                self.add_error(line_number, "ENTRY_INDENT", 
                             "Entry lines must start with at least 4 spaces")
            elif line.startswith("    ") and not line.startswith("    - "):
                self.add_error(line_number, "ENTRY_DASH", 
                             "First line of entry must be '    - ' (4 spaces, dash, space)")

    def _check_duplicate_entry(self, content: str, line_number: int):
        """Check for duplicate entries in the current category"""
        if content in self.entries_in_current_category:
            self.add_error(line_number, "DUPLICATE_ENTRY", 
                         f"Duplicate entry in category '{self.current_category}': {content}")
        else:
            self.entries_in_current_category.add(content)

    def _reset_version_context(self):
        """Reset context when starting a new version section"""
        self.current_version = None
        self.current_category = None
        self.entries_in_current_category.clear()

    def print_errors(self):
        """Print all validation errors"""
        if not self.errors:
            print("✅ Changelog validation passed!")
            return
        
        print(f"❌ Found {len(self.errors)} validation error(s):")
        print()
        
        for error in self.errors:
            print(f"  {error}")
        
        print()
        print("Please fix these errors and run validation again.")


def main():
    """Main entry point"""
    if len(sys.argv) != 2:
        print("Usage: python validate_changelog.py <changelog_file>")
        print("Example: python validate_changelog.py changelog.txt")
        sys.exit(1)
    
    filepath = sys.argv[1]
    validator = ChangelogValidator()
    
    print(f"Validating {filepath}...")
    is_valid = validator.validate_file(filepath)
    
    validator.print_errors()
    
    sys.exit(0 if is_valid else 1)


if __name__ == "__main__":
    main()