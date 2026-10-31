#!/usr/bin/env python3
"""Isolated Factorio integration runner, adapted from Auto-Loader.

Use ./validate.sh --in-game. Workspaces are retained, including on failure.
Only base, quality/recycler, the working mod, and the fixture are enabled.
"""
import argparse
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile


REPO = Path(__file__).resolve().parents[1]
FIXTURES = REPO / "tests/factorio"
PREFIX = "QC_TEST "
CASES = ("capped_host", "capacity", "late_insert", "earned_reload", "upgrade_sounds")
FAILURES = ("QC_TEST FAIL:", "Error while running", "Error ", "Factorio crashed")


def find_factorio(explicit=None):
    candidates = [explicit] if explicit else [
        "/Applications/factorio.app/Contents/MacOS/factorio", shutil.which("factorio")]
    return next((Path(p).resolve() for p in candidates
                 if p and Path(p).is_file() and os.access(p, os.X_OK)), None)


def find_data(executable, explicit=None):
    candidates = [Path(explicit).resolve()] if explicit else [
        executable.parent.parent / "data", executable.parent.parent.parent / "data"]
    return next((p for p in candidates
                 if all((p / name / "info.json").is_file() for name in ("base", "quality"))), None)


def check_log(path, markers=()):
    output = path.read_text(errors="replace")
    if any(failure in output for failure in FAILURES):
        raise RuntimeError(f"Factorio reported an error; inspect {path}\n{output[-6000:]}")
    for marker in markers:
        if marker not in output:
            raise RuntimeError(f"Missing {marker!r}; inspect {path}\n{output[-3000:]}")
    return output


def run_bounded(command, path, timeout, markers=()):
    try:
        with path.open("w") as output:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                           check=True, timeout=timeout)
    except subprocess.SubprocessError as error:
        raise RuntimeError(f"Factorio launch failed ({error}); inspect {path}\n"
                           + path.read_text(errors="replace")[-6000:]) from error
    return check_log(path, markers)


def stop_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def save_checkpoint(command, path, checkpoint, timeout):
    """Wait for the actual save to finish, not merely the Lua save request."""
    with path.open("w") as output:
        # Keep stdin open: a detached Factorio server otherwise logs EOF as an
        # error even though it can continue ticking.
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                log = check_log(path)
                if process.poll() is not None:
                    raise RuntimeError(f"Factorio exited before checkpoint completion; inspect {path}")
                if "QC_TEST CHECKPOINT" in log and checkpoint.is_file() and zipfile.is_zipfile(checkpoint):
                    with zipfile.ZipFile(checkpoint) as archive:
                        if archive.testzip() is not None:
                            raise RuntimeError(f"Corrupt checkpoint: {checkpoint}")
                    return log
                time.sleep(0.1)
            raise RuntimeError(f"Factorio checkpoint timed out after {timeout}s; inspect {path}")
        finally:
            stop_process(process)
            process.stdin.close()


def prepare_workspace(root, data):
    info = json.loads((REPO / "info.json").read_text())
    mod = root / "mods" / f"{info['name']}_{info['version']}"
    mod.mkdir(parents=True)
    # Explicit runtime inputs keep tests, local dependencies, and private files out.
    for name in ("info.json", "control.lua", "data.lua", "settings.lua"):
        shutil.copy2(REPO / name, mod / name)
    for name in ("scripts", "migrations", "locale"):
        shutil.copytree(REPO / name, mod / name)

    # All instrumentation is confined to this disposable copy. No production
    # event handler, API object, RNG, or processing function is replaced.
    shutil.copy2(FIXTURES / "hooks.lua", mod / "qc_test_hooks.lua")
    with (mod / "control.lua").open("a") as output:
        output.write('\nrequire("qc_test_hooks")\n')
    notifications = mod / "scripts/notifications.lua"
    source = notifications.read_text()
    anchor = "return notifications"
    if source.count(anchor) != 1:
        raise RuntimeError("Cannot expose inspection helper: notifications.lua return changed")
    notifications.write_text(source.replace(
        anchor, "notifications.test_append_module_info = append_module_info\n" + anchor))

    fixture_name = "quality-control-test"
    fixture = root / "mods" / f"{fixture_name}_0.1.0"
    fixture.mkdir()
    (fixture / "info.json").write_text(json.dumps({
        "name": fixture_name, "version": "0.1.0", "title": "Quality Control engine tests",
        "author": "Quality Control", "factorio_version": info["factorio_version"],
        "dependencies": [info["name"]],
    }))
    for name in ("control.lua", "data-final-fixes.lua", "settings-final-fixes.lua"):
        shutil.copy2(FIXTURES / name, fixture / name)
    enabled = {"base", "quality", info["name"], fixture_name}
    builtins = {json.loads(p.read_text())["name"] for p in data.glob("*/info.json")
                if p.parent.name != "core"}
    # Quality gained a required recycler dependency in Factorio 2.1.
    if "recycler" in builtins:
        enabled.add("recycler")
    (root / "mods/mod-list.json").write_text(json.dumps({"mods": [
        {"name": name, "enabled": name in enabled}
        for name in sorted(builtins | enabled)]}))
    (root / "user/saves").mkdir(parents=True)
    (root / "config.ini").write_text(
        f"[path]\nread-data={data}\nwrite-data={root}/user\n"
        "[general]\ncheck-updates=false\n"
        "[other]\nshow-tips-and-tricks=false\n")
    server = json.loads((data / "server-settings.example.json").read_text())
    server.update({
        "name": "Quality Control isolated tests", "visibility": {"public": False, "lan": False},
        "require_user_verification": False, "auto_pause": False,
        "autosave_interval": 0, "non_blocking_saving": False,
        "username": "", "password": "", "token": "", "allow_commands": "false",
        "game_password": os.urandom(16).hex(),
    })
    (root / "server.json").write_text(json.dumps(server))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", default=os.environ.get("QC_FACTORIO"))
    parser.add_argument("--data", default=os.environ.get("QC_FACTORIO_DATA"))
    parser.add_argument("--timeout", type=float, default=120, help="Seconds per launch")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be a finite positive number")
    executable = find_factorio(args.factorio)
    if executable is None:
        parser.error("Factorio not found; use --factorio or QC_FACTORIO (engine tests cannot be skipped)")
    data = find_data(executable, args.data)
    if data is None:
        parser.error("Factorio data with base and quality not found; use --data or QC_FACTORIO_DATA")

    root = Path(tempfile.mkdtemp(prefix="quality-control-test-"))
    print(f"Test workspace and logs: {root}", flush=True)
    prepare_workspace(root, data)
    command = [str(executable), "--config", str(root / "config.ini"),
               "--mod-directory", str(root / "mods")]
    initial = root / "initial.zip"
    run_bounded(command + ["--create", str(initial), "--map-gen-seed", "12345"],
                root / "create.log", args.timeout)
    checkpoint = root / "user/saves/qc-earned.zip"
    first_log = save_checkpoint(command + [
        "--start-server", str(initial), "--server-settings", str(root / "server.json"),
        "--bind", "127.0.0.1", "--port", "0"], root / "progress.log", checkpoint, args.timeout)
    reload_log = run_bounded(command + [
        "--benchmark", str(checkpoint), "--benchmark-ticks", "600",
        "--benchmark-runs", "1"], root / "reload.log", args.timeout,
        ["QC_TEST PASS earned_reload", "QC_TEST SUCCESS"])
    combined = first_log + reload_log
    for case in CASES:
        if f"QC_TEST PASS {case}" not in combined:
            raise RuntimeError(f"Missing passing case {case}; inspect {root}")
    print("\n".join(line for line in combined.splitlines() if PREFIX in line))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
