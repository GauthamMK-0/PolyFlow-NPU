# ==============================================================================
# Cadence Xcelium (xrun) Simulation Makefile - Model 1: Dataflow Switching
# ==============================================================================

# --- Directories ---
RTL_DIR    = ./rtl
TB_DIR     = ./tb
OUT_DIR    = ./output

# --- Source Files ---
SRC_FILES  = $(RTL_DIR)/dfs_pe.sv \
             $(RTL_DIR)/dfs_array.sv \
             $(RTL_DIR)/dfs_top.sv \
             $(TB_DIR)/dfs_top_tb.sv

# --- Simulation Options ---
# Control GUI visibility from the command line. Options: 1 (On) or 0 (Off)
GUI        ?= 1

ifeq ($(GUI), 1)
    GUI_FLAGS = -gui
else
    GUI_FLAGS =
endif

# Common xrun flags
XRUN_FLAGS = -64bit \
             -sv \
             -access +rwc \
             $(GUI_FLAGS) \
             -l xrun.log

# ==============================================================================
# Targets
# ==============================================================================
.PHONY: all run clean help lint lint-verilator lint-cadence synth

# Default target when you just type 'make'
all: run

# --- Linting Targets ---
lint: lint-verilator

lint-verilator:
	@echo "=================================================================="
	@echo "Running Verilator Strict Linting for Model 1 (dfs_top)"
	@echo "=================================================================="
	verilator --lint-only -Wall --timing $(SRC_FILES)

lint-cadence:
	@echo "=================================================================="
	@echo "Running Cadence HAL / Xcelium Linting for Model 1 (dfs_top)"
	@echo "=================================================================="
	hal $(SRC_FILES)

run:
	@echo "=================================================================="
	@echo "Creating sandbox and launching Xcelium inside: $(OUT_DIR)"
	@echo "=================================================================="
	@mkdir -p $(OUT_DIR)
	@# Change into the output directory and execute xrun.
	@# Prepending ../ to the source files tells xrun to look back up in the root.
	cd $(OUT_DIR) && xrun \
		$(addprefix ../, $(SRC_FILES)) \
		$(XRUN_FLAGS)

synth:
	@echo "=================================================================="
	@echo "Launching Cadence Genus Synthesis for dfs_top"
	@echo "=================================================================="
	genus -f synth_dfs.tcl -log genus_dfs.log

clean:
	@echo "Cleaning up all simulation logs, compile databases, and synthesis reports..."
	rm -rf $(OUT_DIR) xcelium.d waves.shm .simvision xrun.history xrun.log genus* fv/ *.rpt *_netlist.* reports/

help:
	@echo "Available Makefile targets:"
	@echo "  make lint            - Run default linting (Verilator)"
	@echo "  make lint-verilator  - Run strict Verilator linting (--lint-only -Wall)"
	@echo "  make lint-cadence    - Run Cadence HAL linting"
	@echo "  make run             - Run simulation with GUI enabled (default)"
	@echo "  make run GUI=0       - Run simulation in batch/command-line mode"
	@echo "  make synth           - Run Cadence Genus logic synthesis using synth_dfs.tcl"
	@echo "  make clean           - Delete output directories, reports, and log files"

