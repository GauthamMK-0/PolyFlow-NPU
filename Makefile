# ==============================================================================
# PolyFlow-NPU: Top-Level Master Automation Makefile
# Unified Control for Cadence Digital Flow (Xcelium / Genus / Innovus) & Simulators
# Supports Partitioned Multi-Scale Deliverables (4x4, 8x8, 16x16)
# ==============================================================================

# Architectural model variant to target: pipelined (default) or non_pipelined
MODEL_VARIANT ?= pipelined

# Scale configuration: 4x4 (default), 8x8, or 16x16
SCALE         ?= 4x4

# Simulation mode: 1 (SimVision GUI) or 0 (Headless batch mode)
GUI           ?= 0

.PHONY: help all lint lint-verilator lint-cadence \
        run-model1 run-model2 run-model3 run-all \
        iverilog-model1 iverilog-model2 iverilog-model3 \
        test-4x4-all test-8x8-all test-16x16-all test-all \
        test-scaling-model1 test-scaling-model2 test-scaling-model3 test-scaling-all \
        test-8x8-model1 test-8x8-model2 test-8x8-model3 \
        test-16x16-model1 test-16x16-model2 test-16x16-model3 \
        verilator-model1 verilator-model2 verilator-model3 \
        synth-model1 synth-model2 synth-model3 synth-all \
        synth-4x4-model1 synth-4x4-model2 synth-4x4-model3 synth-4x4-all \
        synth-8x8-model1 synth-8x8-model2 synth-8x8-model3 synth-8x8-all \
        synth-16x16-model1 synth-16x16-model2 synth-16x16-model3 synth-16x16-all \
        synth-scaling-model1 synth-scaling-model2 synth-scaling-model3 synth-scaling-all \
        pnr-place-model1 pnr-place-model2 pnr-place-model3 pnr-place-all \
        pnr-place-4x4-model1 pnr-place-4x4-model2 pnr-place-4x4-model3 pnr-place-4x4-all \
        pnr-place-8x8-model1 pnr-place-8x8-model2 pnr-place-8x8-model3 pnr-place-8x8-all \
        pnr-place-16x16-model1 pnr-place-16x16-model2 pnr-place-16x16-model3 pnr-place-16x16-all \
        pnr-place-scaling-model1 pnr-place-scaling-model2 pnr-place-scaling-model3 pnr-place-scaling-all \
        pnr-model1 pnr-model2 pnr-model3 pnr-all \
        sim-verilator sim-iverilog sim-xrun clean

# Default target
all: help

help:
	@echo "=================================================================="
	@echo " PolyFlow-NPU Master Automation Makefile"
	@echo " Active Variant: $(MODEL_VARIANT) | Default Scale: $(SCALE) | GUI: $(GUI)"
	@echo " Deliverables are partitioned per scale:"
	@echo "   reports/{4x4,8x8,16x16}/   outputs/{4x4,8x8,16x16}/"
	@echo "   netlist/{4x4,8x8,16x16}/   output/{4x4,8x8,16x16}/   db/{4x4,8x8,16x16}/"
	@echo "=================================================================="
	@echo " Cadence Xcelium Simulation Targets:"
	@echo "   make run-model1 [SCALE=...] [GUI=0/1]   - Run Model 1: Dataflow Switching"
	@echo "   make run-model2 [SCALE=...] [GUI=0/1]   - Run Model 2: Spatial Fission"
	@echo "   make run-model3 [SCALE=...] [GUI=0/1]   - Run Model 3: Heterogeneous Fission"
	@echo "   make run-all    [SCALE=...] [GUI=0/1]   - Run all 3 models sequentially"
	@echo ""
	@echo " Fast Icarus Verilog Simulation Shortcuts (< 1s):"
	@echo "   make iverilog-model1                    - Run Model 1 with Icarus (4x4 baseline)"
	@echo "   make iverilog-model2                    - Run Model 2 with Icarus (4x4 baseline)"
	@echo "   make iverilog-model3                    - Run Model 3 with Icarus (4x4 baseline)"
	@echo "   make test-4x4-all                       - Run 4x4 baseline across all 3 models"
	@echo ""
	@echo " Array Scaling Verification Targets (4x4, 8x8, 16x16):"
	@echo "   make test-8x8-all                       - Run 8x8 scaled pod across all 3 models"
	@echo "   make test-16x16-all                     - Run 16x16 scaled pod across all 3 models"
	@echo "   make test-scaling-all                   - Verify all 3 models across all array sizes (9 suites)"
	@echo "   make test-scaling-model1                - Verify Model 1 across 4x4, 8x8, and 16x16"
	@echo "   make test-scaling-model2                - Verify Model 2 across 4x4, 8x8, and 16x16"
	@echo "   make test-scaling-model3                - Verify Model 3 across 4x4, 8x8, and 16x16"
	@echo ""
	@echo " Verilator Cycle Simulation Shortcuts:"
	@echo "   make verilator-model1 [SCALE=...]       - Run Model 1 with Verilator"
	@echo "   make verilator-model2 [SCALE=...]       - Run Model 2 with Verilator"
	@echo "   make verilator-model3 [SCALE=...]       - Run Model 3 with Verilator"
	@echo ""
	@echo " Cadence Genus Logic Synthesis Targets:"
	@echo "   make synth-model1 [SCALE=...]           - Synthesize Model 1 netlist & reports"
	@echo "   make synth-model2 [SCALE=...]           - Synthesize Model 2 netlist & reports"
	@echo "   make synth-model3 [SCALE=...]           - Synthesize Model 3 netlist & reports"
	@echo "   make synth-all    [SCALE=...]           - Synthesize all 3 models sequentially"
	@echo "   make synth-4x4-all                      - Synthesize 4x4 across all models"
	@echo "   make synth-8x8-all                      - Synthesize 8x8 across all models"
	@echo "   make synth-16x16-all                    - Synthesize 16x16 across all models"
	@echo "   make synth-scaling-all                  - Synthesize all models across 4x4, 8x8, 16x16"
	@echo ""
	@echo " Cadence Innovus Standard Cell Placement & PnR Targets:"
	@echo "   make pnr-place-model1 [SCALE=...]       - Run Innovus placement for Model 1"
	@echo "   make pnr-place-model2 [SCALE=...]       - Run Innovus placement for Model 2"
	@echo "   make pnr-place-model3 [SCALE=...]       - Run Innovus placement for Model 3"
	@echo "   make pnr-place-all    [SCALE=...]       - Run Innovus placement across all 3 models"
	@echo "   make pnr-place-4x4-all                  - Run Innovus placement 4x4 across all models"
	@echo "   make pnr-place-8x8-all                  - Run Innovus placement 8x8 across all models"
	@echo "   make pnr-place-16x16-all                - Run Innovus placement 16x16 across all models"
	@echo "   make pnr-place-scaling-all              - Run Innovus placement across all scales"
	@echo ""
	@echo " Multi-Model Linting & Verification Targets:"
	@echo "   make lint                               - Run strict Verilator linting across all models"
	@echo "   make lint-verilator                     - Run strict Verilator linting across all models"
	@echo "   make lint-cadence                       - Run Cadence HAL linting across all models"
	@echo ""
	@echo " Maintenance:"
	@echo "   make clean                              - Clean temporary build artifacts (preserves tracked reports)"
	@echo "=================================================================="

# --- Cadence Xcelium Simulation Targets ---
run-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching run SCALE=$(SCALE) GUI=$(GUI)

run-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission run SCALE=$(SCALE) GUI=$(GUI)

run-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission run SCALE=$(SCALE) GUI=$(GUI)

run-all: run-model1 run-model2 run-model3

# --- Fast Icarus Verilog Simulation Shortcuts ---
iverilog-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching iverilog SCALE=$(SCALE)

iverilog-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission iverilog SCALE=$(SCALE)

iverilog-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission iverilog SCALE=$(SCALE)

# --- Array Scaling Verification Shortcuts (4x4, 8x8, 16x16) ---
test-4x4-all: iverilog-model1 iverilog-model2 iverilog-model3

test-8x8-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching test-8x8

test-8x8-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission test-8x8

test-8x8-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission test-8x8

test-8x8-all: test-8x8-model1 test-8x8-model2 test-8x8-model3

test-16x16-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching test-16x16

test-16x16-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission test-16x16

test-16x16-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission test-16x16

test-16x16-all: test-16x16-model1 test-16x16-model2 test-16x16-model3

test-scaling-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching test-scaling

test-scaling-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission test-scaling

test-scaling-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission test-scaling

test-scaling-all: test-scaling-model1 test-scaling-model2 test-scaling-model3
test-all: test-scaling-all

# --- Verilator Cycle Simulation Shortcuts ---
verilator-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching verilator SCALE=$(SCALE)

verilator-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission verilator SCALE=$(SCALE)

verilator-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission verilator SCALE=$(SCALE)

# --- Optional GUI Shortcuts (SimVision) ---
gui-model1:
	@$(MAKE) run-model1 GUI=1

gui-model2:
	@$(MAKE) run-model2 GUI=1

gui-model3:
	@$(MAKE) run-model3 GUI=1

# --- Cadence Genus Synthesis Targets ---
synth-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching synth SCALE=$(SCALE)

synth-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission synth SCALE=$(SCALE)

synth-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission synth SCALE=$(SCALE)

synth-all: synth-model1 synth-model2 synth-model3

# Multi-Scale Synthesis Targets
synth-4x4-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching synth-4x4

synth-4x4-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission synth-4x4

synth-4x4-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission synth-4x4

synth-4x4-all: synth-4x4-model1 synth-4x4-model2 synth-4x4-model3

synth-8x8-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching synth-8x8

synth-8x8-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission synth-8x8

synth-8x8-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission synth-8x8

synth-8x8-all: synth-8x8-model1 synth-8x8-model2 synth-8x8-model3

synth-16x16-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching synth-16x16

synth-16x16-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission synth-16x16

synth-16x16-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission synth-16x16

synth-16x16-all: synth-16x16-model1 synth-16x16-model2 synth-16x16-model3

synth-scaling-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching synth-scaling

synth-scaling-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission synth-scaling

synth-scaling-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission synth-scaling

synth-scaling-all: synth-scaling-model1 synth-scaling-model2 synth-scaling-model3

# --- Cadence Innovus Physical Design (PnR) Targets ---
pnr-place-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching pnr-place SCALE=$(SCALE)

pnr-place-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission pnr-place SCALE=$(SCALE)

pnr-place-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission pnr-place SCALE=$(SCALE)

pnr-place-all: pnr-place-model1 pnr-place-model2 pnr-place-model3

pnr-model1: pnr-place-model1
pnr-model2: pnr-place-model2
pnr-model3: pnr-place-model3
pnr-all: pnr-place-all

# Multi-Scale PnR Targets
pnr-place-4x4-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching pnr-place-4x4

pnr-place-4x4-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission pnr-place-4x4

pnr-place-4x4-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission pnr-place-4x4

pnr-place-4x4-all: pnr-place-4x4-model1 pnr-place-4x4-model2 pnr-place-4x4-model3

pnr-place-8x8-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching pnr-place-8x8

pnr-place-8x8-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission pnr-place-8x8

pnr-place-8x8-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission pnr-place-8x8

pnr-place-8x8-all: pnr-place-8x8-model1 pnr-place-8x8-model2 pnr-place-8x8-model3

pnr-place-16x16-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching pnr-place-16x16

pnr-place-16x16-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission pnr-place-16x16

pnr-place-16x16-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission pnr-place-16x16

pnr-place-16x16-all: pnr-place-16x16-model1 pnr-place-16x16-model2 pnr-place-16x16-model3

pnr-place-scaling-model1:
	@$(MAKE) -C models/$(MODEL_VARIANT)/dataflow_switching pnr-place-scaling

pnr-place-scaling-model2:
	@$(MAKE) -C models/$(MODEL_VARIANT)/spatial_fission pnr-place-scaling

pnr-place-scaling-model3:
	@$(MAKE) -C models/$(MODEL_VARIANT)/heterogeneous_fission pnr-place-scaling

pnr-place-scaling-all: pnr-place-scaling-model1 pnr-place-scaling-model2 pnr-place-scaling-model3

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
	./scripts/run_all_models.sh verilator all

sim-iverilog:
	./scripts/run_all_models.sh iverilog all

sim-xrun:
	./scripts/run_all_models.sh xrun all

# --- Real-Workload Benchmarks & Accuracy Co-Verification ---
benchmark:
	@$(MAKE) -C benchmarks run

benchmark-4x4:
	@$(MAKE) -C benchmarks run-4x4

benchmark-8x8:
	@$(MAKE) -C benchmarks run-8x8

benchmark-16x16:
	@$(MAKE) -C benchmarks run-16x16

benchmark-verify:
	@$(MAKE) -C benchmarks verify

# --- Clean Target ---
clean:
	@$(MAKE) -C models/pipelined/dataflow_switching clean
	@$(MAKE) -C models/pipelined/spatial_fission clean
	@$(MAKE) -C models/pipelined/heterogeneous_fission clean
	@$(MAKE) -C models/non_pipelined/dataflow_switching clean
	@$(MAKE) -C models/non_pipelined/spatial_fission clean
	@$(MAKE) -C models/non_pipelined/heterogeneous_fission clean
	@echo "Clean completed."
