#!/usr/bin/env python3
"""
Test cases for the profiling system
"""

import re
from pathlib import Path


def test_profiler_module_exists():
    """Test that profiler module exists and has valid content"""
    profiler_path = Path("../scripts/profiler.lua")
    assert profiler_path.exists(), "Profiler module should exist"
    
    # Check that the file can be read and contains expected functions
    with open(profiler_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Verify key functions exist
    expected_functions = [
        'profiler.initialize',
        'profiler.update_settings', 
        'profiler.create_profiler',
        'profiler.start',
        'profiler.stop',
        'profiler.generate_report'
    ]
    
    for func in expected_functions:
        assert func in content, f"Function {func} should exist in profiler module"


def test_profiler_settings_added():
    """Test that profiling settings were added correctly"""
    settings_path = Path("../settings.lua")
    with open(settings_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Check for profiling settings
    expected_settings = [
        'enable-profiling',
        'profiling-detail-level',
        'profiling-report-frequency'
    ]
    
    for setting in expected_settings:
        assert setting in content, f"Setting {setting} should exist in settings.lua"


def test_profiling_commands_added():
    """Test that profiling commands were added to control.lua"""
    control_path = Path("../control.lua")
    with open(control_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Check for profiling commands
    expected_commands = [
        'quality-control-profile',
        'quality-control-stats',
        'quality-control-reset-stats'
    ]
    
    for command in expected_commands:
        assert command in content, f"Command {command} should exist in control.lua"


def test_core_instrumentation():
    """Test that core functions are instrumented with profiling"""
    core_path = Path("../scripts/core.lua")
    with open(core_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Check that profiler is required
    assert 'require("scripts.profiler")' in content, "Profiler should be required in core.lua"
    
    # Check that key functions have profiling instrumentation
    instrumented_functions = [
        'batch_processing',
        'primary_processing', 
        'secondary_processing',
        'upgrade_attempts',
        'network_operations',
        'entity_operations'
    ]
    
    for func_name in instrumented_functions:
        # Look for profiler.create_profiler and profiler.start calls
        create_pattern = f'profiler.create_profiler\\("{func_name}"\\)'
        start_pattern = f'profiler.start\\("{func_name}"\\)'
        stop_pattern = f'profiler.stop\\("{func_name}"'
        
        assert re.search(create_pattern, content), \
            f"Function {func_name} should have profiler.create_profiler call"
        assert re.search(start_pattern, content), \
            f"Function {func_name} should have profiler.start call"  
        assert re.search(stop_pattern, content), \
            f"Function {func_name} should have profiler.stop call"


def test_locale_strings_added():
    """Test that profiling locale strings were added"""
    locale_path = Path("../locale/en/locale.cfg")
    with open(locale_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Check for profiling locale strings
    expected_strings = [
        'enable-profiling=',
        'profiling-detail-level=',
        'profiling-report-frequency='
    ]
    
    for string in expected_strings:
        assert string in content, f"Locale string {string} should exist"