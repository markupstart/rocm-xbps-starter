#!/usr/bin/env bash
set -euo pipefail

# Print sha256 checksums for current template distfiles so you can paste them
# into srcpkgs/*/template in place of REPLACE_WITH_REAL_CHECKSUM.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd sha256sum

mapfile -t templates < <(find "${ROOT}/srcpkgs" -mindepth 2 -maxdepth 2 -type f -name template | sort)

if [[ ${#templates[@]} -eq 0 ]]; then
  echo "ERROR: no template files found under ${ROOT}/srcpkgs" >&2
  exit 1
fi

echo "Package checksums:"
had_error=0
for t in "${templates[@]}"; do
  pkg="$(basename "$(dirname "${t}")")"
  version="$(grep -E '^version=' "${t}" | head -n1 | cut -d'=' -f2- | tr -d '"')"
  distfile_raw="$(grep -E '^distfiles=' "${t}" | head -n1 | cut -d'=' -f2- | tr -d '"')"
  distfile="${distfile_raw//\$\{version\}/${version}}"
  distfile="${distfile//\$version/${version}}"

  if [[ -z "${distfile}" ]]; then
    echo "${pkg}: ERROR (missing distfiles=)"
    continue
  fi

  if sum="$(curl -LfsS "${distfile}" | sha256sum | awk '{print $1}')"; then
    echo "${pkg}: ${sum}"
  else
    echo "${pkg}: ERROR (failed to fetch ${distfile})" >&2
    had_error=1
  fi
done

if [[ ${had_error} -ne 0 ]]; then
  exit 1
fi
