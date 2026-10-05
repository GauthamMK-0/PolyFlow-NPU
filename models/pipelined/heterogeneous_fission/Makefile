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

# Test selector (defaults to ALL, can pass TEST=split, TEST=coexec, etc.)
TEST ?= ALL

# Common xrun flags
XRUN_FLAGS = -64bit \
             -sv \
             -access +rwc \
             -top hdf_top_tb \
             -incdir ../tb \
             -incdir ../tb/tests \
             +TEST=$(TEST) \
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
	@echo "Running Verilator Strict Linting for Model 3 (hdf_top)"
	@echo "=================================================================="
	verilator --lint-only -Wall --timing -I$(TB_DIR) $(SRC_FILES)

lint-cadence:
	@echo "=================================================================="
	@echo "Running Cadence HAL / Xcelium Linting for Model 3 (hdf_top)"
	@echo "=================================================================="
	hal -incdir $(TB_DIR) $(SRC_FILES)

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
	@echo "Launching Cadence Genus Synthesis for hdf_top"
	@echo "=================================================================="
	genus -f synth_hdf.tcl -log genus_hdf.log

clean:
	@echo "Cleaning up all simulation logs, compile databases, synthesis reports, and netlists..."
	rm -rf $(OUT_DIR) xcelium.d waves.shm .simvision xrun.history xrun.log genus* fv/ *.rpt *_netlist.* reports/ netlist/

help:
	@echo "Available Makefile targets:"
	@echo "  make lint            - Run default linting (Verilator)"
	@echo "  make lint-verilator  - Run strict Verilator linting (--lint-only -Wall)"
	@echo "  make lint-cadence    - Run Cadence HAL linting"
	@echo "  make run             - Run simulation with GUI enabled (default)"
	@echo "  make run GUI=0       - Run simulation in batch/command-line mode"
	@echo "  make synth           - Run Cadence Genus logic synthesis using synth_hdf.tcl"
	@echo "  make clean           - Delete output directories, reports, and log files"

