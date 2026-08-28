# Regional LHASA quickstart

This guide runs the existing LHASA model for a bounded area of interest (AOI). It does not change the model, retrain it, or reinterpret its probabilities. The goal is to establish a small, repeatable baseline before adding regional data products or new hazard signals.

## 1. Complete the standard LHASA setup

Follow the repository README first to:

- create and activate the `lhasa` conda environment;
- configure Earthdata and PPS credentials;
- download and extract `static.zip`;
- create the runtime directories used by LHASA.

For an NRT-only regional run, the global forecast static data are required. Exposure and post-fire debris-flow datasets are only needed when those optional analyses are enabled.

## 2. Choose an AOI

LHASA accepts a WGS84 bounding box using north, south, west, and east coordinates. Keep the first test region deliberately small so downloads, interpolation, and output inspection are easier to debug.

Set the four required environment variables:

```bash
export NORTH=30.5
export SOUTH=29.5
export WEST=102.0
export EAST=103.5
```

The coordinates above are only an example. Replace them with the AOI you want to study.

## 3. Run an NRT-only baseline

Activate the environment and invoke the regional runner from the repository root:

```bash
conda activate lhasa
bash examples/regional-run.sh
```

The runner defaults to:

- `LEAD_DAYS=0` — only the near-real-time LHASA product;
- `FORMAT=tif` — GeoTIFF output for easy inspection in GIS software;
- `THREADS=4`;
- repository root as both the LHASA data path and output path.

The script delegates to the existing `lhasa.py` CLI and passes the AOI through `--north`, `--south`, `--west`, and `--east`.

## 4. Reproduce a specific run time

For historical or reproducibility work, provide the UTC date accepted by `lhasa.py`:

```bash
export DATE="2026-08-28 12:00"
bash examples/regional-run.sh
```

Using an explicit date is preferable when comparing outputs across code or data changes. Availability of the corresponding upstream IMERG and SMAP products still determines whether the run can complete.

## 5. Optional settings

You can override the defaults without editing the script:

```bash
export LEAD_DAYS=0
export FORMAT=tif
export THREADS=8
export LHASA_DATA_PATH="$PWD"
export OUTPUT_PATH="$PWD/output"

bash examples/regional-run.sh
```

If `OUTPUT_PATH` is separate from the input data directory, the runner creates the standard NRT and forecast output subdirectories before starting LHASA.

## 6. Inspect the result

With the default `FORMAT=tif`, inspect the generated raster under the NRT hazard output directory, typically:

```text
nrt/hazard/tif/
```

Open the GeoTIFF in QGIS or another GIS tool and verify:

1. the raster covers only the requested AOI;
2. the coordinate extent is correct;
3. nodata/masked regions look reasonable;
4. repeated runs for the same date and inputs produce the expected baseline output.

## Why start here?

Regional research becomes difficult to validate if model changes, new satellite inputs, and data-pipeline changes are introduced at the same time. This workflow intentionally keeps NASA's existing LHASA model untouched and establishes a reproducible reference run first.

A useful next step is to build historical replay around this baseline, then compare additional public Earth-observation signals—such as Sentinel-1 InSAR deformation—against known events.
