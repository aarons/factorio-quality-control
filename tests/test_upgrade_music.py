"""Validate musical bounds, sequence state, and cosmetic randomness in Lua."""
import shutil
import subprocess
from pathlib import Path

import pytest


@pytest.mark.parametrize("scenario", ["ranges", "staircase", "wander", "lifecycle", "effects"])
def test_upgrade_music(scenario):
    lua = shutil.which("lua")
    assert lua, "Lua is required for behavioral validation"
    root = Path(__file__).resolve().parent.parent
    result = subprocess.run(
        [lua, "tests/lua/upgrade_music.lua", scenario], cwd=root,
        capture_output=True, text=True, timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr
