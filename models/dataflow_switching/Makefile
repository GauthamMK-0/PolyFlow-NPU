# ==============================================================================
# Cadence Xcelium (xrun) Simulation Makefile
# Model 1: Dataflow Switching Architecture (Configuration B)
# ==============================================================================

# --- Directories ---
RTL_DIR    = ./rtl
TB_DIR     = ./tb
OUT_DIR    = ./output

# --- Source Files ---
# Listed with relative paths from this model's root directory
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
# -access +rwc: Enable read/write/connectivity access for waveform probing & debug
# -64bit      : Run in 64-bit mode
# -sv         : Enable SystemVerilog parsing
# -timescale  : Default timescale fallback if not in file
XRUN_FLAGS = -64bit \
             -sv \
             -timescale 1ns/1ps \
             -access +rwc \
             $(GUI_FLAGS) \
             -l xrun.log

# ==============================================================================
# Targets
# ==============================================================================
.PHONY: all run clean help

# Default target when you just type 'make'
all: run

run:
	@echo "=================================================================="
	@echo " [Model 1: Dataflow Switching] Launching Xcelium inside: $(OUT_DIR)"
	@echo "=================================================================="
	@mkdir -p $(OUT_DIR)
	@# Change into the output directory and execute xrun.
	@# Prepending ../ to the source files tells xrun to look back up in the model root.
	cd $(OUT_DIR) && xrun \
		$(addprefix ../, $(SRC_FILES)) \
		$(XRUN_FLAGS)

clean:
	@echo "Cleaning up simulation output directory and logs..."
	rm -rf $(OUT_DIR) waves.shm xcelium.d .simvision xrun.log xrun.history

help:
	@echo "Available Makefile targets for Model 1 (Dataflow Switching):"
	@echo "  make run         - Run simulation with Cadence SimVision GUI enabled (default)"
	@echo "  make run GUI=0   - Run simulation in batch/command-line mode"
	@echo "  make clean       - Delete $(OUT_DIR) and Cadence intermediate simulation files"
	@echo "  make help        - Display this help message"
