#!/usr/bin/env bash
set -euo pipefail

# Run the existing LHASA model for a bounded region without changing model logic.
#
# Required environment variables:
#   NORTH SOUTH WEST EAST
#
# Optional environment variables:
#   DATE          UTC timestamp accepted by lhasa.py, e.g. "2026-08-28 12:00"
#   LEAD_DAYS     Forecast lead days (default: 0, NRT only)
#   FORMAT        Output format accepted by lhasa.py (default: tif)
#   THREADS       XGBoost thread count (default: 4)
#   LHASA_DATA_PATH  Directory containing static/, imerg/, smap/, etc.
#                    (default: repository root)
#   OUTPUT_PATH   Output directory (default: LHASA_DATA_PATH)

: "${NORTH:?Set NORTH to the maximum WGS84 latitude}"
: "${SOUTH:?Set SOUTH to the minimum WGS84 latitude}"
: "${WEST:?Set WEST to the minimum WGS84 longitude}"
: "${EAST:?Set EAST to the maximum WGS84 longitude}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LEAD_DAYS="${LEAD_DAYS:-0}"
FORMAT="${FORMAT:-tif}"
THREADS="${THREADS:-4}"
LHASA_DATA_PATH="${LHASA_DATA_PATH:-${REPO_ROOT}}"
OUTPUT_PATH="${OUTPUT_PATH:-${LHASA_DATA_PATH}}"

mkdir -p \
  "${OUTPUT_PATH}/nrt/hazard/tif" \
  "${OUTPUT_PATH}/nrt/exposure/csv" \
  "${OUTPUT_PATH}/fcast/hazard/tif" \
  "${OUTPUT_PATH}/fcast/exposure/csv"

args=(
  python "${REPO_ROOT}/lhasa.py"
  --path "${LHASA_DATA_PATH}"
  --output_path "${OUTPUT_PATH}"
  --north "${NORTH}"
  --south "${SOUTH}"
  --west "${WEST}"
  --east "${EAST}"
  --lead "${LEAD_DAYS}"
  --format "${FORMAT}"
  --threads "${THREADS}"
)

if [[ -n "${DATE:-}" ]]; then
  args+=(--date "${DATE}")
fi

printf 'Running LHASA for bbox W=%s S=%s E=%s N=%s\n' \
  "${WEST}" "${SOUTH}" "${EAST}" "${NORTH}"
printf 'Lead days: %s, format: %s, output: %s\n' \
  "${LEAD_DAYS}" "${FORMAT}" "${OUTPUT_PATH}"

exec "${args[@]}"
