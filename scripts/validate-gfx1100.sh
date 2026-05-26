#!/usr/bin/env bash
set -euo pipefail

# Post-build runtime checks focused on RX 7900 XTX (gfx1100).
# Usage:
#   ./scripts/validate-gfx1100.sh
#   ./scripts/validate-gfx1100.sh core
#   ./scripts/validate-gfx1100.sh apps
#   ./scripts/validate-gfx1100.sh all

pass() { printf '[PASS] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; exit 1; }

MODE="${1:-all}"
if [[ "${MODE}" != "all" && "${MODE}" != "core" && "${MODE}" != "apps" ]]; then
  echo "Usage: $0 [all|core|apps]" >&2
  exit 2
fi

echo "==> ROCm/HIP baseline checks for gfx1100"

if id -nG "${USER}" | grep -Eq '(^| )video( |$)' && id -nG "${USER}" | grep -Eq '(^| )render( |$)'; then
  pass "user is in both video and render groups"
else
  warn "user is not in both video and render groups (or equivalent udev rules are needed)"
fi

if [[ ! -e /dev/kfd ]]; then
  fail "/dev/kfd is missing (ROCm kernel interface unavailable)"
else
  pass "/dev/kfd exists"
fi

if compgen -G '/dev/dri/renderD*' > /dev/null; then
  pass "DRM render node(s) present under /dev/dri"
else
  warn "No /dev/dri/renderD* nodes found"
fi

if command -v rocminfo >/dev/null 2>&1; then
  rocminfo_output="$(rocminfo 2>/dev/null || true)"
  if grep -qi 'gfx1100' <<<"${rocminfo_output}"; then
    pass "rocminfo reports gfx1100"
  else
    fail "rocminfo did not report gfx1100"
  fi
else
  warn "rocminfo not installed; skip runtime GPU probe"
fi

if command -v clinfo >/dev/null 2>&1; then
  clinfo_output="$(clinfo 2>/dev/null || true)"
  if grep -qi 'AMD Accelerated Parallel Processing' <<<"${clinfo_output}" && grep -qi 'gfx1100' <<<"${clinfo_output}"; then
    pass "clinfo reports AMD OpenCL platform and gfx1100 device"
  else
    fail "clinfo did not report the AMD OpenCL platform and gfx1100 device"
  fi
else
  warn "clinfo not installed; skip OpenCL runtime probe"
fi

if command -v hipcc >/dev/null 2>&1; then
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' EXIT

  cat > "${workdir}/hip_smoke.cpp" <<'EOF'
#include <hip/hip_runtime.h>
#include <iostream>

__global__ void k(int* x) { *x = 42; }

int main() {
  int *d = nullptr;
  if (hipMalloc(&d, sizeof(int)) != hipSuccess) return 2;
  hipLaunchKernelGGL(k, dim3(1), dim3(1), 0, 0, d);
  if (hipDeviceSynchronize() != hipSuccess) return 3;
  int out = 0;
  if (hipMemcpy(&out, d, sizeof(int), hipMemcpyDeviceToHost) != hipSuccess) return 4;
  hipFree(d);
  std::cout << out << "\n";
  return out == 42 ? 0 : 5;
}
EOF

  if hipcc --offload-arch=gfx1100 "${workdir}/hip_smoke.cpp" -o "${workdir}/hip_smoke"; then
    if "${workdir}/hip_smoke" >/dev/null; then
      pass "HIP compile+run smoke test passed for gfx1100"
    else
      fail "HIP smoke binary failed at runtime"
    fi
  else
    fail "HIP smoke compile failed"
  fi
else
  warn "hipcc not found; skip HIP compile smoke test"
fi

run_darktable_checks() {
  echo "==> Darktable OpenCL checks"
  if command -v darktable-cltest >/dev/null 2>&1; then
    if darktable-cltest 2>&1 | grep -Eiq 'AMD|gfx1100|Navi 31'; then
      pass "darktable-cltest detected AMD/OpenCL device"
    else
      warn "darktable-cltest ran, but AMD/OpenCL device was not clearly detected"
    fi
  elif command -v darktable >/dev/null 2>&1; then
    warn "darktable-cltest missing; run darktable and verify OpenCL is enabled in preferences"
  else
    warn "darktable is not installed; skipping"
  fi
}

run_ollama_checks() {
  echo "==> Ollama AMD checks"
  if command -v ollama >/dev/null 2>&1; then
    if pgrep -x ollama >/dev/null 2>&1; then
      if ollama ps 2>/dev/null | grep -Eiq 'amd|rocm|100% GPU'; then
        pass "ollama ps indicates GPU/ROCm usage"
      else
        warn "ollama is running but ollama ps did not clearly show GPU usage"
        warn "Tip: run a model and re-check: ollama run llama3.2"
      fi
    else
      warn "ollama daemon not running; start it and run a model, then re-run this check"
    fi
  else
    warn "ollama is not installed; skipping"
  fi
}

if [[ "${MODE}" == "all" || "${MODE}" == "apps" ]]; then
  run_darktable_checks
  run_ollama_checks
fi

echo "Validation finished."
