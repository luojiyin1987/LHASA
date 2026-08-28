#!/usr/bin/env python3
"""Replay a named LHASA region at an explicit historical UTC time."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

ALLOWED_REGION_KEYS = {"REGION_NAME", "NORTH", "SOUTH", "WEST", "EAST"}
REGION_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay a named LHASA region at a historical UTC time."
    )
    parser.add_argument("region", help="name of regions/<region>.conf")
    parser.add_argument("date", help='UTC time formatted as "YYYY-MM-DD HH:MM"')
    return parser.parse_args()


def parse_region_config(path: Path) -> dict[str, str]:
    config: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip("\r")
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Invalid region configuration line: {line}")

        key, value = line.split("=", 1)
        if key not in ALLOWED_REGION_KEYS:
            raise ValueError(f"Unsupported region configuration key: {key}")
        config[key] = value

    missing = [key for key in ("NORTH", "SOUTH", "WEST", "EAST") if not config.get(key)]
    if missing:
        raise ValueError(
            "Region configuration is missing required keys: " + ", ".join(missing)
        )
    return config


def sha256(path: Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_source_state(repo_root: Path) -> tuple[str | None, bool | None]:
    try:
        commit = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
        )
        status = subprocess.run(
            ["git", "-C", str(repo_root), "status", "--porcelain"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None, None

    commit_value = commit.stdout.strip() if commit.returncode == 0 else None
    dirty_value = bool(status.stdout) if status.returncode == 0 else None
    return commit_value, dirty_value


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    if not REGION_PATTERN.fullmatch(args.region):
        raise SystemExit(f"Invalid region name: {args.region}")

    region_config_path = repo_root / "regions" / f"{args.region}.conf"
    if not region_config_path.is_file():
        raise SystemExit(f"Region configuration not found: {region_config_path}")

    try:
        config = parse_region_config(region_config_path)
        requested_time = datetime.strptime(args.date, "%Y-%m-%d %H:%M")
        bbox = {
            "north": float(config["NORTH"]),
            "south": float(config["SOUTH"]),
            "west": float(config["WEST"]),
            "east": float(config["EAST"]),
        }
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    normalized_date = requested_time.strftime("%Y-%m-%d %H:%M")
    run_key = requested_time.strftime("%Y-%m-%dT%H%MZ")
    region_name = config.get("REGION_NAME", args.region)

    runs_root = Path(os.environ.get("RUNS_ROOT", repo_root / "runs")).expanduser().resolve()
    run_dir = runs_root / args.region / run_key
    data_path = Path(os.environ.get("LHASA_DATA_PATH", repo_root)).expanduser().resolve()
    output_format = os.environ.get("FORMAT", "tif")
    threads = os.environ.get("THREADS", "4")
    overwrite = os.environ.get("OVERWRITE", "0")

    if overwrite not in {"0", "1"}:
        raise SystemExit(f"OVERWRITE must be 0 or 1, got: {overwrite}")

    try:
        thread_count = int(threads)
    except ValueError as exc:
        raise SystemExit(f"THREADS must be an integer, got: {threads}") from exc

    git_commit, git_dirty = git_source_state(repo_root)
    region_config_sha256 = sha256(region_config_path)
    model_sha256 = sha256(repo_root / "model.json")

    run_dir.mkdir(parents=True, exist_ok=True)

    print(f"Historical replay: {region_name} at {normalized_date} UTC")
    print(f"Replay output: {run_dir}")

    env = os.environ.copy()
    for key in ("REGION_NAME", "NORTH", "SOUTH", "WEST", "EAST", "DATE", "OUTPUT_PATH"):
        env.pop(key, None)
    env.update(
        {
            "DATE": normalized_date,
            "OUTPUT_PATH": str(run_dir),
            "LEAD_DAYS": "0",
            "FORMAT": output_format,
            "THREADS": str(thread_count),
            "OVERWRITE": overwrite,
            "LHASA_DATA_PATH": str(data_path),
        }
    )

    subprocess.run(
        ["bash", str(script_dir / "regional-run.sh"), args.region],
        cwd=repo_root,
        env=env,
        check=True,
    )

    manifest = {
        "schema_version": 1,
        "region": {
            "id": args.region,
            "name": region_name,
            "config": str(region_config_path.resolve()),
            "config_sha256": region_config_sha256,
            "bbox": bbox,
        },
        "requested_time_utc": normalized_date,
        "run_key": run_key,
        "runtime": {
            "lead_days": 0,
            "format": output_format,
            "threads": thread_count,
            "overwrite": overwrite == "1",
        },
        "source": {
            "git_commit": git_commit,
            "git_dirty": git_dirty,
            "model_sha256": model_sha256,
        },
        "paths": {
            "data": str(data_path),
            "output": str(run_dir),
        },
    }

    manifest_path = run_dir / "run.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Replay manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
