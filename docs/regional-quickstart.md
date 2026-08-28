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

For a reusable AOI, create a named configuration under `regions/`. Region files use a deliberately small `KEY=VALUE` format and may contain only `REGION_NAME`, `NORTH`, `SOUTH`, `WEST`, and `EAST`.

An example is included at `regions/example-mountain-region.conf`:

```text
REGION_NAME=example-mountain-region
NORTH=30.5
SOUTH=29.5
WEST=102.0
EAST=103.5
```

The coordinates are only an example. Copy the file to a meaningful region name and replace them with the AOI you want to study.

You can still run without a named configuration by exporting the four coordinates directly:

```bash
export NORTH=30.5
export SOUTH=29.5
export WEST=102.0
export EAST=103.5
```

## 3. Run an NRT-only baseline

Activate the environment and invoke the regional runner with a region name from the repository root:

```bash
conda activate lhasa
bash examples/regional-run.sh example-mountain-region
```

The region name resolves to `regions/example-mountain-region.conf`. The runner parses only the supported configuration keys; it does not execute the file as shell code.

The runner defaults to:

- `LEAD_DAYS=0` — only the near-real-time LHASA product;
- `FORMAT=tif` — GeoTIFF output for easy inspection in GIS software;
- `THREADS=4`;
- `OVERWRITE=0` — existing outputs are preserved by default;
- repository root as both the LHASA data path and output path.

The script delegates to the existing `lhasa.py` CLI and passes the AOI through `--north`, `--south`, `--west`, and `--east`.

To use only environment variables, omit the region name:

```bash
bash examples/regional-run.sh
```

## 4. Override a named region temporarily

Environment variables take precedence over values in the named region. This is useful for expanding or shrinking an AOI without editing the shared configuration:

```bash
export NORTH=30.7
bash examples/regional-run.sh example-mountain-region
```

The other bounds still come from the region configuration.

## 5. Reproduce a specific run time

For historical or reproducibility work, provide the UTC date accepted by `lhasa.py`:

```bash
export DATE="2026-08-28 12:00"
bash examples/regional-run.sh example-mountain-region
```

Using an explicit date is preferable when comparing outputs across code or data changes. Availability of the corresponding upstream IMERG and SMAP products still determines whether the run can complete.

LHASA refuses to replace an existing hazard file by default. If you intentionally want to rerun the same region and date into the same output path, opt in to overwrite explicitly:

```bash
export DATE="2026-08-28 12:00"
export OVERWRITE=1
bash examples/regional-run.sh example-mountain-region
```

Leave `OVERWRITE` unset (or set it to `0`) when you want existing outputs to remain protected.

## 6. Optional settings

You can override the runtime defaults without editing the region configuration:

```bash
export LEAD_DAYS=0
export FORMAT=tif
export THREADS=8
export OVERWRITE=0
export LHASA_DATA_PATH="$PWD"
export OUTPUT_PATH="$PWD/output"

bash examples/regional-run.sh example-mountain-region
```

If `OUTPUT_PATH` is separate from the input data directory, the runner creates the standard NRT and forecast output subdirectories before starting LHASA.

## 7. Add another named region

Create another file under `regions/` using a filesystem-safe name, for example:

```text
regions/my-study-area.conf
```

Then define its WGS84 bounding box:

```text
REGION_NAME=my-study-area
NORTH=...
SOUTH=...
WEST=...
EAST=...
```

Run it by name:

```bash
bash examples/regional-run.sh my-study-area
```

Keeping AOIs in version control makes historical replay and comparisons easier to reproduce later.

## 8. Inspect the result

With the default `FORMAT=tif`, inspect the generated raster under the NRT hazard output directory, typically:

```text
nrt/hazard/tif/
```

Open the GeoTIFF in QGIS or another GIS tool and verify:

1. the raster covers only the requested AOI;
2. the coordinate extent is correct;
3. nodata/masked regions look reasonable;
4. repeated runs for the same region, date, and inputs produce the expected baseline output.

## 9. Build a historical replay timeline

Once a named region runs successfully, use the dedicated replay runner to isolate historical outputs by region and UTC time:

```bash
python examples/replay-region.py \
  example-mountain-region \
  "2026-08-28 12:00"
```

The replay runner writes into `runs/<region>/<time>/` and creates a `run.json` manifest after a successful LHASA run. See [`historical-replay.md`](historical-replay.md) for the output layout, provenance fields, and an example T-30/T-14/T-7/T-3/T-1 event timeline.

## Why start here?

Regional research becomes difficult to validate if model changes, new satellite inputs, and data-pipeline changes are introduced at the same time. This workflow intentionally keeps NASA's existing LHASA model untouched and establishes a reproducible reference run first.

Historical replay provides the next evidence layer: it lets known events be studied across several pre-event dates before additional public Earth-observation signals—such as Sentinel-1 InSAR deformation—are introduced.
