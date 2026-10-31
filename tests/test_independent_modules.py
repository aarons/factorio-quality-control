"""Exercise the real Lua processing code with a small Factorio API double."""
import shutil
import subprocess
from pathlib import Path

import pytest


@pytest.mark.parametrize("scenario", [
    "slot_progression", "empty_and_resized_slots", "meter_rules", "quality_paths",
    "technical_failure", "batch_budget", "capped_and_disabled_hosts",
    "primary_secondary_credits", "replacement", "queue_removal", "legacy_modes",
    "inspection", "lifecycle", "notifications", "failed_host_upgrade",
])
def test_independent_modules(scenario):
    lua = shutil.which("lua")
    assert lua, "Lua is required for behavioral validation"
    root = Path(__file__).resolve().parent.parent
    result = subprocess.run(
        [lua, "tests/lua/independent_modules.lua", scenario],
        cwd=root, capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0, result.stdout + result.stderr
