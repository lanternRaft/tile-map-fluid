"""Run repeatable whole-demo trials. Uses stock Godot and the Python standard library."""

import argparse
import hashlib
import json
import math
import shutil
import statistics
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons/tile_map_fluid"
CASES = ("live", "no-spray", "no-contact-ticks", "neither")


def options():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--mode", choices=("throughput", "rendered"), default="throughput")
    parser.add_argument("--cases", nargs="+", choices=CASES, default=["live"])
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--warmup-ticks", type=int, default=240)
    parser.add_argument("--ticks", type=int, help="measured steps in throughput mode (default 3600)")
    parser.add_argument("--seconds", type=float, help="wall time in rendered mode (default 30)")
    parser.add_argument("--speed", type=int, choices=(1, 8), default=1)
    parser.add_argument("--hoses", type=int, choices=range(1, 5), default=1)
    parser.add_argument("--receivers", type=int, default=64)
    parser.add_argument("--barriers", type=int, default=8)
    parser.add_argument("--seed", type=int, default=13463)
    parser.add_argument("--edit-probe", action="store_true", help="time 20 local rebuilds after each trial")
    parser.add_argument("--output", type=Path, help="new report directory (default under reports/benchmarks/live-demo)")
    args = parser.parse_args()
    if args.repeat < 1 or args.warmup_ticks < 1 or len(set(args.cases)) != len(args.cases):
        parser.error("repeat and warmup-ticks must be positive and cases must be unique")
    if not 0 <= args.receivers <= 256 or not 0 <= args.barriers <= 16:
        parser.error("receivers must be in 0..256 and barriers in 0..16")
    if args.mode == "throughput" and (args.seconds is not None or args.speed != 1):
        parser.error("seconds and 8× speed require rendered mode")
    if args.mode == "rendered" and args.ticks is not None:
        parser.error("ticks requires throughput mode")
    if args.ticks is not None and args.ticks < 1:
        parser.error("ticks must be positive")
    if args.seconds is not None and (not math.isfinite(args.seconds) or args.seconds < 1):
        parser.error("seconds must be finite and at least one")
    args.ticks = args.ticks or 3600
    args.seconds = args.seconds or 30
    return args


def import_if_needed(executable, directory):
    if (ROOT / ".godot/global_script_class_cache.cfg").is_file():
        return
    log = directory / "import.log"
    proc = subprocess.run([executable, "--headless", "--editor", "--import", "--quit",
                           "--path", str(ROOT), "--log-file", str(log)],
                          capture_output=True, text=True, timeout=120)
    if proc.returncode or "ERROR:" in proc.stdout + proc.stderr:
        raise ValueError(f"Godot import failed. See {log}")


def source_digest():
    digest = hashlib.sha256()
    for path in sorted([ROOT / "project.godot", Path(__file__).resolve(), *ADDON.rglob("*")]):
        if path.is_file() and path.suffix in {".py", ".gd", ".tscn", ".tres", ".gdshader", ".godot", ".svg", ".import"}:
            digest.update(str(path.relative_to(ROOT)).encode() + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def run():
    args = options()
    executable = shutil.which(args.godot)
    if not executable:
        raise ValueError(f"Godot executable not found: {args.godot}")
    directory = args.output or ROOT / "reports/benchmarks/live-demo" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        raise ValueError(f"Choose an empty output directory: {directory}")
    import_if_needed(executable, directory)
    command = [executable, "--path", str(ROOT), "--audio-driver", "Dummy"]
    if args.mode == "throughput":
        command += ["--headless", "--fixed-fps", "120"]
    else:
        command += ["--rendering-method", "gl_compatibility", "--disable-vsync"]
    source = source_digest()
    results = {case: [] for case in args.cases}
    fingerprints = {}
    for trial in range(1, args.repeat + 1):
        order = args.cases if trial % 2 else reversed(args.cases)
        for case in order:
            name = f"{trial:02d}-{case}"
            output = directory / f"{name}.json"
            config = {key: getattr(args, key) for key in
                      ("mode", "hoses", "receivers", "barriers", "seed", "warmup_ticks",
                       "ticks", "seconds", "speed", "edit_probe")}
            config.update(case=case, output=str(output))
            settings = directory / f"{name}.config.json"
            settings.write_text(json.dumps(config, indent=2))
            log = directory / f"{name}.log"
            cmd = command + ["--log-file", str(log), "--script",
                             "addons/tile_map_fluid/benchmarks/live_demo.gd", "--", str(settings)]
            proc = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, timeout=max(120, args.seconds * 3 + (args.warmup_ticks + args.ticks) / 30))
            if proc.returncode or "ERROR:" in proc.stdout or not output.is_file():
                raise ValueError(f"{name} failed (exit {proc.returncode}). See {log}\n{proc.stdout[-2500:]}")
            data = json.loads(output.read_text())
            if args.mode == "throughput":
                state = (data["field_sha256"], data.get("field_after_refresh_sha256"))
                if data["ticks"] != args.ticks or state != fingerprints.setdefault(case, state):
                    raise ValueError(f"{name}: fixed-tick count or final field differs on replay")
            result = {k: data[k] for k in ("wall_us_per_tick", "tick_rate", "interval_summary_us",
                                            "emissions", "field_sha256", "setup_us")}
            for key in ("fps", "over_budget_fraction", "regional_summary_us"):
                if key in data:
                    result[key] = data[key]
            result["report"] = output.name
            results[case].append(result)
            if args.mode == "rendered":
                p95_ms = data["interval_summary_us"]["p95"] / 1000
                timing = f"{data['fps']:.1f} FPS  p95 {p95_ms:.2f} ms"
            else:
                timing = f"{data['wall_us_per_tick']:.1f} µs/tick"
            print(f"{name}  {timing}  {data['tick_rate']:.0f} ticks/s", flush=True)
    medians = {case: statistics.median(row["wall_us_per_tick"] for row in rows)
               for case, rows in results.items()}
    summary = {"schema": 1, "source_sha256": source, "mode": args.mode,
               "median_wall_us_per_tick": medians, "trials": results}
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(directory / "summary.json")


if __name__ == "__main__":
    try:
        run()
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
