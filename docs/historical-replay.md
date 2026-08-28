# Historical regional replay

Historical replay runs the existing LHASA model for a named region at an explicit UTC time and stores the result in a date-scoped output directory. It is intended for comparing LHASA signals around known events without changing or retraining the model.

## Prerequisites

Complete the standard LHASA setup and the regional quickstart first. In particular, the repository must have the required static data and credentials needed to retrieve the historical IMERG and SMAP inputs.

Activate the LHASA environment before running a replay:

```bash
conda activate lhasa
```

## Run one historical time

The replay command requires a checked-in region name and a UTC time in the exact `YYYY-MM-DD HH:MM` format:

```bash
python examples/replay-region.py \
  example-mountain-region \
  "2026-08-28 12:00"
```

The runner deliberately clears inherited coordinate overrides before invoking `regional-run.sh`. A replay therefore uses the bounding box recorded in `regions/<region-name>.conf` rather than an ad-hoc shell environment.

Historical replay currently forces `LEAD_DAYS=0`. The first goal is to reproduce the near-real-time hazard signal for a known point in time, not to mix NRT and forecast behavior in the same experiment.

## Output layout

By default, outputs are stored under `runs/`:

```text
runs/
└── example-mountain-region/
    └── 2026-08-28T1200Z/
        ├── nrt/
        │   └── hazard/
        │       └── tif/
        │           └── ...
        └── run.json
```

Each region/time pair gets a deterministic directory. Different historical dates therefore remain isolated without requiring `OVERWRITE=1`.

If you need a different root—for example, to compare the same region and date across separate code versions—set `RUNS_ROOT`:

```bash
RUNS_ROOT="$PWD/runs-baseline" \
  python examples/replay-region.py example-mountain-region "2026-08-28 12:00"
```

Existing LHASA output files are still protected by default. `OVERWRITE=1` remains an explicit opt-in when replacing an existing replay is intentional.

## Run manifest

After a successful LHASA run, the replay runner writes `run.json`. The manifest records the experiment request and local model state, including:

- named region and WGS84 bounding box;
- SHA256 of the region configuration;
- requested UTC time and stable run key;
- output format, thread count, and overwrite setting;
- repository Git commit and whether the working tree was dirty before replay outputs were created;
- SHA256 of `model.json` when present;
- resolved data and output paths.

Example shape:

```json
{
  "schema_version": 1,
  "region": {
    "id": "example-mountain-region",
    "name": "example-mountain-region",
    "config_sha256": "...",
    "bbox": {
      "north": 30.5,
      "south": 29.5,
      "west": 102.0,
      "east": 103.5
    }
  },
  "requested_time_utc": "2026-08-28 12:00",
  "run_key": "2026-08-28T1200Z",
  "runtime": {
    "lead_days": 0,
    "format": "tif",
    "threads": 4,
    "overwrite": false
  },
  "source": {
    "git_commit": "...",
    "git_dirty": false,
    "model_sha256": "..."
  }
}
```

The manifest does **not** yet hash every downloaded IMERG or SMAP asset. It should therefore be treated as a reproducibility record for the requested experiment and local model/configuration state, not as a complete provenance ledger for all upstream Earth-observation inputs.

The manifest is written only after `regional-run.sh` completes successfully. A failed data download or LHASA run therefore does not leave a `run.json` that looks like a successful replay.

## Build an event timeline

For a known landslide or debris-flow event, replay several dates before the event rather than inspecting only the failure date. For example:

```text
T-30 days
T-14 days
T-7 days
T-3 days
T-1 day
T0 event
```

Run each time separately:

```bash
python examples/replay-region.py my-study-area "2026-07-29 12:00"
python examples/replay-region.py my-study-area "2026-08-14 12:00"
python examples/replay-region.py my-study-area "2026-08-21 12:00"
python examples/replay-region.py my-study-area "2026-08-25 12:00"
python examples/replay-region.py my-study-area "2026-08-27 12:00"
```

This creates a stable baseline for later comparison with additional signals such as rainfall accumulation, soil moisture, Sentinel-1 deformation, or InSAR velocity/acceleration.

## Data availability caveat

An explicit historical date does not guarantee that all required upstream products are still available through the URLs used by LHASA. A failed historical run may therefore indicate a data-access or product-version problem rather than a model problem. Preserve the failing date and error before changing code so those two classes of failure remain distinguishable.
