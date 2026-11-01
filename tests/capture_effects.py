#!/usr/bin/env python3
"""Capture real notification effects in an isolated graphical Factorio session.

Run from the repository root: python3 tests/capture_effects.py
Produces H.264 MP4 clips and selected PNG stills at 640x640.
Add --sequence to retain the 15 fps PNG frames, or --stills-only to skip video.
Normal saves, mods, configuration, and the running game are never modified.
"""
import argparse
from datetime import datetime
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from run_factorio import REPO, check_log, find_data, find_factorio, stop_process


CASES = [
    {"style": "halo", "entity": "electric-furnace", "before_quality": "normal",
     "quality": "uncommon", "stills": [12, 24, 36, 48]},
    {"style": "rainbow", "entity": "radar", "before_quality": "rare",
     "quality": "epic", "stills": [12, 24, 36, 48]},
    {"style": "badge", "entity": "assembling-machine-2", "before_quality": "epic",
     "quality": "legendary", "stills": [35, 70, 120, 180]},
    {"style": "bubbles", "entity": "beacon", "before_quality": "uncommon",
     "quality": "rare", "module": "speed-module-3", "stills": [45, 75, 105, 135]},
]
RESOLUTION = [640, 640]
ZOOM = 2.5
ENTITY_HEIGHT = 0.7  # Fraction from the top: 30% breathing room below the entity.
FRAME_STEP = 4
FPS = 60 // FRAME_STEP
SETTLE_TICKS = 180  # Let placement dust clear before saving any frames.
LEAD_IN_TICKS = 60  # One second of settled footage before the staged upgrade.
LAST_TICK = LEAD_IN_TICKS + 300


def lua(value):
    """Serialize this fixture's simple JSON-compatible configuration as Lua."""
    if isinstance(value, dict):
        return "{" + ",".join(f"[{json.dumps(k)}]={lua(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def prepare_capture(root, data, sequence):
    info = json.loads((REPO / "info.json").read_text())
    mod = root / "mods" / f"{info['name']}_{info['version']}"
    mod.mkdir(parents=True)
    for name in ("info.json", "control.lua", "data.lua", "settings.lua"):
        shutil.copy2(REPO / name, mod / name)
    for name in ("scripts", "migrations", "locale"):
        shutil.copytree(REPO / name, mod / name)
    shutil.copy2(REPO / "tests/capture/hooks.lua", mod / "qc_capture_hooks.lua")
    with (mod / "control.lua").open("a") as output:
        output.write('\nrequire("qc_capture_hooks")\n')
    scenario = mod / "scenarios/qc-capture"
    scenario.mkdir(parents=True)
    shutil.copy2(REPO / "tests/capture/control.lua", scenario / "control.lua")
    (scenario / "capture_config.lua").write_text(
        "return " + lua({"cases": CASES, "frame_step": FRAME_STEP if sequence else 0,
                         "last_tick": LAST_TICK, "lead_in_ticks": LEAD_IN_TICKS,
                         "settle_ticks": SETTLE_TICKS,
                         "resolution": RESOLUTION,
                         "zoom": ZOOM, "entity_height": ENTITY_HEIGHT}) + "\n")
    builtins = {json.loads(path.read_text())["name"] for path in data.glob("*/info.json")
                if path.parent.name != "core"}
    enabled = {"base", "quality", info["name"]}
    if "recycler" in builtins:
        enabled.add("recycler")
    (root / "mods/mod-list.json").write_text(json.dumps({"mods": [
        {"name": name, "enabled": name in enabled} for name in sorted(builtins | enabled)]}))
    (root / "user").mkdir()
    # Screenshot alt-mode also needs this client preference to reveal beacon modules.
    (root / "config.ini").write_text(
        f"[path]\nread-data={data}\nwrite-data={root}/user\n"
        "[general]\ncheck-updates=false\n"
        "[other]\nshow-tips-and-tricks=false\n"
        "[interface]\nshow-beacon-modules-in-alt-mode=true\n"
        "[graphics]\nfull-screen=false\n")
    (root / "manifest.json").write_text(json.dumps({
        "cases": CASES, "resolution": RESOLUTION, "zoom": ZOOM,
        "entity_height_from_top": ENTITY_HEIGHT, "sequence_fps": FPS if sequence else None,
        "settle_seconds": SETTLE_TICKS / 60,
        "lead_in_seconds": LEAD_IN_TICKS / 60, "upgrade_tick": LEAD_IN_TICKS,
        "tick_origin": "First captured frame, after the uncaptured settling period.",
        "video": {"codec": "h264", "pixel_format": "yuv420p", "crf": 20} if sequence else None,
        "note": "Staged upgrade results rendered by the unmodified production notification functions.",
    }, indent=2) + "\n")


def expected_images(root, sequence):
    output = root / "user/script-output/qc-effects"
    for case in CASES:
        for tick in [0] + [LEAD_IN_TICKS + tick for tick in case["stills"]]:
            yield output / case["style"] / "stills" / f"{tick:04d}.png"
        if sequence:
            for frame in range(LAST_TICK // FRAME_STEP + 1):
                yield output / case["style"] / "sequence" / f"{frame:04d}.png"


def capture(command, root, timeout, sequence):
    log_path = root / "capture.log"
    with log_path.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                log = check_log(log_path)
                if "QC_CAPTURE DONE" in log:
                    missing = [path for path in expected_images(root, sequence)
                               if not path.is_file() or path.stat().st_size < 100]
                    if not missing:
                        return
                if process.poll() is not None:
                    raise RuntimeError(f"Capture exited before all images were saved; inspect {log_path}")
                time.sleep(0.2)
            raise RuntimeError(f"Capture timed out after {timeout}s; inspect {log_path}")
        finally:
            stop_process(process)


def encode_clips(ffmpeg, source, destination):
    """Encode browser-compatible clips; retain the source frames on failure."""
    for case in CASES:
        style = case["style"]
        subprocess.run([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-framerate", str(FPS), "-start_number", "0",
            "-i", str(source / style / "sequence/%04d.png"),
            "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(destination / f"{style}.mp4"),
        ], check=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", default=os.environ.get("QC_FACTORIO"))
    parser.add_argument("--data", default=os.environ.get("QC_FACTORIO_DATA"))
    parser.add_argument("--timeout", type=float, default=180)
    media = parser.add_mutually_exclusive_group()
    media.add_argument("--sequence", action="store_true", help="Keep 15 fps PNG sequences alongside MP4 clips")
    media.add_argument("--stills-only", action="store_true", help="Only capture PNG stills; no FFmpeg required")
    parser.add_argument("--prepare-only", action="store_true", help="Print launch command without opening Factorio")
    parser.add_argument("--output", type=Path, default=REPO / "assets/notifications/captures",
                        help="Parent directory for a new capture folder (default: assets/notifications/captures)")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be a finite positive number")
    video = not args.stills_only
    ffmpeg = shutil.which("ffmpeg")
    if video and not args.prepare_only and ffmpeg is None:
        parser.error("FFmpeg with libx264 is required for MP4 clips; install ffmpeg or use --stills-only")
    executable = find_factorio(args.factorio)
    if executable is None:
        parser.error("Factorio not found; use --factorio or QC_FACTORIO")
    data = find_data(executable, args.data)
    if data is None:
        parser.error("Factorio data with base and quality not found; use --data or QC_FACTORIO_DATA")
    root = Path(tempfile.mkdtemp(prefix="quality-control-capture-"))
    prepare_capture(root, data, video)
    command = [str(executable), "--config", str(root / "config.ini"),
               "--mod-directory", str(root / "mods"), "--load-scenario", "quality-control/qc-capture",
               "--window-size", "1280x800", "--disable-audio"]
    print(f"Capture workspace: {root}", flush=True)
    if args.prepare_only:
        import shlex
        print(shlex.join(command))
        return 0
    capture(command, root, args.timeout, video)
    args.output.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix=datetime.now().strftime("%Y%m%d-%H%M%S-"), dir=args.output))
    source = root / "user/script-output/qc-effects"
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    ignore=None if args.sequence else shutil.ignore_patterns("sequence"))
    shutil.copy2(root / "manifest.json", destination / "manifest.json")
    print(f"Capture output: {destination.resolve()}", flush=True)
    if video:
        encode_clips(ffmpeg, source, destination)
    print(f"Saved {len(CASES) if video else 0} MP4 clips and "
          f"{len(list(destination.rglob('*.png')))} PNGs: {destination.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
