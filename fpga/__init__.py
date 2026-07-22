"""Reduced RCIF FPGA prototype and deterministic emulation backend."""

from .prototype import (
    FpgaPrototypeDevice,
    Phase10Report,
    build_toy_graph,
    run_agentic_trace,
)

__all__ = [
    "FpgaPrototypeDevice",
    "Phase10Report",
    "build_toy_graph",
    "run_agentic_trace",
]
