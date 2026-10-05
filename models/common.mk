# ==============================================================================
# PolyFlow-NPU: Common Model Simulation & Synthesis Makefile Include
# Reusable rules for Cadence Xcelium (xrun), Genus, HAL, and Verilator
# ==============================================================================

# --- Directories ---
RTL_DIR    ?= ./rtl
TB_DIR     ?= ./tb
OUT_DIR    ?= ./output

# --- Source Files Auto-Discovery ---
RTL_FILES  ?= $(wildcard $(RTL_DIR)/*.sv)
TB_FILE    ?= $(TB_DIR)/$(TB_MODULE).sv
SRC_FILES  ?= $(RTL_FILES) $(TB_FILE)

# --- Simulation Options ---
# GUI visibility is OPTIONAL (Default: 0 = Headless batch mode; 1 = SimVision GUI)
GUI        ?= 0

ifeq ($(GUI), 1)
    GUI_FLAGS = -gui
else
    GUI_FLAGS =
endif

# Test selector (defaults to ALL, can pass TEST=ws, TEST=coexec, etc.)
TEST       ?= ALL

# Common Cadence Xcelium flags
XRUN_FLAGS ?= -64bit \
              -sv \
              -access +rwc \
              -top $(TB_MODULE) \
              -incdir ../tb \
              -incdir ../tb/tests \
              +TEST=$(TEST) \
              $(GUI_FLAGS) \
              -l xrun.log

# ==============================================================================
# Targets
# ==============================================================================
.PHONY: all run gui clean help lint lint-verilator lint-cadence synth

# Default target: Headless simulation
all: run

# --- Simulation Targets ---
run:
	@echo "=================================================================="
	@echo "Launching Xcelium Simulation for $(TB_MODULE) inside $(OUT_DIR)"
	@echo "Mode: $(if $(filter 1,$(GUI)),Interactive GUI (SimVision),Headless Batch) | Test: $(TEST)"
	@echo "=================================================================="
	@mkdir -p $(OUT_DIR)
	cd $(OUT_DIR) && xrun \
		$(addprefix ../, $(SRC_FILES)) \
		$(XRUN_FLAGS)

# Shortcut target to run with GUI enabled
gui:
	@$(MAKE) run GUI=1

# --- Linting Targets ---
lint: lint-verilator

lint-verilator:
	@echo "=================================================================="
	@echo "Running Verilator Strict Linting for $(TOP_MODULE)"
	@echo "=================================================================="
	verilator --lint-only -Wall --timing -I$(TB_DIR) $(SRC_FILES)

lint-cadence:
	@echo "=================================================================="
	@echo "Running Cadence HAL / Xcelium Linting for $(TOP_MODULE)"
	@echo "=================================================================="
	hal -incdir $(TB_DIR) $(SRC_FILES)

# --- Logic Synthesis Target ---
synth:
	@echo "=================================================================="
	@echo "Launching Cadence Genus Synthesis for $(TOP_MODULE)"
	@echo "=================================================================="
	genus -f $(SYNTH_TCL) -log genus_$(TOP_MODULE).log

# --- Cleanup Target ---
clean:
	@echo "Cleaning up $(TOP_MODULE) simulation sandbox, logs, and reports..."
	rm -rf $(OUT_DIR) xcelium.d waves.shm .simvision xrun.history xrun.log genus* fv/ *.rpt *_netlist.* reports/ netlist/

# --- Help Target ---
help:
	@echo "Available Makefile targets for $(TOP_MODULE):"
	@echo "  make run            - Run simulation in headless batch mode (default, GUI=0)"
	@echo "  make gui            - Run simulation with SimVision GUI enabled (GUI=1)"
	@echo "  make run GUI=1      - Run simulation with SimVision GUI enabled"
	@echo "  make run TEST=<name>- Run specific test (e.g. TEST=ws, TEST=coexec)"
	@echo "  make lint           - Run strict Verilator linting"
	@echo "  make lint-cadence   - Run Cadence HAL linting"
	@echo "  make synth          - Run Cadence Genus logic synthesis using $(SYNTH_TCL)"
	@echo "  make clean          - Delete sandbox, waveforms, and log files"
