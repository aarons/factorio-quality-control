# Lua Validation System

This directory contains the extensible Lua validation system for the Quality Control Factorio mod.

## Overview

The `lua_validator.py` script provides modular validation checks for Lua code specific to Factorio mod requirements. It's designed to be easily extended with new validation rules over time.

## Current Validation Rules

### check_require_placement
Ensures that `require()` statements only appear at the top level of files, not inside functions or conditional blocks. This is a Factorio mod requirement.

## Adding New Validation Rules

To add a new validation rule:

1. Add a new method to the `LuaValidator` class in `lua_validator.py`:
   ```python
   def check_your_rule_name(self, filepath: Path, lines: List[str]) -> None:
       """Description of what this rule validates."""
       # Your validation logic here
       # Add errors using: self.errors.append((str(filepath), line_num, "Error message"))
       # Add warnings using: self.warnings.append((str(filepath), line_num, "Warning message"))
   ```

2. Call your new method from `validate_file()`:
   ```python
   def validate_file(self, filepath: Path) -> None:
       # ... existing code ...
       self.check_your_rule_name(filepath, lines)
   ```

## Example Validation Rules to Add

Here are some validation rules that could be added in the future:

### check_global_usage
- Ensure globals are properly declared and accessed
- Detect accidental global variable creation
- Validate use of `global` table

### check_event_handlers
- Validate event handler registration patterns
- Ensure proper event handler signatures
- Check for common event handling mistakes

### check_api_patterns
- Detect common Factorio API misuse
- Validate entity validity checks before operations
- Check for proper nil handling

### check_performance_patterns
- Detect inefficient patterns (e.g., repeated API calls in loops)
- Suggest caching opportunities
- Warn about expensive operations

## Running the Validator

The validator is automatically run as part of `validate.sh`. To run it standalone:

```bash
python3 validation/lua_validator.py
```

## Output Format

The validator outputs errors in a format compatible with most editors and CI systems:
```
filepath:line_number: error message
```

Example:
```
scripts/inventory.lua:234: require() must be at top-level, not inside function 'on_robot_built_entity'
```

## Design Principles

1. **Modular**: Each validation rule is a separate method
2. **Extensible**: Easy to add new rules without modifying core logic
3. **Clear Output**: File:line format for easy navigation
4. **Fast**: Efficient parsing suitable for CI/CD pipelines
5. **Comprehensive**: Validates all .lua files in the project (excluding test/archive directories)