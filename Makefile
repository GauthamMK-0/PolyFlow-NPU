# ==============================================================================
# PolyFlow-NPU: Top-Level Master Simulation Makefile
# ==============================================================================

# Simulation tool configuration:
# GUI: 1 (Launch SimVision GUI, default for Cadence) or 0 (batch mode)
GUI        ?= 1
SIM_TOOL   ?= xrun

MODELS = models/dataflow_switching models/spatial_fission models/heterogeneous_fission

.PHONY: all run run-all run-model1 run-model2 run-model3 synth-all synth-model1 synth-model2 synth-model3 clean clean-all help

all: run-all

# Run all 3 models sequentially with Xcelium
run-all:
	@for m in $(MODELS); do \
		echo ""; \
		echo "##################################################################"; \
		echo " Running Simulation: $$m with $(SIM_TOOL) (GUI=$(GUI))"; \
		echo "##################################################################"; \
		$(MAKE) -C $$m run GUI=$(GUI) || exit 1; \
	done

run-model1:
	$(MAKE) -C models/dataflow_switching run GUI=$(GUI)

run-model2:
	$(MAKE) -C models/spatial_fission run GUI=$(GUI)

run-model3:
	$(MAKE) -C models/heterogeneous_fission run GUI=$(GUI)

# Run Cadence Genus logic synthesis across all 3 models
synth-all:
	@for m in $(MODELS); do \
		echo ""; \
		echo "##################################################################"; \
		echo " Synthesizing: $$m with Cadence Genus"; \
		echo "##################################################################"; \
		$(MAKE) -C $$m synth || exit 1; \
	done

synth-model1:
	$(MAKE) -C models/dataflow_switching synth

synth-model2:
	$(MAKE) -C models/spatial_fission synth

synth-model3:
	$(MAKE) -C models/heterogeneous_fission synth

clean-all:
	@for m in $(MODELS); do \
		$(MAKE) -C $$m clean; \
	done
	@rm -rf dump.vcd *.log

clean: clean-all

help:
	@echo "PolyFlow-NPU Cadence Verification & Synthesis Targets:"
	@echo "  make run-all           - Run all 3 simulation testbenches with SimVision GUI"
	@echo "  make run-all GUI=0     - Run all 3 simulation testbenches in batch mode"
	@echo "  make run-model1 GUI=0  - Run Model 1 simulation in batch mode"
	@echo "  make run-model2 GUI=0  - Run Model 2 simulation in batch mode"
	@echo "  make run-model3 GUI=0  - Run Model 3 simulation in batch mode"
	@echo "  make synth-all         - Run Cadence Genus synthesis for all 3 models"
	@echo "  make synth-model1      - Synthesize Model 1 (dfs_top)"
	@echo "  make synth-model2      - Synthesize Model 2 (sfa_top)"
	@echo "  make synth-model3      - Synthesize Model 3 (hdf_top)"
	@echo "  make clean-all         - Clean up all simulation and synthesis artifacts"
