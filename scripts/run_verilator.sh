#!/usr/bin/env bash
set -euo pipefail

# Homebrew Perl on macOS and Debian containers do not always share the same
# generated UTF-8 locales. Verilator output and the smoke test are ASCII-only,
# so use the portable locale for identical local and Modal behavior.
export LC_ALL=C
export LANG=C

MODE="${1:-sim}"
TOP="${TOP:-rcif_top}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
BUILD_DIR="${BUILD_DIR:-build/verilator}"
VERILATOR="${VERILATOR:-verilator}"

RTL_SOURCES=(
  "${REPO_ROOT}/rtl/common/rcif_desc_pkg.sv"
  "${REPO_ROOT}/rtl/common/rcif_cmd_queue.sv"
  "${REPO_ROOT}/rtl/kv/rcif_kv_tlb.sv"
  "${REPO_ROOT}/rtl/kv/rcif_kv_page_walker.sv"
  "${REPO_ROOT}/rtl/kv/rcif_kv_fault_unit.sv"
  "${REPO_ROOT}/rtl/kv/rcif_kv_mmu.sv"
  "${REPO_ROOT}/rtl/dma/rcif_dma_desc_fetch.sv"
  "${REPO_ROOT}/rtl/dma/rcif_gather_scatter.sv"
  "${REPO_ROOT}/rtl/dma/rcif_dma.sv"
  "${REPO_ROOT}/rtl/attention/rcif_attention_mask_unit.sv"
  "${REPO_ROOT}/rtl/attention/rcif_kv_page_reader.sv"
  "${REPO_ROOT}/rtl/attention/rcif_qk_dot_array.sv"
  "${REPO_ROOT}/rtl/attention/rcif_online_softmax.sv"
  "${REPO_ROOT}/rtl/attention/rcif_v_reduce.sv"
  "${REPO_ROOT}/rtl/attention/rcif_attn_engine.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_weight_decode.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_mac_tile.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_scale_apply.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_activation_unit.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_accumulator_bank.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_norm_unit.sv"
  "${REPO_ROOT}/rtl/tensor/rcif_tensor_array.sv"
  "${REPO_ROOT}/rtl/collectives/rcif_collective_protocol_pkg.sv"
  "${REPO_ROOT}/rtl/collectives/rcif_credit_link.sv"
  "${REPO_ROOT}/rtl/collectives/rcif_topology_table.sv"
  "${REPO_ROOT}/rtl/collectives/rcif_collective_engine.sv"
  "${REPO_ROOT}/rtl/collectives/rcif_ring_collective_node.sv"
  "${REPO_ROOT}/rtl/collectives/rcif_collective_cluster.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_graph_decoder.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_dependency_scoreboard.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_qos_arbiter.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_replay_trace.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_completion_writer.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_token_scheduler.sv"
  "${REPO_ROOT}/rtl/scheduler/rcif_scheduler_stub.sv"
  "${REPO_ROOT}/rtl/verification/rcif_top_assertions.sv"
  "${REPO_ROOT}/rtl/top/rcif_top.sv"
)

COMMON_FLAGS=(
  -Wall
  -Wno-DECLFILENAME
  -Wno-UNUSEDPARAM
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
    "${VERILATOR}" --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
      --top-module rcif_token_scheduler "-I${REPO_ROOT}/rtl/common" "${RTL_SOURCES[@]}"
    ;;
  build|verilate)
    mkdir -p "${BUILD_DIR}"
    "${VERILATOR}" --cc "${COMMON_FLAGS[@]}" "${RTL_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/verilator/rcif_top_smoke.cpp" \
      -CFLAGS "-std=c++17" \
      --Mdir "${BUILD_DIR}" \
      --build
    ;;
  sim)
    "${BASH_SOURCE[0]}" build
    "${BUILD_DIR}/V${TOP}"
    ;;
  attention)
    ATTN_TOP=rcif_attn_engine
    ATTN_BUILD_DIR="${BUILD_DIR}_attention"
    ATTN_SOURCES=(
      "${REPO_ROOT}/rtl/attention/rcif_attention_mask_unit.sv"
      "${REPO_ROOT}/rtl/attention/rcif_kv_page_reader.sv"
      "${REPO_ROOT}/rtl/attention/rcif_qk_dot_array.sv"
      "${REPO_ROOT}/rtl/attention/rcif_online_softmax.sv"
      "${REPO_ROOT}/rtl/attention/rcif_v_reduce.sv"
      "${REPO_ROOT}/rtl/attention/rcif_attn_engine.sv"
    )
    mkdir -p "${ATTN_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME --top-module "${ATTN_TOP}" \
      "-I${REPO_ROOT}/rtl/common" "${ATTN_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/attention_directed/rcif_attn_engine_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${ATTN_BUILD_DIR}" --build
    "${ATTN_BUILD_DIR}/V${ATTN_TOP}"
    ;;
  tensor)
    TENSOR_TOP=rcif_tensor_array
    TENSOR_BUILD_DIR="${BUILD_DIR}_tensor"
    TENSOR_SOURCES=(
      "${REPO_ROOT}/rtl/tensor/rcif_weight_decode.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_mac_tile.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_scale_apply.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_activation_unit.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_accumulator_bank.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_norm_unit.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_tensor_array.sv"
    )
    mkdir -p "${TENSOR_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME --top-module "${TENSOR_TOP}" \
      "${TENSOR_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/tensor_formats/rcif_tensor_array_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${TENSOR_BUILD_DIR}" --build
    "${TENSOR_BUILD_DIR}/V${TENSOR_TOP}"
    ;;
  scheduler)
    SCHED_TOP=rcif_token_scheduler
    SCHED_BUILD_DIR="${BUILD_DIR}_scheduler"
    SCHED_SOURCES=(
      "${REPO_ROOT}/rtl/common/rcif_desc_pkg.sv"
      "${REPO_ROOT}/rtl/dma/rcif_dma_desc_fetch.sv"
      "${REPO_ROOT}/rtl/dma/rcif_gather_scatter.sv"
      "${REPO_ROOT}/rtl/dma/rcif_dma.sv"
      "${REPO_ROOT}/rtl/attention/rcif_attention_mask_unit.sv"
      "${REPO_ROOT}/rtl/attention/rcif_kv_page_reader.sv"
      "${REPO_ROOT}/rtl/attention/rcif_qk_dot_array.sv"
      "${REPO_ROOT}/rtl/attention/rcif_online_softmax.sv"
      "${REPO_ROOT}/rtl/attention/rcif_v_reduce.sv"
      "${REPO_ROOT}/rtl/attention/rcif_attn_engine.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_weight_decode.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_mac_tile.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_scale_apply.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_activation_unit.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_accumulator_bank.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_norm_unit.sv"
      "${REPO_ROOT}/rtl/tensor/rcif_tensor_array.sv"
      "${REPO_ROOT}/rtl/scheduler/rcif_graph_decoder.sv"
      "${REPO_ROOT}/rtl/scheduler/rcif_dependency_scoreboard.sv"
      "${REPO_ROOT}/rtl/scheduler/rcif_qos_arbiter.sv"
      "${REPO_ROOT}/rtl/scheduler/rcif_replay_trace.sv"
      "${REPO_ROOT}/rtl/scheduler/rcif_completion_writer.sv"
      "${REPO_ROOT}/rtl/scheduler/rcif_token_scheduler.sv"
    )
    mkdir -p "${SCHED_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM --top-module "${SCHED_TOP}" \
      "${SCHED_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/token_step/rcif_token_scheduler_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${SCHED_BUILD_DIR}" --build
    "${SCHED_BUILD_DIR}/V${SCHED_TOP}"
    ;;
  collectives)
    COLL_TOP=rcif_collective_engine
    COLL_BUILD_DIR="${BUILD_DIR}_collectives"
    COLL_SOURCES=(
      "${REPO_ROOT}/rtl/collectives/rcif_collective_protocol_pkg.sv"
      "${REPO_ROOT}/rtl/collectives/rcif_credit_link.sv"
      "${REPO_ROOT}/rtl/collectives/rcif_topology_table.sv"
      "${REPO_ROOT}/rtl/collectives/rcif_collective_engine.sv"
    )
    mkdir -p "${COLL_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
      --top-module "${COLL_TOP}" "${COLL_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/collectives/rcif_collective_engine_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${COLL_BUILD_DIR}" --build
    "${COLL_BUILD_DIR}/V${COLL_TOP}"
    CREDIT_TOP=rcif_credit_link
    CREDIT_BUILD_DIR="${COLL_BUILD_DIR}_credit"
    mkdir -p "${CREDIT_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
      --top-module "${CREDIT_TOP}" \
      "${REPO_ROOT}/rtl/collectives/rcif_credit_link.sv" \
      --exe "${REPO_ROOT}/dv/tests/collectives/rcif_credit_link_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${CREDIT_BUILD_DIR}" --build
    "${CREDIT_BUILD_DIR}/V${CREDIT_TOP}"
    CLUSTER_TOP=rcif_collective_cluster
    CLUSTER_BUILD_DIR="${COLL_BUILD_DIR}_cluster"
    CLUSTER_SOURCES=(
      "${REPO_ROOT}/rtl/collectives/rcif_collective_protocol_pkg.sv"
      "${REPO_ROOT}/rtl/collectives/rcif_credit_link.sv"
      "${REPO_ROOT}/rtl/collectives/rcif_ring_collective_node.sv"
      "${REPO_ROOT}/rtl/collectives/rcif_collective_cluster.sv"
    )
    mkdir -p "${CLUSTER_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
      --top-module "${CLUSTER_TOP}" "${CLUSTER_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/collectives/rcif_collective_cluster_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${CLUSTER_BUILD_DIR}" --build
    "${CLUSTER_BUILD_DIR}/V${CLUSTER_TOP}"
    ;;
  phase9)
    PHASE9_BUILD_DIR="${BUILD_DIR}_phase9"
    PHASE9_RANDOM_BUILD_DIR="${BUILD_DIR}_phase9_random"
    PHASE9_REPORT_DIR="${BUILD_DIR}_phase9_report"
    mkdir -p "${PHASE9_BUILD_DIR}" "${PHASE9_RANDOM_BUILD_DIR}" "${PHASE9_REPORT_DIR}"
    "${VERILATOR}" --cc "${COMMON_FLAGS[@]}" --assert --coverage "${RTL_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/verilator/rcif_top_smoke.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${PHASE9_BUILD_DIR}" --build
    "${PHASE9_BUILD_DIR}/V${TOP}" "${PHASE9_BUILD_DIR}/coverage.dat"
    "${VERILATOR}" --cc "${COMMON_FLAGS[@]}" --assert --coverage "${RTL_SOURCES[@]}" \
      --exe "${REPO_ROOT}/dv/tests/full_chip/rcif_full_chip_random_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${PHASE9_RANDOM_BUILD_DIR}" --build
    "${PHASE9_RANDOM_BUILD_DIR}/V${TOP}" "${PHASE9_RANDOM_BUILD_DIR}/coverage.dat"
    verilator_coverage --write-info "${PHASE9_REPORT_DIR}/coverage.info" \
      "${PHASE9_BUILD_DIR}/coverage.dat" "${PHASE9_RANDOM_BUILD_DIR}/coverage.dat"
    "${REPO_ROOT}/scripts/check_verilator_coverage.py" \
      --input "${PHASE9_REPORT_DIR}/coverage.info" --minimum 90
    ;;
  fpga-lint)
    FPGA_SOURCES=(
      "${RTL_SOURCES[@]}"
      "${REPO_ROOT}/fpga/rtl/rcif_ddr_axi_reader.sv"
      "${REPO_ROOT}/fpga/rtl/rcif_fpga_top.sv"
    )
    "${VERILATOR}" --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
      -Wno-UNUSEDSIGNAL --top-module rcif_fpga_top \
      "-I${REPO_ROOT}/rtl/common" "${FPGA_SOURCES[@]}"
    ;;
  fpga)
    "${BASH_SOURCE[0]}" fpga-lint
    FPGA_DDR_BUILD_DIR="${BUILD_DIR}_fpga_ddr"
    mkdir -p "${FPGA_DDR_BUILD_DIR}"
    "${VERILATOR}" --cc -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
      --top-module rcif_ddr_axi_reader \
      "${REPO_ROOT}/fpga/rtl/rcif_ddr_axi_reader.sv" \
      --exe "${REPO_ROOT}/dv/tests/phase10/rcif_ddr_axi_reader_test.cpp" \
      -CFLAGS "-std=c++17" --Mdir "${FPGA_DDR_BUILD_DIR}" --build
    "${FPGA_DDR_BUILD_DIR}/Vrcif_ddr_axi_reader"
    ;;
  *)
    echo "usage: $0 [lint|build|verilate|sim|attention|tensor|scheduler|collectives|phase9|fpga-lint|fpga]" >&2
    exit 2
    ;;
esac
