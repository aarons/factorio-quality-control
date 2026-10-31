"""Runner failures must not masquerade as passing engine tests.

These use tiny subprocesses, so ordinary validation needs no Factorio install.
"""
import json
from pathlib import Path
import sys

import pytest

import run_factorio as runner


def test_explicit_executable_never_falls_back(tmp_path):
    assert runner.find_factorio(sys.executable) == Path(sys.executable).resolve()
    assert runner.find_factorio(str(tmp_path / "missing-factorio")) is None
    not_executable = tmp_path / "not-executable"
    not_executable.write_text("not a program")
    assert runner.find_factorio(str(not_executable)) is None


def test_data_override_requires_quality_and_never_falls_back(tmp_path):
    data = tmp_path / "data"
    (data / "base").mkdir(parents=True)
    (data / "base/info.json").write_text('{}')
    executable = tmp_path / "bin/factorio"
    assert runner.find_data(executable) is None
    (data / "quality").mkdir()
    (data / "quality/info.json").write_text('{}')
    assert runner.find_data(executable) == data
    assert runner.find_data(executable, tmp_path / "missing") is None


@pytest.mark.parametrize("program,match", [
    ("pass", "Missing"),
    ("print('QC_TEST SUCCESS'); raise SystemExit(1)", "launch failed"),
    ("print('QC_TEST SUCCESS'); print('QC_TEST FAIL: broken')", "reported an error"),
    ("print('QC_TEST SUCCESS'); print('Error while running on_tick')", "reported an error"),
])
def test_completed_process_requires_clean_exit_and_markers(tmp_path, program, match):
    with pytest.raises(RuntimeError, match=match):
        runner.run_bounded([sys.executable, "-c", program], tmp_path / "test.log", 5,
                           ["QC_TEST SUCCESS"])


def test_completed_process_accepts_success(tmp_path):
    log = runner.run_bounded([sys.executable, "-c", "print('QC_TEST SUCCESS')"],
                             tmp_path / "test.log", 5, ["QC_TEST SUCCESS"])
    assert "QC_TEST SUCCESS" in log


@pytest.mark.parametrize("mode", ["save", "premature_exit", "timeout", "assertion"])
def test_checkpoint_wait_and_process_cleanup(tmp_path, monkeypatch, mode):
    processes = []
    original_popen = runner.subprocess.Popen

    def capture_process(*args, **kwargs):
        process = original_popen(*args, **kwargs)
        processes.append(process)
        return process

    monkeypatch.setattr(runner.subprocess, "Popen", capture_process)
    checkpoint = tmp_path / "earned.zip"
    programs = {
        "save": "import sys, time, zipfile\n"
                "print('QC_TEST CHECKPOINT', flush=True)\n"
                "with zipfile.ZipFile(sys.argv[1], 'w') as z: z.writestr('state', 'earned')\n"
                "time.sleep(60)",
        "premature_exit": "pass",
        "timeout": "import time; print('QC_TEST CHECKPOINT', flush=True); time.sleep(60)",
        "assertion": "import time; print('QC_TEST FAIL: broken', flush=True); time.sleep(60)",
    }
    command = [sys.executable, "-c", programs[mode], str(checkpoint)]
    if mode == "save":
        assert "QC_TEST CHECKPOINT" in runner.save_checkpoint(command, tmp_path / "test.log", checkpoint, 5)
    else:
        match = {"premature_exit": "exited before", "timeout": "timed out", "assertion": "reported an error"}[mode]
        with pytest.raises(RuntimeError, match=match):
            runner.save_checkpoint(command, tmp_path / "test.log", checkpoint, 0.5 if mode == "timeout" else 5)
    assert processes and all(process.poll() is not None for process in processes)
    assert (tmp_path / "test.log").exists()


def test_bounded_launch_timeout_reaps_process(tmp_path, monkeypatch):
    processes = []
    original_popen = runner.subprocess.Popen

    def capture_process(*args, **kwargs):
        process = original_popen(*args, **kwargs)
        processes.append(process)
        return process

    monkeypatch.setattr(runner.subprocess, "Popen", capture_process)
    with pytest.raises(RuntimeError, match="timed out"):
        runner.run_bounded([sys.executable, "-c", "import time; time.sleep(60)"],
                           tmp_path / "test.log", 0.1)
    assert processes and all(process.poll() is not None for process in processes)


def test_instrumentation_and_configuration_stay_in_workspace(tmp_path):
    data = tmp_path / "data"
    for name in ("base", "quality", "recycler", "space-age", "elevated-rails"):
        (data / name).mkdir(parents=True)
        (data / name / "info.json").write_text(json.dumps({"name": name}))
    (data / "server-settings.example.json").write_text('{}')
    original = {path: path.read_bytes() for path in (
        runner.REPO / "control.lua", runner.REPO / "scripts/notifications.lua")}
    root = tmp_path / "isolated"
    runner.prepare_workspace(root, data)
    info = json.loads((runner.REPO / "info.json").read_text())
    mod = root / "mods" / f"{info['name']}_{info['version']}"
    assert (mod / "qc_test_hooks.lua").is_file()
    assert "test_append_module_info = append_module_info" in (mod / "scripts/notifications.lua").read_text()
    assert not (mod / "tests").exists()
    assert all(path.read_bytes() == content for path, content in original.items())
    mods = {entry["name"]: entry["enabled"] for entry in json.loads((root / "mods/mod-list.json").read_text())["mods"]}
    assert mods["quality"] and mods["recycler"]
    assert not mods["space-age"] and not mods["elevated-rails"]
    server = json.loads((root / "server.json").read_text())
    assert server["visibility"] == {"public": False, "lan": False}
    assert not server["auto_pause"] and not server["non_blocking_saving"]
    assert f"write-data={root}/user" in (root / "config.ini").read_text()
