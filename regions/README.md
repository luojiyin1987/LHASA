# Regional configurations

Each `*.conf` file defines a reusable WGS84 bounding box for `examples/regional-run.sh`.

Supported keys are:

- `REGION_NAME`
- `NORTH`
- `SOUTH`
- `WEST`
- `EAST`

The runner parses these files as data rather than sourcing them as shell code. Environment variables override values loaded from a named region.

Run a region by its file stem:

```bash
bash examples/regional-run.sh example-mountain-region
```
