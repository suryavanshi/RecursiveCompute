#!/usr/bin/env python3
"""Enforce the bounded Phase 9 Verilator line-coverage threshold."""

from __future__ import annotations

import argparse
from pathlib import Path


def line_coverage(path: Path) -> tuple[int, int]:
    found = 0
    hit = 0
    da_found = 0
    da_hit = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("LF:"):
            found += int(line[3:])
        elif line.startswith("LH:"):
            hit += int(line[3:])
        elif line.startswith("DA:"):
            # Verilator's LCOV writer emits per-line DA records but does not
            # add the optional LF/LH summary records.
            da_found += 1
            da_hit += int(line.split(",", 1)[1]) > 0
    if found == 0:
        found, hit = da_found, da_hit
    if found == 0:
        raise ValueError(f"{path} contains no line-coverage records")
    return hit, found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--minimum", required=True, type=float)
    args = parser.parse_args()
    hit, found = line_coverage(args.input)
    percent = 100.0 * hit / found
    print(f"Verilator line coverage: {hit}/{found} ({percent:.2f}%), target {args.minimum:.2f}%")
    if percent < args.minimum:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
