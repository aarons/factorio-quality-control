#!/usr/bin/env python3
"""
Pytest module to validate info.json format and content compliance.

Validates info.json files against Factorio's mod requirements and best practices.
"""

import json
import pytest
import re
from pathlib import Path
from typing import Dict, Any, List


def test_info_json_exists():
    """Test that info.json exists in the project root."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    assert info_path.exists(), f"info.json not found at {info_path}"


def test_info_json_valid_format():
    """Test that info.json is valid JSON."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    try:
        with open(info_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"info.json is not valid JSON: {e}")
    except Exception as e:
        pytest.fail(f"Error reading info.json: {e}")

    assert isinstance(data, dict), "info.json must contain a JSON object"


def test_info_json_required_fields():
    """Test that info.json contains all required fields."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    with open(info_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    required_fields = ['name', 'version', 'title', 'author', 'factorio_version']
    missing_fields = [field for field in required_fields if field not in data]

    assert not missing_fields, f"Missing required fields in info.json: {missing_fields}"


def test_info_json_version_format():
    """Test that version follows semantic versioning format."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    with open(info_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    version = data.get('version')
    assert version, "Version field is required"

    # Version must be in format X.Y.Z where X, Y, Z are numbers
    version_pattern = r'^(\d+)\.(\d+)\.(\d+)$'
    match = re.match(version_pattern, version)

    assert match, f"Version '{version}' must be in format X.Y.Z where X, Y, Z are numbers"

    major, minor, patch = map(int, match.groups())

    # Check number ranges (0-65535)
    for num, name in [(major, "major"), (minor, "minor"), (patch, "patch")]:
        assert 0 <= num <= 65535, f"Version {name} number {num} must be between 0 and 65535"

    # Check for 0.0.0
    assert not (major == 0 and minor == 0 and patch == 0), "Version 0.0.0 is not valid"


def test_info_json_factorio_version_format():
    """Test that factorio_version is in correct format."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    with open(info_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    factorio_version = data.get('factorio_version')
    assert factorio_version, "factorio_version field is required"

    # Can be either "X.Y" or "X.Y.Z" format
    version_pattern = r'^(\d+)\.(\d+)(?:\.(\d+))?$'
    match = re.match(version_pattern, factorio_version)

    assert match, f"factorio_version '{factorio_version}' must be in format X.Y or X.Y.Z"


def test_info_json_string_fields():
    """Test that string fields are non-empty strings."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    with open(info_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    string_fields = ['name', 'version', 'title', 'author', 'factorio_version']
    optional_string_fields = ['description', 'homepage']

    for field in string_fields:
        value = data.get(field)
        assert isinstance(value, str), f"Field '{field}' must be a string"
        assert value.strip(), f"Field '{field}' cannot be empty"

    for field in optional_string_fields:
        if field in data:
            value = data[field]
            assert isinstance(value, str), f"Optional field '{field}' must be a string"
            assert value.strip(), f"Optional field '{field}' cannot be empty"


def test_info_json_dependencies_format():
    """Test that dependencies field is properly formatted if present."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    with open(info_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    if 'dependencies' not in data:
        return  # Dependencies are optional

    dependencies = data['dependencies']
    assert isinstance(dependencies, list), "dependencies must be a list"

    for i, dep in enumerate(dependencies):
        assert isinstance(dep, str), f"Dependency {i} must be a string"
        assert dep.strip(), f"Dependency {i} cannot be empty"

        # Check for valid dependency format
        # Can be: "mod", "? mod", "! mod", "(?) mod", "mod >= version", etc.
        dep_pattern = r'^[!?()]*\s*[a-zA-Z0-9_-]+(\s*[><=]+\s*[\d.]+)?$'
        assert re.match(dep_pattern, dep), f"Dependency '{dep}' has invalid format"


def test_info_json_boolean_flags():
    """Test that boolean flags are properly formatted if present."""
    project_root = Path(__file__).parent.parent
    info_path = project_root / "quality-control" / "info.json"

    with open(info_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    boolean_flags = [
        'quality_required',
        'rail_bridges_required',
        'space_travel_required',
        'spoiling_required',
        'freezing_required',
        'segmented_units_required',
        'expansion_shaders_required'
    ]

    for flag in boolean_flags:
        if flag in data:
            value = data[flag]
            assert isinstance(value, bool), f"Flag '{flag}' must be a boolean (true/false)"




if __name__ == "__main__":
    # Allow running these tests directly for debugging
    test_info_json_exists()
    test_info_json_valid_format()
    test_info_json_required_fields()
    test_info_json_version_format()
    test_info_json_factorio_version_format()
    test_info_json_string_fields()
    test_info_json_dependencies_format()
    test_info_json_boolean_flags()
    print("✓ All info.json validation tests passed")