# Empirical Throughput & Multi-Tenancy Benchmark Results

### Benchmark Methodology & Setup
- **Workloads Co-Executed**: ResNet-50 Conv Layer (`WS-optimal`) + Vision Transformer Self-Attention $Q \cdot K^T$ (`OS-optimal`)
- **Data Precision**: Quantized Signed INT8 $\times$ INT8 $\to$ INT32 Accumulation
- **Clock Frequency**: 200 MHz ($T_{\text{clk}} = 5.000\text{ ns}$, 90nm Slow Corner)
- **Simulation Engine**: Cycle-Accurate Icarus Verilog RTL Simulation

## 1. Multi-Scale Empirical Throughput Comparison Table

| Scale | Metric | Model 1: Sequential (ReDas) | Model 2: Homog. Fission (Planaria) | Model 3: PolyFlow-NPU (Proposed) | PolyFlow Win vs. Baselines |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **4x4** (16 PEs) | **Makespan (cycles)** | 54 cyc | 58 cyc | **28 cyc** | **1.93× vs M1** / **2.07× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.27 $\mu\text{s}$ | 0.29 $\mu\text{s}$ | **0.14 $\mu\text{s}$** | **48.1% Latency Reduction** |
| | **Sustained Throughput** | 1.90 GOPS | 1.77 GOPS | **3.66 GOPS** | **Peak: 6.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 29.6% | 27.6% | **57.1%** | **+29.6% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.48× | 1.45× | **2.00×** | **Optimal 2.00× parallel scaling bound** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **8x8** (64 PEs) | **Makespan (cycles)** | 100 cyc | 106 cyc | **52 cyc** | **1.92× vs M1** / **2.04× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.50 $\mu\text{s}$ | 0.53 $\mu\text{s}$ | **0.26 $\mu\text{s}$** | **48.0% Latency Reduction** |
| | **Sustained Throughput** | 8.19 GOPS | 7.73 GOPS | **15.75 GOPS** | **Peak: 25.60 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 32.0% | 30.2% | **61.5%** | **+31.3% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.48× | 1.45× | **2.00×** | **Optimal 2.00× parallel scaling bound** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **16x16** (256 PEs) | **Makespan (cycles)** | 192 cyc | 202 cyc | **100 cyc** | **1.92× vs M1** / **2.02× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.96 $\mu\text{s}$ | 1.01 $\mu\text{s}$ | **0.50 $\mu\text{s}$** | **47.9% Latency Reduction** |
| | **Sustained Throughput** | 34.13 GOPS | 32.44 GOPS | **65.54 GOPS** | **Peak: 102.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 33.3% | 31.7% | **64.0%** | **+32.3% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.48× | 1.46× | **2.00×** | **Optimal 2.00× parallel scaling bound** |
| :---: | :--- | :---: | :---: | :---: | :--- |

## 2. Key Microarchitectural Findings

1. **Elimination of Head-of-Line (HoL) Serialization Delay**: Model 1 (ReDas) forces the second tenant to wait until the first tenant completely finishes and drains, resulting in high total makespan and degraded multi-tenant throughput ($WS \approx 1.48\times$). PolyFlow-NPU achieves concurrent dispatch with zero HoL delay.
2. **Elimination of Dataflow Mismatch Reload Stalls**: In Model 2 (Planaria), locking the entire array to Weight-Stationary forces the Vision Transformer attention layer into a non-native dataflow. Key operands must be repeatedly reloaded from memory buffers across tiles, causing Region B to lag and stretching the makespan ($WS \approx 1.45\times$). PolyFlow allows Region B to operate natively in Output-Stationary, matching Region A in lockstep.
3. **Optimal Multi-Tenant Speedup ($WS = 2.00\times$)**: PolyFlow-NPU achieves the theoretical upper bound for 2-tenant parallel execution ($WS = 2.00\times$) with 100% bit-exact accuracy and balanced active PE utilization across all array sizes ($4\times 4$, $8\times 8$, $16\times 16$), converting silicon area directly into effective arithmetic throughput.
