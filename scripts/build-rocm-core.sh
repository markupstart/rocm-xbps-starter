#!/usr/bin/env bash
set -euo pipefail

# Dependency-ordered build script for core ROCm components on Void with xbps-src.
# Usage:
#   XBPS_SRC_ROOT=$HOME/void-packages ./scripts/build-rocm-core.sh
# Optional:
#   ROCM_STUB_ROOT=/path/to/rocm-xbps-starter ./scripts/build-rocm-core.sh
#   ROCM_SYNC_EXISTING=1 XBPS_SRC_ROOT=$HOME/void-packages ./scripts/build-rocm-core.sh
#   ROCM_CLEAN_BEFORE_PKG=0 XBPS_SRC_ROOT=$HOME/void-packages ./scripts/build-rocm-core.sh
#   ROCM_ONLY_PKGS="hip-runtime-amd" XBPS_SRC_ROOT=$HOME/void-packages ./scripts/build-rocm-core.sh

XBPS_SRC_ROOT="${XBPS_SRC_ROOT:-$HOME/void-packages}"
ROCM_STUB_ROOT="${ROCM_STUB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="${ROCM_STUB_ROOT}/build-logs"
ROCM_SYNC_EXISTING="${ROCM_SYNC_EXISTING:-0}"
ROCM_CLEAN_BEFORE_PKG="${ROCM_CLEAN_BEFORE_PKG:-1}"
ROCM_ONLY_PKGS="${ROCM_ONLY_PKGS:-}"

PKGS=(
  rocm-cmake
  rocm-llvm
  rocm-device-libs
  rocm-comgr
  rocr-runtime
  rocminfo
  rocm-opencl
  hip-runtime-amd
  hipcc
)

if [[ -n "${ROCM_ONLY_PKGS}" ]]; then
  read -r -a PKGS <<< "${ROCM_ONLY_PKGS}"
fi

if [[ ! -d "${XBPS_SRC_ROOT}" ]]; then
  echo "ERROR: XBPS_SRC_ROOT does not exist: ${XBPS_SRC_ROOT}" >&2
  exit 1
fi

if [[ ! -x "${XBPS_SRC_ROOT}/xbps-src" ]]; then
  echo "ERROR: xbps-src not found or not executable at ${XBPS_SRC_ROOT}/xbps-src" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

cd "${XBPS_SRC_ROOT}"

ensure_shlib_entry() {
  local soname="$1"
  local pkgver="$2"
  local shlibs_file="${XBPS_SRC_ROOT}/common/shlibs"

  if grep -q "^${soname} " "${shlibs_file}"; then
    sed -i "s|^${soname} .*|${soname} ${pkgver}|" "${shlibs_file}"
  else
    printf '%s %s\n' "${soname}" "${pkgver}" >> "${shlibs_file}"
  fi
}

echo "==> Ensuring local ROCm shlib mappings exist in common/shlibs"
ensure_shlib_entry "libhsa-runtime64.so.1" "rocr-runtime-7.2.3_1"
ensure_shlib_entry "libamd_comgr.so.3" "rocm-comgr-7.2.3_1"
ensure_shlib_entry "libamdhip64.so.7" "hip-runtime-amd-7.2.3_1"
ensure_shlib_entry "libamdocl64.so.2" "rocm-opencl-7.2.3_1"
ensure_shlib_entry "libhiprtc-builtins.so.7" "hip-runtime-amd-7.2.3_1"
ensure_shlib_entry "libhiprtc.so.7" "hip-runtime-amd-7.2.3_1"
ensure_shlib_entry "libcltrace.so" "rocm-opencl-7.2.3_1"

echo "==> Ensuring core templates are available under srcpkgs/"
for pkg in "${PKGS[@]}"; do
  src="${ROCM_STUB_ROOT}/srcpkgs/${pkg}"
  dst="${XBPS_SRC_ROOT}/srcpkgs/${pkg}"

  if [[ ! -d "${src}" ]]; then
    echo "ERROR: Missing stub template dir: ${src}" >&2
    exit 1
  fi

  if [[ -L "${dst}" ]]; then
    src_real="$(readlink -f "${src}")"
    dst_real="$(readlink -f "${dst}")"

    if [[ "${src_real}" == "${dst_real}" ]]; then
      rm -f "${dst}"
      cp -a "${src}" "${dst}"
      echo "    ${pkg}: replaced starter symlink with real directory copy"
    else
      echo "ERROR: ${dst} points to ${dst_real}, expected ${src_real}" >&2
      echo "       Remove or fix the existing link/directory, then rerun." >&2
      exit 1
    fi
  elif [[ -d "${dst}" ]]; then
    if [[ "${ROCM_SYNC_EXISTING}" == "1" ]]; then
      rm -rf "${dst}"
      cp -a "${src}" "${dst}"
      echo "    ${pkg}: refreshed existing directory from starter template"
    else
      echo "ERROR: Existing directory blocks copy: ${dst}" >&2
      echo "       Re-run with ROCM_SYNC_EXISTING=1 to refresh from starter templates." >&2
      exit 1
    fi
  else
    cp -a "${src}" "${dst}"
    echo "    ${pkg}: copied starter template to ${dst}"
  fi
done

echo "==> Running binary bootstrap (safe if already done)"
./xbps-src binary-bootstrap

echo "==> Building core ROCm packages in dependency order"
for pkg in "${PKGS[@]}"; do
  log_file="${LOG_DIR}/${pkg}.log"
  echo "---- ${pkg} ----"
  if [[ "${ROCM_CLEAN_BEFORE_PKG}" == "1" ]]; then
    ./xbps-src clean "${pkg}" >/dev/null 2>&1 || true
  fi
  if ./xbps-src pkg "${pkg}" 2>&1 | tee "${log_file}"; then
    echo "OK: ${pkg}"
  else
    echo "FAIL: ${pkg} (see ${log_file})" >&2
    exit 1
  fi
done

echo "==> Indexing local binary repository"
if compgen -G "${XBPS_SRC_ROOT}/hostdir/binpkgs/*.xbps" > /dev/null; then
  xbps-rindex -a "${XBPS_SRC_ROOT}"/hostdir/binpkgs/*.xbps
  echo "Repository indexed in ${XBPS_SRC_ROOT}/hostdir/binpkgs"
else
  echo "WARNING: No .xbps artifacts found under hostdir/binpkgs"
fi

echo "Done. Build logs are in ${LOG_DIR}"
