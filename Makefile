PYTHON ?= python3
VERILATOR ?= verilator
MODAL ?= /Users/kb/Library/Python/3.9/bin/modal

.PHONY: help test lint verilate sim regress modal-test modal-lint modal-verilate modal-sim modal-regress local-test local-lint local-verilate local-sim local-regress clean

help:
	@echo "Targets:"
	@echo "  test           Run Python unit tests on Modal CPU"
	@echo "  lint           Run Verilator lint on Modal CPU"
	@echo "  verilate       Build the Verilator smoke binary on Modal CPU"
	@echo "  sim            Run the Verilator smoke simulation on Modal CPU"
	@echo "  regress        Run Python tests plus Verilator smoke on Modal CPU"
	@echo "  local-*        Run the same target locally when tools are installed"
	@echo "  clean          Remove local build artifacts"

test: modal-test

lint: modal-lint

verilate: modal-verilate

sim: modal-sim

regress: modal-regress

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

local-test:
	$(PYTHON) -m unittest discover -s dv/tests -v

local-lint:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh lint

local-verilate:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh build

local-sim:
	VERILATOR=$(VERILATOR) scripts/run_verilator.sh sim

local-regress: local-test local-sim

clean:
	rm -rf build
