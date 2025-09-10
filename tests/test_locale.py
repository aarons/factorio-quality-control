#!/usr/bin/env python3
"""
Pytest module to validate locale file format and content compliance.

Validates locale.cfg files against Factorio's localization requirements.
"""

import pytest
import re
import configparser
from pathlib import Path
from typing import List, Set, Dict, Tuple


def get_all_locale_files() -> List[Path]:
    """Get all locale.cfg files across all language directories."""
    project_root = Path(__file__).parent.parent
    locale_root = project_root / "locale"
    
    if not locale_root.exists():
        return []
    
    locale_files = []
    for lang_dir in locale_root.iterdir():
        if lang_dir.is_dir():
            locale_file = lang_dir / "locale.cfg"
            if locale_file.exists():
                locale_files.append(locale_file)
    
    return sorted(locale_files)  # Sort for consistent test ordering


def validate_locale_file_with_configparser(locale_file: Path) -> List[str]:
    """Use configparser to validate basic INI format and detect duplicates."""
    errors = []
    
    # Test with strict mode to catch duplicates automatically
    config = configparser.ConfigParser(strict=True)
    try:
        config.read(locale_file, encoding='utf-8')
    except configparser.DuplicateOptionError as e:
        errors.append(f"{locale_file.parent.name}/{locale_file.name}: {str(e)}")
    except configparser.DuplicateSectionError as e:
        errors.append(f"{locale_file.parent.name}/{locale_file.name}: {str(e)}")
    except configparser.ParsingError as e:
        errors.append(f"{locale_file.parent.name}/{locale_file.name}: Parsing error - {str(e)}")
    except UnicodeDecodeError as e:
        errors.append(f"{locale_file.parent.name}/{locale_file.name}: Encoding error - {str(e)}")
    
    return errors


def validate_locale_file_duplicates_manual(locale_file: Path) -> List[str]:
    """Manual duplicate validation with detailed line number reporting."""
    errors = []
    
    try:
        with open(locale_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except UnicodeDecodeError:
        return [f"{locale_file.parent.name}/{locale_file.name}: File encoding error"]
    
    current_section = None
    section_keys: Dict[str, Dict[str, int]] = {}  # section -> {key -> line_number}
    
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
                section_keys[current_section] = {}
            continue
        
        # Check for key=value pairs
        kv_match = re.match(r'^([^=]+)=(.*)$', line)
        if kv_match and current_section:
            key = kv_match.group(1).strip()
            
            # Check for duplicate keys
            if key in section_keys[current_section]:
                original_line = section_keys[current_section][key]
                errors.append(
                    f"{locale_file.parent.name}/{locale_file.name}: Duplicate key '{key}' in section [{current_section}] "
                    f"(first at line {original_line}, duplicate at line {i})"
                )
            else:
                section_keys[current_section][key] = i
    
    return errors


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
    """Test that English locale.cfg doesn't have duplicate keys within sections."""
    project_root = Path(__file__).parent.parent
    locale_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not locale_file.exists():
        pytest.skip("No locale.cfg found")
    
    # Use the manual validation for detailed error reporting
    errors = validate_locale_file_duplicates_manual(locale_file)
    
    if errors:
        pytest.fail("Duplicate keys found:\n" + "\n".join(errors))


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


@pytest.mark.parametrize("locale_file", get_all_locale_files(), ids=lambda f: f"{f.parent.name}/{f.name}")
def test_all_locale_files_configparser_validation(locale_file):
    """Test all locale files with configparser for basic validation."""
    if not locale_file or not locale_file.exists():
        pytest.skip(f"Locale file not found: {locale_file}")
    
    # Use configparser for free validation
    errors = validate_locale_file_with_configparser(locale_file)
    
    if errors:
        pytest.fail(f"Validation errors in {locale_file.parent.name}/{locale_file.name}:\n" + "\n".join(errors))


@pytest.mark.parametrize("locale_file", get_all_locale_files(), ids=lambda f: f"{f.parent.name}/{f.name}")
def test_all_locale_files_no_duplicate_keys(locale_file):
    """Test all locale files for duplicate keys with detailed error reporting."""
    if not locale_file or not locale_file.exists():
        pytest.skip(f"Locale file not found: {locale_file}")
    
    # Use manual validation for detailed line number reporting
    errors = validate_locale_file_duplicates_manual(locale_file)
    
    if errors:
        pytest.fail(f"Duplicate key errors in {locale_file.parent.name}/{locale_file.name}:\n" + "\n".join(errors))


def test_all_locale_files_exist():
    """Test that we found at least some locale files."""
    locale_files = get_all_locale_files()
    assert len(locale_files) > 0, "No locale files found in the project"
    
    # Log which files we found for debugging
    file_names = [f.name for f in locale_files]
    print(f"\nFound {len(locale_files)} locale files: {', '.join(file_names)}")


def get_reference_locale_structure() -> Tuple[Dict[str, Set[str]], Path]:
    """Get the sections and keys from the English locale as reference."""
    project_root = Path(__file__).parent.parent
    reference_file = project_root / "locale" / "en" / "locale.cfg"
    
    if not reference_file.exists():
        return {}, reference_file
    
    config = configparser.ConfigParser(strict=True)
    config.read(reference_file, encoding='utf-8')
    
    reference_structure = {}
    for section in config.sections():
        reference_structure[section] = set(config.options(section))
    
    return reference_structure, reference_file


@pytest.mark.parametrize("locale_file", get_all_locale_files(), ids=lambda f: f"{f.parent.name}/{f.name}")
def test_all_locale_files_complete(locale_file):
    """Test that all locale files have the same sections and keys as English reference."""
    if not locale_file or not locale_file.exists():
        pytest.skip(f"Locale file not found: {locale_file}")
    
    # Skip if this is the English reference file itself
    if locale_file.parent.name == "en":
        return
    
    reference_structure, reference_file = get_reference_locale_structure()
    if not reference_structure:
        pytest.skip("English reference locale not found")
    
    # Read the current locale file
    config = configparser.ConfigParser(strict=True)
    try:
        config.read(locale_file, encoding='utf-8')
    except Exception as e:
        pytest.fail(f"{locale_file.parent.name}/locale.cfg: Failed to parse - {str(e)}")
    
    errors = []
    
    # Check for missing sections
    current_sections = set(config.sections())
    reference_sections = set(reference_structure.keys())
    
    missing_sections = reference_sections - current_sections
    if missing_sections:
        errors.append(f"Missing sections: {', '.join(sorted(missing_sections))}")
    
    # Check for missing keys in each section
    for section in reference_sections:
        if section not in current_sections:
            continue  # Already reported as missing section
        
        reference_keys = reference_structure[section]
        current_keys = set(config.options(section))
        
        missing_keys = reference_keys - current_keys
        if missing_keys:
            errors.append(f"Missing keys in [{section}]: {', '.join(sorted(missing_keys))}")
    
    if errors:
        pytest.fail(f"{locale_file.parent.name}/locale.cfg: Incomplete localization\n" + "\n".join(errors))


@pytest.mark.parametrize("locale_file", get_all_locale_files(), ids=lambda f: f"{f.parent.name}/{f.name}")
def test_all_locale_files_no_extra_content(locale_file):
    """Test that locale files don't have extra sections or keys not in English reference."""
    if not locale_file or not locale_file.exists():
        pytest.skip(f"Locale file not found: {locale_file}")
    
    # Skip if this is the English reference file itself
    if locale_file.parent.name == "en":
        return
    
    reference_structure, reference_file = get_reference_locale_structure()
    if not reference_structure:
        pytest.skip("English reference locale not found")
    
    # Read the current locale file
    config = configparser.ConfigParser(strict=True)
    try:
        config.read(locale_file, encoding='utf-8')
    except Exception as e:
        pytest.fail(f"{locale_file.parent.name}/locale.cfg: Failed to parse - {str(e)}")
    
    errors = []
    
    # Check for extra sections
    current_sections = set(config.sections())
    reference_sections = set(reference_structure.keys())
    
    extra_sections = current_sections - reference_sections
    if extra_sections:
        errors.append(f"Extra sections not in reference: {', '.join(sorted(extra_sections))}")
    
    # Check for extra keys in each section
    for section in current_sections:
        if section not in reference_sections:
            continue  # Already reported as extra section
        
        reference_keys = reference_structure[section]
        current_keys = set(config.options(section))
        
        extra_keys = current_keys - reference_keys
        if extra_keys:
            errors.append(f"Extra keys in [{section}]: {', '.join(sorted(extra_keys))}")
    
    if errors:
        pytest.fail(f"{locale_file.parent.name}/locale.cfg: Contains extra content not in reference\n" + "\n".join(errors))


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
    test_all_locale_files_exist()
    
    # Test all locale files
    locale_files = get_all_locale_files()
    for locale_file in locale_files:
        print(f"Testing {locale_file.name}...")
        test_all_locale_files_configparser_validation(locale_file)
        test_all_locale_files_no_duplicate_keys(locale_file)
    
    print("✓ All locale validation tests passed")