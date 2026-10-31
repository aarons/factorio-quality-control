"""Exercise independent alert settings and cosmetic lifecycle behavior."""
import shutil
import subprocess
from pathlib import Path

import pytest


@pytest.mark.parametrize("scenario", [
    "independent", "chat_and_gps", "sound_surface", "speaker_sounds", "recipients", "lifecycle", "burst",
])
def test_celebrations(scenario):
    lua = shutil.which("lua")
    assert lua, "Lua is required for behavioral validation"
    root = Path(__file__).resolve().parent.parent
    result = subprocess.run(
        [lua, "tests/lua/celebrations.lua", scenario], cwd=root,
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0, result.stdout + result.stderr
