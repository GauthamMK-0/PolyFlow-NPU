# ==============================================================================
# PolyFlow-NPU: Top-Level Master Automation Makefile
# Unified Control for Cadence Digital Flow (Xcelium / Genus) & Open-Source Simulators
# ==============================================================================

# Architectural model variant to target: pipelined (default) or non_pipelined
MODEL_VARIANT ?= pipelined

# Simulation mode: 1 (SimVision GUI) or 0 (Headless batch mode)
GUI           ?= 0

# Testcase selector: ALL (default) or specific sub-test (e.g. ws, os, is, split, coexec)
TEST          ?= ALL

.PHONY: help all lint lint-verilator lint-cadence \
        run-model1 run-model2 run-model3 run-all \
        synth-model1 synth-model2 synth-model3 synth-all \
        sim-verilator sim-iverilog sim-xrun clean

# Default target
all: help

help:
	@echo "=================================================================="
	@echo " PolyFlow-NPU Master Automation Makefile"
	@echo " Active Variant: $(MODEL_VARIANT) | GUI: $(GUI) | Test: $(TEST)"
	@echo "=================================================================="
	@echo " Cadence Xcelium Simulation Targets:"
	@echo "   make run-model1 [GUI=0/1] [TEST=...]  - Run Model 1: Dataflow Switching"
	@echo "   make run-model2 [GUI=0/1] [TEST=...]  - Run Model 2: Spatial Fission"
	@echo "   make run-model3 [GUI=0/1] [TEST=...]  - Run Model 3: Heterogeneous Fission"
	@echo "   make run-all    [GUI=0/1] [TEST=...]  - Run all 3 models sequentially"
	@echo ""
	@echo " Cadence Genus Logic Synthesis Targets:"
	@echo "   make synth-model1                     - Synthesize Model 1 netlist & reports"
	@echo "   make synth-model2                     - Synthesize Model 2 netlist & reports"
	@echo "   make synth-model3                     - Synthesize Model 3 netlist & reports"
	@echo "   make synth-all                        - Synthesize all 3 models sequentially"
	@echo ""
	@echo " Multi-Model Linting & Verification Targets:"
	@echo "   make lint                             - Run strict Verilator linting across all models"
	@echo "   make lint-verilator                   - Run strict Verilator linting across all models"
	@echo "   make lint-cadence                     - Run Cadence HAL linting across all models"
	@echo ""
	@echo " Automated Batch Simulation Suite:"
	@echo "   make sim-verilator [TEST=...]         - Run all models with Verilator"
	@echo "   make sim-iverilog  [TEST=...]         - Run all models with Icarus Verilog"
	@echo "   make sim-xrun      [TEST=...]         - Run all models with Cadence Xcelium"
	@echo ""
	@echo " Maintenance:"
	@echo "   make clean                            - Clean build artifacts across all models"
	@echo "=================================================================="

# --- Cadence Xcelium Simulation Targets ---
run-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching run GUI=$(GUI) TEST=$(TEST)

run-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission run GUI=$(GUI) TEST=$(TEST)

run-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission run GUI=$(GUI) TEST=$(TEST)

run-all: run-model1 run-model2 run-model3

# --- Optional GUI Shortcuts (SimVision) ---
gui-model1:
	@$(MAKE) run-model1 GUI=1 TEST=$(TEST)

gui-model2:
	@$(MAKE) run-model2 GUI=1 TEST=$(TEST)

gui-model3:
	@$(MAKE) run-model3 GUI=1 TEST=$(TEST)

# --- Cadence Genus Synthesis Targets ---
synth-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching synth

synth-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission synth

synth-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission synth

synth-all: synth-model1 synth-model2 synth-model3

# --- Linting Targets ---
lint: lint-verilator

lint-verilator:
	@echo "=== Strict Verilator Linting (All Models) ==="
	@$(MAKE) -C models/pipelined/dataflow_switching lint-verilator
	@$(MAKE) -C models/pipelined/spatial_fission lint-verilator
	@$(MAKE) -C models/pipelined/heterogeneous_fission lint-verilator
	@$(MAKE) -C models/non_pipelined/dataflow_switching lint-verilator
	@$(MAKE) -C models/non_pipelined/spatial_fission lint-verilator
	@$(MAKE) -C models/non_pipelined/heterogeneous_fission lint-verilator

lint-cadence:
	@echo "=== Cadence HAL Linting (All Models) ==="
	@$(MAKE) -C models/pipelined/dataflow_switching lint-cadence
	@$(MAKE) -C models/pipelined/spatial_fission lint-cadence
	@$(MAKE) -C models/pipelined/heterogeneous_fission lint-cadence
	@$(MAKE) -C models/non_pipelined/dataflow_switching lint-cadence
	@$(MAKE) -C models/non_pipelined/spatial_fission lint-cadence
	@$(MAKE) -C models/non_pipelined/heterogeneous_fission lint-cadence

# --- Open-Source & Batch Simulation ---
sim-verilator:
	./scripts/run_all_models.sh verilator all $(TEST)

sim-iverilog:
	./scripts/run_all_models.sh iverilog all $(TEST)

sim-xrun:
	./scripts/run_all_models.sh xrun all $(TEST)

# --- Clean Target ---
clean:
	@$(MAKE) -C models/pipelined/dataflow_switching clean
	@$(MAKE) -C models/pipelined/spatial_fission clean
	@$(MAKE) -C models/pipelined/heterogeneous_fission clean
	@$(MAKE) -C models/non_pipelined/dataflow_switching clean
	@$(MAKE) -C models/non_pipelined/spatial_fission clean
	@$(MAKE) -C models/non_pipelined/heterogeneous_fission clean
	@echo "Clean completed."
