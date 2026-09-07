# ==============================================================================
# PolyFlow-NPU Top-Level Makefile (Cadence Xcelium & Standard Toolflow)
# ==============================================================================

# Simulation Tool Options: verilator, iverilog, xcelium
SIM_TOOL ?= xcelium
# Control Cadence SimVision GUI visibility: 1 (On) or 0 (Off)
GUI      ?= 0

MODELS = dataflow_switching spatial_fission heterogeneous_fission

.PHONY: all run run-all run-m1 run-m2 run-m3 clean help

all: run-all

# Run all models using the selected simulator
run-all:
ifeq ($(SIM_TOOL), xcelium)
	@echo "=================================================================="
	@echo " [PolyFlow-NPU] Simulating All Models with Cadence Xcelium (xrun)"
	@echo " GUI Mode: $(GUI)"
	@echo "=================================================================="
	@for model in $(MODELS); do \
		echo ""; \
		echo ">>> Running Cadence Xcelium for: $$model <<<"; \
		$(MAKE) -C models/$$model run GUI=$(GUI); \
	done
else
	@./scripts/run_all_models.sh $(SIM_TOOL)
endif

# Run individual models with Xcelium
run-m1:
	@$(MAKE) -C models/dataflow_switching run GUI=$(GUI)

run-m2:
	@$(MAKE) -C models/spatial_fission run GUI=$(GUI)

run-m3:
	@$(MAKE) -C models/heterogeneous_fission run GUI=$(GUI)

clean:
	@echo "Cleaning up all models simulation artifacts..."
	@for model in $(MODELS); do \
		$(MAKE) -C models/$$model clean; \
	done
	@rm -rf dump.vcd tb/dumps/ obj_dir/ scratch/ *.log

help:
	@echo "PolyFlow-NPU Simulation Makefile"
	@echo "=================================================================="
	@echo "Targets:"
	@echo "  make run-all [SIM_TOOL=xcelium|verilator|iverilog] [GUI=0|1]"
	@echo "               - Runs testbenches for all 3 architectural models"
	@echo "  make run-m1  [GUI=0|1]  - Runs Model 1 (Dataflow Switching) via Xcelium"
	@echo "  make run-m2  [GUI=0|1]  - Runs Model 2 (Spatial Fission) via Xcelium"
	@echo "  make run-m3  [GUI=0|1]  - Runs Model 3 (PolyFlow-NPU) via Xcelium"
	@echo "  make clean              - Cleans all simulation outputs and logs"
	@echo "  make help               - Shows this help dialog"
