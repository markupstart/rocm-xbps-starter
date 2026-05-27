ROCm xbps-src templates for Void Linux (current ROCm ver: 7.2.3)

This repo gives you templates and scripts to build core ROCm packages in Void. This is a personal project to get ROCM working on Void on my system.  Your mileage may vary, but currently everything builds and has been tested successfully.

Included packages:
- rocm-cmake
- rocm-llvm
- rocm-device-libs
- rocm-comgr
- rocr-runtime
- rocminfo
- rocm-opencl
- hip-runtime-amd
- hipcc

ROCm 7.x note:
- rocm-device-libs source is fetched from ROCm llvm-project (amd/device-libs path),
  because the ROCm-Device-Libs repo does not publish rocm-7.2.3 tags.

Included scripts:
- scripts/print-checksums.sh
- scripts/build-rocm-core.sh
- scripts/validate-gfx1100.sh

Important:
- This is a starter, not final production packaging.
- You must set real checksums before building.
- Keep all package versions on the same ROCm release line.

Step-by-step (copy and paste)

1) Open a terminal in this repo

Run this first so every later command works from the same place:

```bash
cd /home/mark/Projects/rocm-xbps-starter
```

2) Clone Void packages (one time)

```bash
git clone https://github.com/void-linux/void-packages.git ~/void-packages
```

If you already cloned it before, skip this step.

3) Bootstrap xbps-src (one time)

```bash
cd ~/void-packages
./xbps-src binary-bootstrap
```

4) Return to this starter repo

```bash
cd /home/mark/Projects/rocm-xbps-starter
```

5) Fill all checksums automatically

This command fetches each upstream tarball hash and writes it into matching templates.

```bash
while IFS=': ' read -r pkg sum; do
  sed -i "s|^checksum=.*$|checksum=${sum}|" "srcpkgs/${pkg}/template"
done < <(./scripts/print-checksums.sh | awk '/: [0-9a-f]{64}$/ {print}')
```

6) Confirm there are no placeholders left

```bash
rg -n "REPLACE_WITH_REAL_CHECKSUM" srcpkgs || echo "OK: all checksums set"
```

7) Build core ROCm packages

```bash
XBPS_SRC_ROOT=~/void-packages ./scripts/build-rocm-core.sh
```

If you edit templates in this starter repo and want to refresh copies already
present in ~/void-packages/srcpkgs, run:

```bash
ROCM_SYNC_EXISTING=1 XBPS_SRC_ROOT=~/void-packages ./scripts/build-rocm-core.sh
```

The build script cleans per-package xbps build state before each package by
default to avoid stale state errors on reruns. Disable this behavior with:

```bash
ROCM_CLEAN_BEFORE_PKG=0 XBPS_SRC_ROOT=~/void-packages ./scripts/build-rocm-core.sh
```

Notes:
- Build order is handled automatically.
- Templates are copied into ~/void-packages/srcpkgs as real directories (not symlinks),
  because xbps-src treats symlinked srcpkgs as subpackages.
- The build script also updates ~/void-packages/common/shlibs with the local ROCm
  shared library ownership entries needed for xbps dependency generation,
  including ROCr, Comgr, HIP, and OpenCL libraries.
- If srcpkgs/<name> already exists in ~/void-packages, the script stops so you do not
  accidentally overwrite local work.

8) Install packages from your local binpkgs

```bash
sudo xbps-install -y \
  -R ~/void-packages/hostdir/binpkgs \
  rocm-cmake rocm-llvm rocm-device-libs rocm-comgr rocr-runtime rocminfo rocm-opencl hip-runtime-amd hipcc
```

No-sudo test install (alternate root)

If you cannot use sudo yet, install into a temporary root and test from there:

```bash
TESTROOT="$(mktemp -d)"
xbps-install -y -r "${TESTROOT}" \
  -R ~/void-packages/hostdir/binpkgs \
  -R https://repo-default.voidlinux.org/current \
  rocr-runtime rocm-llvm rocm-device-libs rocm-comgr rocminfo rocm-opencl hip-runtime-amd hipcc ocl-icd clinfo
```

Then run runtime checks against that root:

```bash
env \
  PATH="${TESTROOT}/usr/bin:${PATH}" \
  LD_LIBRARY_PATH="${TESTROOT}/usr/lib:${TESTROOT}/usr/lib64" \
  OCL_ICD_VENDORS="${TESTROOT}/etc/OpenCL/vendors" \
  ROCM_PATH="${TESTROOT}/usr" \
  HIP_PATH="${TESTROOT}/usr" \
  ./scripts/validate-gfx1100.sh core
```

Expected with current templates:
- rocminfo passes and reports gfx1100.
- clinfo passes and shows AMD Accelerated Parallel Processing + gfx1100.
- HIP smoke compiles and runs via hipcc when /dev/kfd and render nodes are accessible.

Fast HIP-only iteration

If you are debugging HIP and do not want to rebuild the whole stack, build only
the packages HIP now needs directly:

```bash
ROCM_SYNC_EXISTING=1 ROCM_ONLY_PKGS="rocm-comgr hip-runtime-amd" XBPS_SRC_ROOT=~/void-packages ./scripts/build-rocm-core.sh
```

If rocm-comgr is already built and installed, you can narrow it further:

```bash
ROCM_SYNC_EXISTING=1 ROCM_ONLY_PKGS="hip-runtime-amd" XBPS_SRC_ROOT=~/void-packages ./scripts/build-rocm-core.sh
```

9) Run validation

Core ROCm checks only:

```bash
./scripts/validate-gfx1100.sh core
```

App integration checks only (darktable + ollama):

```bash
./scripts/validate-gfx1100.sh apps
```

Everything:

```bash
./scripts/validate-gfx1100.sh all
```

10) Optional: build for only one GPU target

Default targets in hip-runtime-amd are gfx1100;gfx1101;gfx1102.

If you only want one target:

```bash
AMDGPU_TARGETS="gfx1100" XBPS_SRC_ROOT=~/void-packages ./scripts/build-rocm-core.sh
```

Where build outputs go

Built packages:
- ~/void-packages/hostdir/binpkgs

Build logs:
- /home/mark/Projects/rocm-xbps-starter/build-logs

Troubleshooting quick checks

Check device nodes:

```bash
ls -l /dev/kfd /dev/dri/renderD* 2>/dev/null
```

Check user groups:

```bash
groups
```

You usually want video and render groups for ROCm access.
