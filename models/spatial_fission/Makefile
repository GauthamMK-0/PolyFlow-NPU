# ==============================================================================
# Cadence Xcelium (xrun) Simulation Makefile - Model 2: Spatial Fission
# ==============================================================================

# --- Directories ---
RTL_DIR    = ./rtl
TB_DIR     = ./tb
OUT_DIR    = ./output

# --- Source Files ---
SRC_FILES  = $(RTL_DIR)/sfa_pe.sv \
             $(RTL_DIR)/sfa_fission_decoder.sv \
             $(RTL_DIR)/sfa_array.sv \
             $(RTL_DIR)/sfa_otp_fsm.sv \
             $(RTL_DIR)/sfa_bank_scrub.sv \
             $(RTL_DIR)/sfa_eppa.sv \
             $(RTL_DIR)/sfa_top.sv \
             $(TB_DIR)/sfa_top_tb.sv

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
.PHONY: all run clean help lint synth

# Default target when you just type 'make'
all: run

lint:
	@echo "=================================================================="
	@echo "Running Verilator Strict Linting for Model 2 (sfa_top)"
	@echo "=================================================================="
	verilator --lint-only -Wall --timing $(SRC_FILES)

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
	@echo "Launching Cadence Genus Synthesis for sfa_top"
	@echo "=================================================================="
	genus -f synth_sfa.tcl -log genus_sfa.log

clean:
	@echo "Cleaning up all simulation logs, compile databases, and synthesis reports..."
	rm -rf $(OUT_DIR) xcelium.d waves.shm .simvision xrun.history xrun.log genus* fv/ *.rpt *_netlist.*

help:
	@echo "Available Makefile targets:"
	@echo "  make lint        - Run strict Verilator linting (--lint-only -Wall)"
	@echo "  make run         - Run simulation with GUI enabled (default)"
	@echo "  make run GUI=0   - Run simulation in batch/command-line mode"
	@echo "  make synth       - Run Cadence Genus logic synthesis using synth_sfa.tcl"
	@echo "  make clean       - Delete output directories, reports, and log files"

