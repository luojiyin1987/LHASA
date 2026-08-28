#!/usr/bin/env bash
set -euo pipefail

# Replay a named LHASA region at an explicit historical UTC time.
#
# Usage:
#   bash examples/replay-region.sh <region-name> "YYYY-MM-DD HH:MM"
#
# Each replay writes to:
#   runs/<region-name>/<YYYY-MM-DDTHHMMZ>/
#
# Optional environment variables:
#   RUNS_ROOT        Root directory for replay outputs (default: <repo>/runs)
#   FORMAT           Output format accepted by regional-run.sh (default: tif)
#   THREADS          XGBoost thread count (default: 4)
#   OVERWRITE        Set to 1 to replace existing LHASA output files (default: 0)
#   LHASA_DATA_PATH  Directory containing static/, imerg/, smap/, etc.

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <region-name> "YYYY-MM-DD HH:MM"\n' "$0" >&2
  exit 2
fi

REGION="$1"
DATE_INPUT="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ ! "${REGION}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'Invalid region name: %s\n' "${REGION}" >&2
  exit 2
fi

REGION_CONFIG_PATH="${REPO_ROOT}/regions/${REGION}.conf"
if [[ ! -f "${REGION_CONFIG_PATH}" ]]; then
  printf 'Region configuration not found: %s\n' "${REGION_CONFIG_PATH}" >&2
  exit 2
fi

declare -A region_config=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%$'\r'}"
  [[ -z "${line}" || "${line}" == \#* ]] && continue

  if [[ "${line}" != *=* ]]; then
    printf 'Invalid region configuration line: %s\n' "${line}" >&2
    exit 2
  fi

  key="${line%%=*}"
  value="${line#*=}"
  case "${key}" in
    REGION_NAME|NORTH|SOUTH|WEST|EAST)
      region_config["${key}"]="${value}"
      ;;
    *)
      printf 'Unsupported region configuration key: %s\n' "${key}" >&2
      exit 2
      ;;
  esac
done < "${REGION_CONFIG_PATH}"

NORTH="${region_config[NORTH]:-}"
SOUTH="${region_config[SOUTH]:-}"
WEST="${region_config[WEST]:-}"
EAST="${region_config[EAST]:-}"
REGION_DISPLAY_NAME="${region_config[REGION_NAME]:-${REGION}}"

: "${NORTH:?Region configuration must define NORTH}"
: "${SOUTH:?Region configuration must define SOUTH}"
: "${WEST:?Region configuration must define WEST}"
: "${EAST:?Region configuration must define EAST}"

DATE_VALUES="$(python - "${DATE_INPUT}" <<'PY'
from datetime import datetime
import sys

try:
    value = datetime.strptime(sys.argv[1], "%Y-%m-%d %H:%M")
except ValueError as exc:
    raise SystemExit(
        f'Invalid replay date {sys.argv[1]!r}; expected "YYYY-MM-DD HH:MM": {exc}'
    )

print(value.strftime("%Y-%m-%d %H:%M") + "\t" + value.strftime("%Y-%m-%dT%H%MZ"))
PY
)"
IFS=$'\t' read -r NORMALIZED_DATE RUN_KEY <<< "${DATE_VALUES}"

RUNS_ROOT="${RUNS_ROOT:-${REPO_ROOT}/runs}"
RUN_DIR="${RUNS_ROOT}/${REGION}/${RUN_KEY}"
FORMAT_VALUE="${FORMAT:-tif}"
THREADS_VALUE="${THREADS:-4}"
OVERWRITE_VALUE="${OVERWRITE:-0}"
LHASA_DATA_PATH_VALUE="${LHASA_DATA_PATH:-${REPO_ROOT}}"

mkdir -p "${RUN_DIR}"

printf 'Historical replay: %s at %s UTC\n' "${REGION_DISPLAY_NAME}" "${NORMALIZED_DATE}"
printf 'Replay output: %s\n' "${RUN_DIR}"

(
  # A historical replay is tied to the checked-in named region. Clear any
  # coordinate overrides inherited from the caller before delegating.
  unset REGION_NAME NORTH SOUTH WEST EAST DATE OUTPUT_PATH
  export DATE="${NORMALIZED_DATE}"
  export OUTPUT_PATH="${RUN_DIR}"
  export LEAD_DAYS=0
  export FORMAT="${FORMAT_VALUE}"
  export THREADS="${THREADS_VALUE}"
  export OVERWRITE="${OVERWRITE_VALUE}"
  export LHASA_DATA_PATH="${LHASA_DATA_PATH_VALUE}"

  bash "${SCRIPT_DIR}/regional-run.sh" "${REGION}"
)

GIT_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null || true)" ]]; then
  GIT_DIRTY=1
else
  GIT_DIRTY=0
fi

python - \
  "${RUN_DIR}/run.json" \
  "${REGION}" \
  "${REGION_DISPLAY_NAME}" \
  "${REGION_CONFIG_PATH}" \
  "${NORTH}" "${SOUTH}" "${WEST}" "${EAST}" \
  "${NORMALIZED_DATE}" "${RUN_KEY}" \
  "${FORMAT_VALUE}" "${THREADS_VALUE}" "${OVERWRITE_VALUE}" \
  "${LHASA_DATA_PATH_VALUE}" "${RUN_DIR}" \
  "${GIT_COMMIT}" "${GIT_DIRTY}" "${REPO_ROOT}/model.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

(
    manifest_path,
    region,
    region_name,
    region_config_path,
    north,
    south,
    west,
    east,
    requested_time,
    run_key,
    output_format,
    threads,
    overwrite,
    data_path,
    output_path,
    git_commit,
    git_dirty,
    model_path,
) = sys.argv[1:]


def sha256(path: str):
    file_path = Path(path)
    if not file_path.is_file():
        return None
    digest = hashlib.sha256()
    with file_path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

manifest = {
    "schema_version": 1,
    "region": {
        "id": region,
        "name": region_name,
        "config": str(Path(region_config_path).resolve()),
        "config_sha256": sha256(region_config_path),
        "bbox": {
            "north": float(north),
            "south": float(south),
            "west": float(west),
            "east": float(east),
        },
    },
    "requested_time_utc": requested_time,
    "run_key": run_key,
    "runtime": {
        "lead_days": 0,
        "format": output_format,
        "threads": int(threads),
        "overwrite": overwrite == "1",
    },
    "source": {
        "git_commit": git_commit or None,
        "git_dirty": git_dirty == "1",
        "model_sha256": sha256(model_path),
    },
    "paths": {
        "data": str(Path(data_path).resolve()),
        "output": str(Path(output_path).resolve()),
    },
}

with Path(manifest_path).open("w", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY

printf 'Replay manifest: %s\n' "${RUN_DIR}/run.json"
