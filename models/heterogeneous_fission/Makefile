# ==============================================================================
# Cadence Xcelium (xrun) Simulation Makefile - Model 3: Heterogeneous Fission
# ==============================================================================

# --- Directories ---
RTL_DIR    = ./rtl
TB_DIR     = ./tb
OUT_DIR    = ./output

# --- Source Files ---
SRC_FILES  = $(RTL_DIR)/hdf_pe.sv \
             $(RTL_DIR)/hdf_fission_decoder.sv \
             $(RTL_DIR)/hdf_array_grid.sv \
             $(RTL_DIR)/eppa_arbiter.sv \
             $(RTL_DIR)/otp_token_fsm.sv \
             $(RTL_DIR)/pod_bank_scrub.sv \
             $(RTL_DIR)/hdf_top.sv \
             $(TB_DIR)/hdf_top_tb.sv

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
.PHONY: all run clean help

# Default target when you just type 'make'
all: run

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

clean:
	@echo "Cleaning up all simulation logs and compile databases..."
	rm -rf $(OUT_DIR) xcelium.d waves.shm .simvision xrun.history xrun.log

help:
	@echo "Available Makefile targets:"
	@echo "  make run         - Run simulation with GUI enabled (default)"
	@echo "  make run GUI=0   - Run simulation in batch/command-line mode"
	@echo "  make clean       - Delete the output directory and all log files"
