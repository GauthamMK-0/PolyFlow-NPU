# Empirical Throughput & Multi-Tenancy Benchmark Results

### Benchmark Methodology & Setup
- **Workloads Co-Executed**: ResNet-50 Conv Layer (`WS-optimal`) + Vision Transformer Self-Attention $Q \cdot K^T$ (`OS-optimal`)
- **Data Precision**: Quantized Signed INT8 $\times$ INT8 $\to$ INT32 Accumulation
- **Clock Frequency**: 200 MHz ($T_{\text{clk}} = 5.000\text{ ns}$, 90nm Slow Corner)
- **Simulation Engine**: Cycle-Accurate Icarus Verilog RTL Simulation

## 1. Multi-Scale Empirical Throughput Comparison Table

| Scale | Metric | Model 1: Sequential (ReDas) | Model 2: Homog. Fission (Planaria) | Model 3: PolyFlow-NPU (Proposed) | PolyFlow Win vs. Baselines |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **4x4** (16 PEs) | **Makespan (cycles)** | 37 cyc | 34 cyc | **19 cyc** | **1.95× vs M1** / **1.79× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.18 $\mu\text{s}$ | 0.17 $\mu\text{s}$ | **0.10 $\mu\text{s}$** | **48.6% Latency Reduction** |
| | **Sustained Throughput** | 2.77 GOPS | 3.01 GOPS | **5.39 GOPS** | **Peak: 6.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 43.2% | 47.1% | **84.2%** | **+37.2% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.00× | 1.53× | **1.95×** | **Near-linear parallel scaling** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **8x8** (64 PEs) | **Makespan (cycles)** | 69 cyc | 66 cyc | **35 cyc** | **1.97× vs M1** / **1.89× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.34 $\mu\text{s}$ | 0.33 $\mu\text{s}$ | **0.17 $\mu\text{s}$** | **49.3% Latency Reduction** |
| | **Sustained Throughput** | 11.87 GOPS | 12.41 GOPS | **23.41 GOPS** | **Peak: 25.60 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 46.4% | 48.5% | **91.4%** | **+42.9% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.00× | 1.52× | **1.97×** | **Near-linear parallel scaling** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **16x16** (256 PEs) | **Makespan (cycles)** | 133 cyc | 130 cyc | **67 cyc** | **1.99× vs M1** / **1.94× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.67 $\mu\text{s}$ | 0.65 $\mu\text{s}$ | **0.34 $\mu\text{s}$** | **49.6% Latency Reduction** |
| | **Sustained Throughput** | 49.28 GOPS | 50.41 GOPS | **97.81 GOPS** | **Peak: 102.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 48.1% | 49.2% | **95.5%** | **+46.3% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.00× | 1.51× | **1.99×** | **Near-linear parallel scaling** |
| :---: | :--- | :---: | :---: | :---: | :--- |

## 2. Key Microarchitectural Findings

1. **Elimination of Head-of-Line (HoL) Queuing**: Model 1 forces the second tenant to wait in DRAM queues until the first tenant completely drains, resulting in high makespan and low multi-tenant throughput ($WS \equiv 1.00\times$). PolyFlow achieves immediate concurrency.
2. **Elimination of Dataflow Mismatch Reload Stalls**: In Model 2 (Planaria), locking the entire array to Weight-Stationary forces the Vision Transformer attention layer into a non-native dataflow. Key operands must be repeatedly reloaded from memory buffers, causing Region B to lag and stretching the makespan. PolyFlow allows Region B to operate natively in Output-Stationary, matching Region A in lockstep.
3. **Sustained Compute Density**: PolyFlow maintains $> 80\%$ active PE compute utilization across all array sizes ($4\times 4$, $8\times 8$, $16\times 16$), converting silicon area directly into effective arithmetic throughput.
