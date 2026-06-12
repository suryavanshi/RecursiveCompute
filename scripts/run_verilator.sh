#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-sim}"
TOP="${TOP:-rcif_top}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
BUILD_DIR="${BUILD_DIR:-build/verilator}"
VERILATOR="${VERILATOR:-verilator}"

RTL_SOURCES=(
  "${REPO_ROOT}/rtl/common/rcif_desc_pkg.sv"
  "${REPO_ROOT}/rtl/common/rcif_cmd_queue.sv"
  "${REPO_ROOT}/rtl/kv/rcif_kv_tlb.sv"
  "${REPO_ROOT}/rtl/kv/rcif_kv_mmu.sv"
  "${REPO_ROOT}/rtl/dma/rcif_gather_scatter.sv"
  "${REPO_ROOT}/rtl/dma/rcif_dma.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_scheduler_stub.sv"
  "${REPO_ROOT}/rtl/top/rcif_top.sv"
)

COMMON_FLAGS=(
  -Wall
  -Wno-DECLFILENAME
  --top-module "${TOP}"
  "-I${REPO_ROOT}/rtl/common"
)

if ! command -v "${VERILATOR}" >/dev/null 2>&1; then
  echo "error: Verilator not found. Install verilator or set VERILATOR=/path/to/verilator." >&2
  exit 127
fi

case "${MODE}" in
  lint)
    "${VERILATOR}" --lint-only "${COMMON_FLAGS[@]}" "${RTL_SOURCES[@]}"
    ;;
  build|verilate)
    mkdir -p "${BUILD_DIR}"
    "${VERILATOR}" --cc "${COMMON_FLAGS[@]}" "${RTL_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/verilator/rcif_top_smoke.cpp" \
      --Mdir "${BUILD_DIR}" \
      --build
    ;;
  sim)
    "${BASH_SOURCE[0]}" build
    "${BUILD_DIR}/V${TOP}"
    ;;
  *)
    echo "usage: $0 [lint|build|verilate|sim]" >&2
    exit 2
    ;;
esac
