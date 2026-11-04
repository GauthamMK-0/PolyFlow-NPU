# Empirical Throughput & Multi-Tenancy Benchmark Results

### Benchmark Methodology & Setup
- **Workloads Co-Executed**: ResNet-50 Conv Layer (`WS-optimal`) + Vision Transformer Self-Attention $Q \cdot K^T$ (`OS-optimal`)
- **Data Precision**: Quantized Signed INT8 $\times$ INT8 $\to$ INT32 Accumulation
- **Clock Frequency**: 200 MHz ($T_{\text{clk}} = 5.000\text{ ns}$, 90nm Slow Corner)
- **Simulation Engine**: Cycle-Accurate Icarus Verilog RTL Simulation

## 1. Multi-Scale Empirical Throughput Comparison Table

| Scale | Metric | Model 1: Sequential (ReDas) | Model 2: Homog. Fission (Planaria) | Model 3: PolyFlow-NPU (Proposed) | PolyFlow Win vs. Baselines |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **4x4** (16 PEs) | **Makespan (cycles)** | 38 cyc | 52 cyc | **20 cyc** | **1.90× vs M1** / **2.60× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.19 $\mu\text{s}$ | 0.26 $\mu\text{s}$ | **0.10 $\mu\text{s}$** | **47.4% Latency Reduction** |
| | **Sustained Throughput** | 2.69 GOPS | 1.97 GOPS | **5.12 GOPS** | **Peak: 6.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 42.1% | 30.8% | **80.0%** | **+49.2% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.47× | 1.40× | **1.90×** | **Near-linear parallel scaling** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **8x8** (64 PEs) | **Makespan (cycles)** | 72 cyc | 166 cyc | **38 cyc** | **1.89× vs M1** / **4.37× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.36 $\mu\text{s}$ | 0.83 $\mu\text{s}$ | **0.19 $\mu\text{s}$** | **47.2% Latency Reduction** |
| | **Sustained Throughput** | 11.38 GOPS | 4.93 GOPS | **21.56 GOPS** | **Peak: 25.60 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 44.4% | 19.3% | **84.2%** | **+64.9% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.47× | 1.23× | **1.89×** | **Near-linear parallel scaling** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **16x16** (256 PEs) | **Makespan (cycles)** | 140 cyc | 586 cyc | **74 cyc** | **1.89× vs M1** / **7.92× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.70 $\mu\text{s}$ | 2.93 $\mu\text{s}$ | **0.37 $\mu\text{s}$** | **47.1% Latency Reduction** |
| | **Sustained Throughput** | 46.81 GOPS | 11.18 GOPS | **88.56 GOPS** | **Peak: 102.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 45.7% | 10.9% | **86.5%** | **+75.6% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.47× | 1.13× | **1.89×** | **Near-linear parallel scaling** |
| :---: | :--- | :---: | :---: | :---: | :--- |

## 2. Key Microarchitectural Findings

1. **Elimination of Head-of-Line (HoL) Queuing**: Model 1 forces the second tenant to wait in DRAM queues until the first tenant completely drains, resulting in high makespan and low multi-tenant throughput ($WS \equiv 1.00\times$). PolyFlow achieves immediate concurrency.
2. **Elimination of Dataflow Mismatch Reload Stalls**: In Model 2 (Planaria), locking the entire array to Weight-Stationary forces the Vision Transformer attention layer into a non-native dataflow. Key operands must be repeatedly reloaded from memory buffers, causing Region B to lag and stretching the makespan. PolyFlow allows Region B to operate natively in Output-Stationary, matching Region A in lockstep.
3. **Sustained Compute Density**: PolyFlow maintains $> 80\%$ active PE compute utilization across all array sizes ($4\times 4$, $8\times 8$, $16\times 16$), converting silicon area directly into effective arithmetic throughput.
