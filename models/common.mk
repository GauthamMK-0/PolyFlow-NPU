# ==============================================================================
# PolyFlow-NPU: Common Model Simulation & Synthesis Makefile Include
# Reusable rules for Cadence Xcelium (xrun), Genus, HAL, Icarus, and Verilator
# Supports Multi-Scale Organization: 4x4, 8x8, 16x16
# ==============================================================================

# --- Array Scale Configuration (Default: 4x4; Options: 4x4, 8x8, 16x16) ---
SCALE          ?= 4x4

# --- Directories ---
MODEL_ROOT     := $(CURDIR)
RTL_DIR        ?= ./rtl
TB_DIR         ?= ./tb
OUT_DIR        ?= ./output/$(SCALE)
REPORT_DIR     ?= ./reports/$(SCALE)
NETLIST_DIR    ?= ./netlist/$(SCALE)
OUTPUTS_DIR    ?= ./outputs/$(SCALE)
DB_DIR         ?= ./db/$(SCALE)

# --- Module Resolution by Scale ---
ORIG_TB_MODULE ?= $(TB_MODULE)
ifeq ($(SCALE), 8x8)
    ACTIVE_TB_MODULE := $(patsubst %_16x16_tb,%_8x8_tb,$(patsubst %_8x8_tb,%_8x8_tb,$(patsubst %_tb,%_8x8_tb,$(ORIG_TB_MODULE))))
else ifeq ($(SCALE), 16x16)
    ACTIVE_TB_MODULE := $(patsubst %_8x8_tb,%_16x16_tb,$(patsubst %_16x16_tb,%_16x16_tb,$(patsubst %_tb,%_16x16_tb,$(ORIG_TB_MODULE))))
else
    ACTIVE_TB_MODULE := $(patsubst %_8x8_tb,%_tb,$(patsubst %_16x16_tb,%_tb,$(ORIG_TB_MODULE)))
endif

# Active testbench for current scale execution
CURRENT_TB := $(ACTIVE_TB_MODULE)

# --- Source Files Auto-Discovery ---
RTL_FILES  ?= $(wildcard $(RTL_DIR)/*.sv)
TB_FILE    ?= $(TB_DIR)/$(CURRENT_TB).sv
SRC_FILES  ?= $(RTL_FILES) $(TB_FILE)

# --- Simulation Options ---
# GUI visibility is OPTIONAL (Default: 0 = Headless batch mode; 1 = SimVision GUI)
GUI        ?= 0

ifeq ($(GUI), 1)
    GUI_FLAGS = -gui
else
    GUI_FLAGS =
endif

# Common Cadence Xcelium flags
XRUN_FLAGS ?= -64bit \
              -sv \
              -access +rwc \
              -top $(CURRENT_TB) \
              -incdir ../../tb \
              $(GUI_FLAGS) \
              -l xrun_$(SCALE).log

# ==============================================================================
# Targets
# ==============================================================================
.PHONY: all run gui clean help lint lint-verilator lint-cadence \
        sim-iverilog iverilog sim-verilator verilator \
        test-4x4 test-8x8 test-16x16 test-scaling \
        run-4x4 run-8x8 run-16x16 run-scaling \
        verilator-4x4 verilator-8x8 verilator-16x16 verilator-scaling \
        synth synth-4x4 synth-8x8 synth-16x16 synth-scaling \
        pnr-place pnr-place-4x4 pnr-place-8x8 pnr-place-16x16 pnr-place-scaling \
        pnr pnr-4x4 pnr-8x8 pnr-16x16 pnr-scaling

# Default target: Headless simulation
all: run

# --- Simulation Targets (Cadence Xcelium) ---
run:
	@echo "=================================================================="
	@echo "Launching Xcelium Simulation for $(CURRENT_TB) [Scale: $(SCALE)] inside $(OUT_DIR)"
	@echo "=================================================================="
	@mkdir -p $(OUT_DIR)
	cd $(OUT_DIR) && xrun \
		$(addprefix $(MODEL_ROOT)/, $(SRC_FILES)) \
		$(XRUN_FLAGS)

run-4x4:
	@$(MAKE) run SCALE=4x4

run-8x8:
	@$(MAKE) run SCALE=8x8

run-16x16:
	@$(MAKE) run SCALE=16x16

run-scaling: run-4x4 run-8x8 run-16x16

# Shortcut target to run with GUI enabled
gui:
	@$(MAKE) run GUI=1

# --- Open-Source Simulation Targets (Icarus Verilog) ---
sim-iverilog:
	@echo "=================================================================="
	@echo "Running Icarus Verilog Simulation for $(CURRENT_TB) [Scale: $(SCALE)]"
	@echo "=================================================================="
	@mkdir -p $(OUT_DIR)
	iverilog -g2012 -I $(TB_DIR) -o $(OUT_DIR)/$(CURRENT_TB).vvp $(SRC_FILES)
	vvp $(OUT_DIR)/$(CURRENT_TB).vvp
	@cp -f $(OUT_DIR)/$(CURRENT_TB).vvp ./output/$(CURRENT_TB).vvp 2>/dev/null || true

iverilog: sim-iverilog

# --- Array Scaling Verification Targets ---
test-4x4:
	@$(MAKE) iverilog SCALE=4x4

test-8x8:
	@$(MAKE) iverilog SCALE=8x8

test-16x16:
	@$(MAKE) iverilog SCALE=16x16

test-scaling: test-4x4 test-8x8 test-16x16

# --- Verilator Cycle Simulation Targets ---
sim-verilator:
	@echo "=================================================================="
	@echo "Running Verilator Simulation for $(CURRENT_TB) [Scale: $(SCALE)]"
	@echo "=================================================================="
	@mkdir -p obj_dir/$(SCALE)
	verilator -j $(shell nproc) --binary --timing -Wall -I$(TB_DIR) \
		-MAKEFLAGS "-j$(shell nproc) OPT_FAST=-O1" --Mdir obj_dir/$(SCALE) $(SRC_FILES) \
		--top-module $(CURRENT_TB) -o V$(CURRENT_TB) > /dev/null
	./obj_dir/$(SCALE)/V$(CURRENT_TB)

verilator: sim-verilator

verilator-4x4:
	@$(MAKE) verilator SCALE=4x4

verilator-8x8:
	@$(MAKE) verilator SCALE=8x8

verilator-16x16:
	@$(MAKE) verilator SCALE=16x16

verilator-scaling: verilator-4x4 verilator-8x8 verilator-16x16

# --- Linting Targets ---
lint: lint-verilator

lint-verilator:
	@echo "=================================================================="
	@echo "Running Verilator Strict Linting for $(TOP_MODULE)"
	@echo "=================================================================="
	verilator --lint-only -Wall -Wno-MULTITOP --timing -I$(TB_DIR) $(SRC_FILES)

lint-cadence:
	@echo "=================================================================="
	@echo "Running Cadence HAL / Xcelium Linting for $(TOP_MODULE)"
	@echo "=================================================================="
	hal -incdir $(TB_DIR) $(SRC_FILES)

# --- Logic Synthesis Targets (Cadence Genus) ---
synth:
	@echo "=================================================================="
	@echo "Launching Cadence Genus Synthesis for $(TOP_MODULE) [Scale: $(SCALE)]"
	@echo "=================================================================="
	@mkdir -p reports/$(SCALE) netlist/$(SCALE)
	SCALE=$(SCALE) genus -f $(SYNTH_TCL) -log genus_$(TOP_MODULE)_$(SCALE).log

synth-4x4:
	@$(MAKE) synth SCALE=4x4

synth-8x8:
	@$(MAKE) synth SCALE=8x8

synth-16x16:
	@$(MAKE) synth SCALE=16x16

synth-scaling: synth-4x4 synth-8x8 synth-16x16

# --- Physical Design Targets (Cadence Innovus PnR) ---
PNR_PLACE_TCL ?= pnr_place.tcl
PNR_TCL       ?= $(PNR_PLACE_TCL)

pnr-place:
	@echo "=================================================================="
	@echo "Launching Cadence Innovus Physical Design for $(TOP_MODULE) [Scale: $(SCALE)]"
	@echo "=================================================================="
	@mkdir -p db/$(SCALE) DBS/$(SCALE) outputs/$(SCALE) reports/$(SCALE)/cts
	SCALE=$(SCALE) innovus -files $(PNR_PLACE_TCL) -log innovus_$(TOP_MODULE)_$(SCALE)_place.log

pnr-place-4x4:
	@$(MAKE) pnr-place SCALE=4x4

pnr-place-8x8:
	@$(MAKE) pnr-place SCALE=8x8

pnr-place-16x16:
	@$(MAKE) pnr-place SCALE=16x16

pnr-place-scaling: pnr-place-4x4 pnr-place-8x8 pnr-place-16x16

pnr: pnr-place
pnr-4x4: pnr-place-4x4
pnr-8x8: pnr-place-8x8
pnr-16x16: pnr-place-16x16
pnr-scaling: pnr-place-scaling

# --- Cleanup Target ---
clean:
	@echo "Cleaning up $(TOP_MODULE) simulation sandbox, logs, and temporary files..."
	rm -rf output/4x4/*.vvp output/8x8/*.vvp output/16x16/*.vvp obj_dir xcelium.d waves.shm .simvision xrun*.history xrun*.log genus*.log innovus*.log fv/ timingReports ccopt* *.gds *.enc* *.spef viewDefinition_*_8x8.tcl viewDefinition_*_16x16.tcl

# --- Help Target ---
help:
	@echo "Available Makefile targets for $(TOP_MODULE) (Active Scale: $(SCALE)):"
	@echo "  make run            - Run Cadence Xcelium simulation for $(SCALE)"
	@echo "  make run-4x4        - Run Cadence Xcelium simulation for 4x4 baseline"
	@echo "  make run-8x8        - Run Cadence Xcelium simulation for 8x8 scaled pod"
	@echo "  make run-16x16      - Run Cadence Xcelium simulation for 16x16 scaled pod"
	@echo "  make gui            - Run simulation with SimVision GUI enabled (GUI=1)"
	@echo "  make iverilog       - Fast compilation & simulation using Icarus Verilog"
	@echo "  make test-4x4       - Run 4x4 baseline simulation using Icarus Verilog (output in output/4x4)"
	@echo "  make test-8x8       - Run 8x8 scaled pod simulation using Icarus Verilog (output in output/8x8)"
	@echo "  make test-16x16     - Run 16x16 scaled pod simulation using Icarus Verilog (output in output/16x16)"
	@echo "  make test-scaling   - Run complete scaling regression across 4x4, 8x8, and 16x16"
	@echo "  make verilator      - Cycle-accurate simulation using Verilator"
	@echo "  make synth          - Run Cadence Genus synthesis for active SCALE (reports in reports/$(SCALE))"
	@echo "  make synth-4x4      - Run Genus synthesis for 4x4 (reports/4x4, netlist/4x4)"
	@echo "  make synth-8x8      - Run Genus synthesis for 8x8 (reports/8x8, netlist/8x8)"
	@echo "  make synth-16x16    - Run Genus synthesis for 16x16 (reports/16x16, netlist/16x16)"
	@echo "  make synth-scaling  - Run Genus synthesis for all scales (4x4, 8x8, 16x16)"
	@echo "  make pnr-place      - Run Innovus physical design for active SCALE (outputs in outputs/$(SCALE))"
	@echo "  make pnr-place-4x4  - Run Innovus PnR for 4x4"
	@echo "  make pnr-place-8x8  - Run Innovus PnR for 8x8"
	@echo "  make pnr-place-16x16 - Run Innovus PnR for 16x16"
	@echo "  make pnr-place-scaling - Run Innovus PnR across all scales"
	@echo "  make clean          - Delete sandbox, waveforms, and log files"
