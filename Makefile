PYTHON ?= python3
VERILATOR ?= verilator
MODAL ?= /Users/kb/Library/Python/3.9/bin/modal

.PHONY: help test lint verilate sim regress phase9 phase10 modal-test modal-lint modal-verilate modal-sim modal-regress modal-phase9 modal-phase10 local-test local-lint local-verilate local-sim local-collectives local-phase9 local-phase10 local-fpga local-fpga-lint local-regress clean

help:
	@echo "Targets:"
	@echo "  test           Run Python unit tests on Modal CPU"
	@echo "  lint           Run Verilator lint on Modal CPU"
	@echo "  verilate       Build the Verilator smoke binary on Modal CPU"
	@echo "  sim            Run the Verilator smoke simulation on Modal CPU"
	@echo "  regress        Run Python tests plus Verilator smoke on Modal CPU"
	@echo "  phase9         Run assertion, random, invariant, and coverage signoff suite"
	@echo "  phase10        Run FPGA-shell lint and end-to-end emulation acceptance suite"
	@echo "  local-*        Run the same target locally when tools are installed"
	@echo "  local-collectives  Run the Phase 7 collective and credit-link simulations"
	@echo "  clean          Remove local build artifacts"

test: modal-test

lint: modal-lint

verilate: modal-verilate

sim: modal-sim

regress: modal-regress

phase9: modal-phase9

phase10: modal-phase10

modal-test:
	$(MODAL) run infra/modal/run_verilator.py --target local-test

modal-lint:
	$(MODAL) run infra/modal/run_verilator.py --target local-lint

modal-verilate:
	$(MODAL) run infra/modal/run_verilator.py --target local-verilate

modal-sim:
	$(MODAL) run infra/modal/run_verilator.py --target local-sim

modal-regress:
	$(MODAL) run infra/modal/run_verilator.py --target local-regress

modal-phase9:
	$(MODAL) run infra/modal/run_verilator.py --target local-phase9

modal-phase10:
	$(MODAL) run infra/modal/run_verilator.py --target local-phase10

local-test:
	$(PYTHON) -m unittest discover -s dv/tests -v

local-lint:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh lint

local-verilate:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh build

local-sim:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh sim

local-collectives:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh collectives

local-phase9: local-test
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh phase9

local-fpga-lint:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh fpga-lint

local-fpga:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh fpga

local-phase10: local-test local-fpga

local-regress: local-test local-sim
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh attention
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh tensor
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh scheduler
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh collectives

clean:
	rm -rf build
