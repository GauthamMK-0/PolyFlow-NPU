# ==============================================================================
# PolyFlow-NPU: Top-Level Master Simulation Makefile
# ==============================================================================

# Simulation tool configuration:
# GUI: 1 (Launch SimVision GUI, default for Cadence) or 0 (batch mode)
GUI        ?= 1
SIM_TOOL   ?= xrun

MODELS = models/dataflow_switching models/spatial_fission models/heterogeneous_fission

.PHONY: all run run-all run-model1 run-model2 run-model3 clean clean-all help

all: run-all

# Run all 3 models sequentially
run-all:
	@for m in $(MODELS); do \
		echo ""; \
		echo "##################################################################"; \
		echo " Running Model: $$m with $(SIM_TOOL) (GUI=$(GUI))"; \
		echo "##################################################################"; \
		$(MAKE) -C $$m run GUI=$(GUI) || exit 1; \
	done

run-model1:
	$(MAKE) -C models/dataflow_switching run GUI=$(GUI)

run-model2:
	$(MAKE) -C models/spatial_fission run GUI=$(GUI)

run-model3:
	$(MAKE) -C models/heterogeneous_fission run GUI=$(GUI)

clean-all:
	@for m in $(MODELS); do \
		$(MAKE) -C $$m clean; \
	done
	@rm -rf dump.vcd *.log

clean: clean-all

help:
	@echo "PolyFlow-NPU Simulation Targets:"
	@echo "  make run-all           - Run all 3 models in Cadence Xcelium GUI mode (default)"
	@echo "  make run-all GUI=0     - Run all 3 models in Cadence batch mode"
	@echo "  make run-model1 GUI=0  - Run Model 1 (Dataflow Switching) in batch mode"
	@echo "  make run-model2 GUI=0  - Run Model 2 (Spatial Fission) in batch mode"
	@echo "  make run-model3 GUI=0  - Run Model 3 (Heterogeneous Fission) in batch mode"
	@echo "  make clean-all         - Clean up all simulation sandboxes and database directories"
