#!/usr/bin/env python3
"""
Pytest module to validate locale file format and content compliance.

Validates locale.cfg files against Factorio's localization requirements.
"""

import pytest
import re
from pathlib import Path
from typing import List, Set, Dict, Tuple


def test_locale_directory_exists():
    """Test that locale/en directory exists."""
    project_root = Path(__file__).parent.parent
    locale_dir = project_root / "locale" / "en"
    
    if not locale_dir.exists():
        pytest.skip("No locale directory found - this is optional for mods")


def test_locale_cfg_exists():
    """Test that locale.cfg exists if locale directory exists."""
    project_root = Path(__file__).parent.parent
    locale_dir = project_root / "locale" / "en"
    
    if not locale_dir.exists():
        pytest.skip("No locale directory found")
    
    locale_file = locale_dir / "locale.cfg"
    assert locale_file.exists(), "locale.cfg must exist in locale/en/ directory"


def test_locale_cfg_format():
    """Test that locale.cfg follows proper INI-style format."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    with open(locale_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    errors = []
    current_section = None
    section_pattern = r'^\[([^\]]+)\]$'
    key_value_pattern = r'^([^=]+)=(.*)$'
    
    for i, line in enumerate(lines, 1):
        line = line.rstrip('\n')
        
        # Skip empty lines and comments
        if not line.strip() or line.strip().startswith('#'):
            continue
        
        # Check for section headers
        section_match = re.match(section_pattern, line.strip())
        if section_match:
            current_section = section_match.group(1)
            continue
        
        # Check for key=value pairs
        kv_match = re.match(key_value_pattern, line)
        if kv_match:
            if current_section is None:
                errors.append(f"Line {i}: Key-value pair found outside of section: {line}")
            continue
        
        # If we get here, the line doesn't match expected format
        errors.append(f"Line {i}: Invalid locale format: {line}")
    
    if errors:
        pytest.fail("Locale file format errors:\n" + "\n".join(errors))


def test_locale_cfg_no_tabs():
    """Test that locale.cfg doesn't contain tabs."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    with open(locale_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    tab_lines = []
    for i, line in enumerate(lines, 1):
        if '\t' in line:
            tab_lines.append(f"Line {i}: Contains tab character")
    
    if tab_lines:
        pytest.fail("Locale file contains tabs:\n" + "\n".join(tab_lines))


def test_locale_cfg_no_trailing_whitespace():
    """Test that locale.cfg doesn't have trailing whitespace."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    with open(locale_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    trailing_space_lines = []
    for i, line in enumerate(lines, 1):
        if line.rstrip('\n').endswith(' '):
            trailing_space_lines.append(f"Line {i}: Contains trailing whitespace")
    
    if trailing_space_lines:
        pytest.fail("Locale file has trailing whitespace:\n" + "\n".join(trailing_space_lines))


def test_locale_cfg_valid_sections():
    """Test that locale.cfg contains valid section names."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    with open(locale_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Common Factorio locale sections
    valid_sections = {
        'mod-name', 'mod-description', 'mod-setting-name', 'mod-setting-description',
        'setting-value', 'alert-message', 'controls', 'item-name', 'item-description',
        'entity-name', 'entity-description', 'recipe-name', 'recipe-description',
        'technology-name', 'technology-description', 'fluid-name', 'equipment-name',
        'tile-name', 'gui', 'quality-control'  # custom sections are also valid
    }
    
    sections = re.findall(r'^\[([^\]]+)\]', content, re.MULTILINE)
    
    # Check that we have at least some sections
    assert sections, "Locale file must contain at least one section"
    
    # For this specific mod, we expect certain sections to exist
    expected_sections = ['mod-name', 'mod-description']
    missing_expected = [sec for sec in expected_sections if sec not in sections]
    
    if missing_expected:
        pytest.fail(f"Missing expected sections: {missing_expected}")


def test_locale_cfg_no_duplicate_keys():
    """Test that locale.cfg doesn't have duplicate keys within sections."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    with open(locale_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    current_section = None
    section_keys: Dict[str, Set[str]] = {}
    duplicate_errors = []
    
    for i, line in enumerate(lines, 1):
        line = line.rstrip('\n')
        
        # Skip empty lines and comments
        if not line.strip() or line.strip().startswith('#'):
            continue
        
        # Check for section headers
        section_match = re.match(r'^\[([^\]]+)\]$', line.strip())
        if section_match:
            current_section = section_match.group(1)
            if current_section not in section_keys:
                section_keys[current_section] = set()
            continue
        
        # Check for key=value pairs
        kv_match = re.match(r'^([^=]+)=(.*)$', line)
        if kv_match and current_section:
            key = kv_match.group(1).strip()
            if key in section_keys[current_section]:
                duplicate_errors.append(f"Line {i}: Duplicate key '{key}' in section [{current_section}]")
            else:
                section_keys[current_section].add(key)
    
    if duplicate_errors:
        pytest.fail("Duplicate keys found:\n" + "\n".join(duplicate_errors))


def test_locale_cfg_key_value_format():
    """Test that key=value pairs are properly formatted."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    with open(locale_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    format_errors = []
    current_section = None
    
    for i, line in enumerate(lines, 1):
        line = line.rstrip('\n')
        
        # Skip empty lines and comments
        if not line.strip() or line.strip().startswith('#'):
            continue
        
        # Check for section headers
        if re.match(r'^\[([^\]]+)\]$', line.strip()):
            current_section = line.strip()
            continue
        
        # Check for key=value pairs
        kv_match = re.match(r'^([^=]+)=(.*)$', line)
        if kv_match:
            key, value = kv_match.groups()
            
            # Key should not have leading/trailing whitespace
            if key != key.strip():
                format_errors.append(f"Line {i}: Key has leading/trailing whitespace: '{key}'")
            
            # Key should not be empty
            if not key.strip():
                format_errors.append(f"Line {i}: Empty key found")
            
            # Value can be empty (that's valid for locales)
            continue
        
        # If we're in a section and line doesn't match key=value, it's an error
        if current_section and line.strip():
            format_errors.append(f"Line {i}: Invalid key=value format: {line}")
    
    if format_errors:
        pytest.fail("Key=value format errors:\n" + "\n".join(format_errors))


if __name__ == "__main__":
    # Allow running these tests directly for debugging
    test_locale_directory_exists()
    test_locale_cfg_exists()
    test_locale_cfg_format()
    test_locale_cfg_no_tabs()
    test_locale_cfg_no_trailing_whitespace()
    test_locale_cfg_valid_sections()
    test_locale_cfg_no_duplicate_keys()
    test_locale_cfg_key_value_format()
    print("✓ All locale validation tests passed")