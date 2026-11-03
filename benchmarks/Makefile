# ==============================================================================
# Benchmarks Automation Makefile — PolyFlow-NPU
# Real-Workload Multi-Tenant Throughput & Bit-Exact Co-Verification Suite
# ==============================================================================

SCALE ?= all

.PHONY: help all data run run-4x4 run-8x8 run-16x16 verify clean

all: run

help:
	@echo "=================================================================="
	@echo " PolyFlow-NPU Real-Workload Throughput Benchmarking Suite"
	@echo "=================================================================="
	@echo " Targets:"
	@echo "   make data         - Generate quantized INT8 weights & golden models"
	@echo "   make run          - Run full benchmark across all scales (4x4, 8x8, 16x16)"
	@echo "   make run-4x4      - Run benchmark for 4x4 baseline"
	@echo "   make run-8x8      - Run benchmark for 8x8 scaled pod"
	@echo "   make run-16x16    - Run benchmark for 16x16 full pod"
	@echo "   make verify       - Verify 100% bit-exact accuracy vs. NumPy golden"
	@echo "   make clean        - Clean simulation executables and intermediate dumps"
	@echo "=================================================================="

data:
	python3 scripts/gen_real_workloads.py

run:
	python3 scripts/run_throughput_benchmark.py

run-4x4:
	python3 scripts/run_throughput_benchmark.py 4x4

run-8x8:
	python3 scripts/run_throughput_benchmark.py 8x8

run-16x16:
	python3 scripts/run_throughput_benchmark.py 16x16

verify:
	python3 scripts/verify_accuracy.py

clean:
	rm -rf results/4x4/*.vvp results/8x8/*.vvp results/16x16/*.vvp
	@echo "Benchmark cleanup complete."

