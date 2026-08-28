#!/usr/bin/env bash
set -euo pipefail

# Run the existing LHASA model for a bounded region without changing model logic.
#
# Usage:
#   bash examples/regional-run.sh [region-name]
#
# A region name resolves to regions/<region-name>.conf. Region files use a
# simple KEY=VALUE format and may define only REGION_NAME, NORTH, SOUTH, WEST,
# and EAST. Existing environment variables override values from the region file.
#
# Required after loading configuration:
#   NORTH SOUTH WEST EAST
#
# Optional environment variables:
#   DATE             UTC timestamp accepted by lhasa.py, e.g. "2026-08-28 12:00"
#   LEAD_DAYS        Forecast lead days (default: 0, NRT only)
#   FORMAT           Output format accepted by lhasa.py (default: tif)
#   THREADS          XGBoost thread count (default: 4)
#   LHASA_DATA_PATH  Directory containing static/, imerg/, smap/, etc.
#                    (default: repository root)
#   OUTPUT_PATH      Output directory (default: LHASA_DATA_PATH)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

load_region() {
  local region="$1"
  local config_path
  local line key value
  declare -A config=()

  if [[ ! "${region}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Invalid region name: %s\n' "${region}" >&2
    return 2
  fi

  config_path="${REPO_ROOT}/regions/${region}.conf"
  if [[ ! -f "${config_path}" ]]; then
    printf 'Region configuration not found: %s\n' "${config_path}" >&2
    return 2
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue

    if [[ "${line}" != *=* ]]; then
      printf 'Invalid region configuration line: %s\n' "${line}" >&2
      return 2
    fi

    key="${line%%=*}"
    value="${line#*=}"

    case "${key}" in
      REGION_NAME|NORTH|SOUTH|WEST|EAST)
        config["${key}"]="${value}"
        ;;
      *)
        printf 'Unsupported region configuration key: %s\n' "${key}" >&2
        return 2
        ;;
    esac
  done < "${config_path}"

  REGION_NAME="${REGION_NAME:-${config[REGION_NAME]:-${region}}}"
  NORTH="${NORTH:-${config[NORTH]:-}}"
  SOUTH="${SOUTH:-${config[SOUTH]:-}}"
  WEST="${WEST:-${config[WEST]:-}}"
  EAST="${EAST:-${config[EAST]:-}}"
}

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [region-name]\n' "$0" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  load_region "$1"
fi

: "${NORTH:?Set NORTH or provide a region configuration}"
: "${SOUTH:?Set SOUTH or provide a region configuration}"
: "${WEST:?Set WEST or provide a region configuration}"
: "${EAST:?Set EAST or provide a region configuration}"

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

if [[ -n "${REGION_NAME:-}" ]]; then
  printf 'Region: %s\n' "${REGION_NAME}"
fi
printf 'Running LHASA for bbox W=%s S=%s E=%s N=%s\n' \
  "${WEST}" "${SOUTH}" "${EAST}" "${NORTH}"
printf 'Lead days: %s, format: %s, output: %s\n' \
  "${LEAD_DAYS}" "${FORMAT}" "${OUTPUT_PATH}"

exec "${args[@]}"
