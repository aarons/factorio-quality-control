#!/usr/bin/env python3
"""
Pytest module to validate whitespace compliance in source files.

This performs read-only validation of whitespace issues without modifying files.
The cleanup-whitespace.sh script should be run separately to fix issues.
"""

import pytest
import os
from pathlib import Path
from typing import List, Tuple, Generator
from gitignore_parser import parse_gitignore


def find_source_files(project_root: Path = None) -> List[Path]:
    """
    Find all source files that should be checked for whitespace issues.
    
    Args:
        project_root: Root directory to search from. If None, uses parent of tests dir.
        
    Returns:
        List of Path objects for all source files found.
    """
    if project_root is None:
        project_root = Path(__file__).parent.parent
    
    # Load .gitignore patterns
    gitignore_path = project_root / '.gitignore'
    if gitignore_path.exists():
        matches_gitignore = parse_gitignore(gitignore_path)
    else:
        matches_gitignore = lambda x: False
    
    source_files = []
    
    # File patterns to check for whitespace
    file_patterns = [
        "*.lua",
        "*.json", 
        "*.cfg",
        "*.txt",
        "*.md",
        "*.sh"
    ]
    
    # Directories to exclude from search (in addition to gitignore)
    exclude_dirs = {
        '.git', '__pycache__', 'node_modules', '.pytest_cache'
    }
    
    for pattern in file_patterns:
        for file_path in project_root.rglob(pattern):
            # Check if file is in an excluded directory
            relative_path = file_path.relative_to(project_root)
            if any(excluded in relative_path.parts for excluded in exclude_dirs):
                continue
            
            # Check if file matches gitignore patterns
            if matches_gitignore(str(file_path)):
                continue
            
            # Only include regular files
            if file_path.is_file():
                source_files.append(file_path)
    
    return sorted(source_files)


def check_file_for_whitespace_issues(filepath: Path) -> List[Tuple[int, str]]:
    """
    Check a file for whitespace issues.
    
    Args:
        filepath: Path to the file to check
        
    Returns:
        List of tuples (line_number, issue_description)
    """
    issues = []
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            for line_num, line in enumerate(f, 1):
                # Check for tabs
                if '\t' in line:
                    issues.append((line_num, "Contains tab character"))
                
                # Check for trailing whitespace (excluding the newline)
                line_without_newline = line.rstrip('\n\r')
                if line_without_newline.endswith(' '):
                    issues.append((line_num, "Contains trailing whitespace"))
                
                # Check for trailing tabs
                if line_without_newline.endswith('\t'):
                    issues.append((line_num, "Contains trailing tab"))
    
    except Exception as e:
        issues.append((0, f"Error reading file: {e}"))
    
    return issues


def test_file_whitespace_compliance():
    """Test that all source files don't have whitespace issues."""
    source_files = find_source_files()
    files_with_issues = []
    
    for source_file in source_files:
        issues = check_file_for_whitespace_issues(source_file)
        if issues:
            issue_messages = [f"  Line {line_num}: {issue}" for line_num, issue in issues]
            files_with_issues.append(
                f"{source_file.name}:\n" + "\n".join(issue_messages)
            )
    
    if files_with_issues:
        pytest.fail(
            f"Whitespace issues found in {len(files_with_issues)} file(s):\n\n" + 
            "\n\n".join(files_with_issues) + 
            f"\n\nRun cleanup-whitespace.sh to fix these issues automatically."
        )


def test_source_files_found():
    """Test that we actually found some source files to check."""
    source_files = find_source_files()
    assert len(source_files) > 0, "No source files found to validate"
    
    # Check that we found the expected types of files
    extensions = {f.suffix for f in source_files}
    expected_extensions = {'.lua', '.json', '.cfg', '.txt', '.md', '.sh'}
    
    # We should have at least some of the expected file types
    common_extensions = extensions & expected_extensions
    assert len(common_extensions) > 0, f"Expected to find files with extensions {expected_extensions}, but only found {extensions}"


def test_whitespace_validation_summary():
    """Provide a summary of whitespace validation results."""
    source_files = find_source_files()
    total_files = len(source_files)
    files_with_issues = 0
    total_issues = 0
    
    for source_file in source_files:
        issues = check_file_for_whitespace_issues(source_file)
        if issues:
            files_with_issues += 1
            total_issues += len(issues)
    
    clean_files = total_files - files_with_issues
    
    print(f"\nWhitespace Validation Summary:")
    print(f"  Total files checked: {total_files}")
    print(f"  Clean files: {clean_files}")
    print(f"  Files with issues: {files_with_issues}")
    print(f"  Total issues: {total_issues}")
    
    if files_with_issues > 0:
        print(f"\nRun 'cleanup-whitespace.sh' to automatically fix whitespace issues.")


if __name__ == "__main__":
    # Allow running these tests directly for debugging
    source_files = find_source_files()
    print(f"Found {len(source_files)} source files to check")
    
    total_issues = 0
    for source_file in source_files:
        issues = check_file_for_whitespace_issues(source_file)
        if issues:
            print(f"\nIssues in {source_file.name}:")
            for line_num, issue in issues:
                print(f"  Line {line_num}: {issue}")
            total_issues += len(issues)
    
    if total_issues == 0:
        print("✓ All whitespace validation tests passed")
    else:
        print(f"\n✗ Found {total_issues} whitespace issues")
        print("Run cleanup-whitespace.sh to fix these issues")