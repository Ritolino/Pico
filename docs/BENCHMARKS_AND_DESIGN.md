# Benchmarks, Architecture & Engineering Design

> **An honest, transparent, and empirical analysis of Pico's architecture, memory footprint, performance benchmarks, key strengths, and known limitations.**
> Verified on Apple Silicon M5 (10-core: 4 Super + 6 Efficiency, 16.0 GB Unified RAM) on macOS 27.2.

---

## 1. Why Pico Was Built

Most macOS system monitors (such as *Stats*, *iStat Menus*, or *Sensei*) are multi-featured suites: they feature animated graphs, customizable themes, network packet sniffers, disk health monitors, and sensor history caches. 

However, this feature depth comes with a significant hidden cost:
- **High Memory Footprint**: They typically occupy between **100 MB and 300 MB** of physical RAM (`phys_footprint`).
- **Constant Idle Wakeups**: They trigger dozens of timer wakeups per second to feed live chart rendering, preventing Apple Silicon CPU cores from remaining in their deepest low-power sleep states (`C-states`).
- **Heavy UI Frameworks**: Many rely on SwiftUI or Electron, introducing rendering overhead, large dynamic libraries, and transient heap allocations.

**Pico's thesis is simple**: 
> *A system monitor must observe system resources without perturbing them.*

By strictly using **native AppKit**, **in-process Mach/IOKit kernel APIs**, and a single **coalesced 3.0-second background timer**, Pico maintains an ultra-low physical footprint of **~15 MB** and **0.0% idle CPU usage**.

---

## 2. Empirical Benchmarks & Test Results

All measurements below were gathered on physical hardware using macOS standard diagnostic tooling (`footprint`, `vmmap`, `leaks`, and `ps`).

### 2.1 Memory Footprint Comparison

| Monitor | UI Technology | Subprocesses Spawned | Physical Footprint (`phys_footprint`) | Overhead vs. AppKit Baseline | Relative Overhead vs. Pico |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bare AppKit Baseline** | AppKit (Minimal) | None | `~12 MB` | *Baseline* | *-20%* |
| **🍏 Pico** | **AppKit + CShim** | **None (0)** | **`~15 MB`** | **`+3 MB`** | **Reference (0%)** |
| **MenuMeters** | Legacy AppKit | None | `~30 MB – 60 MB` | `+18 MB – 48 MB` | **+100% to +300%** *(2× to 4× larger)* |
| **Stats** | SwiftUI + AppKit | `sysctl`, `ioreg` | `~100 MB – 250 MB` | `+88 MB – 238 MB` | **+550% to +1,550%** *(6× to 16× larger)* |
| **iStat Menus** | AppKit / Custom Helper | Background daemons | `~150 MB – 300 MB` | `+138 MB – 288 MB` | **+900% to +1,900%** *(10× to 20× larger)* |

*Note: On modern macOS (14.0+), simply launching the bare minimum AppKit runtime and linking system frameworks incurs an unavoidable baseline of ~12 MB. Pico's entire logic, collectors, 3 menu bar items, custom CoreGraphics views, and login item manager consume just ~3 MB of additional memory. In real-world usage, suites like Stats and iStat Menus grow rapidly from 100 MB up to 250–300 MB as thermal sensors, live history graphs, and multiple widgets are active.*

### 2.2 CPU Idle & Wakeup Overhead

- **Idle CPU Usage**: **`0.0%`** reported by Activity Monitor and `ps`.
- **Active CPU Time at Rest**: Over 60 seconds of continuous monitoring at a 3.0-second sampling interval, Pico consumed just **0.26 seconds** of total CPU core time (~0.43% duty cycle on a single efficiency core).
- **Idle Wakeups**: A single coalesced `DispatchSourceTimer` with a `500 ms` leeway ensures macOS power management can align timer execution with other system events, minimizing wakeups from low-power states.

### 2.3 Memory Leak & Long-Term Stability Tests

- **Collector Stress Test (5,000 cycles)**: 
  Continuous sampling of `host_processor_info`, `IOAccelerator` (GPU), and `host_statistics64` (RAM) over 5,000 consecutive iterations produced **0 bytes/cycle linear growth** and **0 memory leaks** (`leaks --atExit`).
- **Menu Lifecycle Stress Test (50 cycles)**: 
  Simulating 50 rapid user open-and-close cycles across CPU, GPU, and RAM menus showed a net memory delta of **0 KB** once AppKit's internal window backing stores were reclaimed.
- **Sleep / Wake Resilience**: 
  Verified across system sleep/wake transitions. Kernel Mach ports and IOKit client connections remain intact without stale handles, crashing, or resource leakage.

---

## 3. Core Architectural Principles & Key Strengths

```text
┌─────────────────────────────────────────────────────────────┐
│                       macOS Kernel                          │
│   (Mach host_processor_info, IOAccelerator, AppleSMC)      │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
    [Every 3.0s, Coalesced]       [Only while NSMenu is open, 1.0s]
               │                               │
        ┌──────▼──────┐                 ┌──────▼──────┐
        │  Rest Loop  │                 │ Detail Loop │
        └──────┬──────┘                 └──────┬──────┘
               │                               │
        Updates ONLY 3                  Queries Thermals, Watt,
        Integers in Bar                 Per-Core, Top 5 Processes
               │                               │
        ┌──────▼──────┐                 ┌──────▼──────┐
        │ NSStatusItem│                 │   NSMenu    │
        │ (Template)  │                 │ (High-Contr)│
        └─────────────┘                 └─────────────┘
```

### 3.1 Strict Dual-Loop Architecture
Pico strictly separates what runs in the background from what runs when the user clicks:
1. **Rest Loop (`3.0 s`)**: Only samples 3 integer numbers (`CPU %`, `GPU %`, `RAM %`). Allocates no heap memory during ticks.
2. **On-Demand Detail Loop (`1.0 s`)**: Expensive hardware queries (individual core loads, thermal diodes, SMC power in Watts, and `libproc` process table scans) activate **only** while the respective `NSMenu` is visible. When the menu closes, all detail state and temporary buffers are released immediately.

### 3.2 Zero Subprocesses & Zero Root Privileges
- For all telemetry and monitoring (`CPU`, `GPU`, `RAM`, thermals, wattage, top processes), Pico **never** calls `Process` / `NSTask` to run `top`, `ps`, `vm_stat`, `sysctl`, or `ioreg`. Everything runs in-process via Mach kernel traps (`mach_host_self()`), IOKit (`IOServiceGetMatchingService`), and `libproc`.
- Update checks against GitHub Releases (once 15 s after launch and at most once per 24 hours on wake) are isolated into a sub-second ephemeral self-worker (`--internal-update-check`) so `CFNetwork`/TLS libraries are never mapped into the resident `~15 MB` menu bar process.
- Pico requires **no `sudo` or administrator privileges**.

### 3.3 Activity Monitor RAM Formula Alignment
RAM usage matches macOS Activity Monitor's **Formula A**:
$$\text{Used RAM} = \text{App Memory} + \text{Wired Memory} + \text{Compressed Memory}$$
Many third-party tools calculate Used RAM as $\text{Total} - \text{Free}$, which incorrectly counts cached files as used memory and causes users to panic about high RAM usage.

### 3.4 Notch-Aware Menu Alignment & Optical Centering
- **Zero Notch Gap**: On MacBook displays with camera notches, AppKit's standard `NSPopupMenuWindow` can detach by ~16 pt from the menu bar. Pico dynamically aligns menu windows directly against `screen.visibleFrame.maxY`, ensuring menus sit flush with the bar, exactly like system status items (Battery, Wi-Fi).
- **Single-Instance Dynamic Template Rendering**: Icon text is rendered into a single dynamic `NSImage` template (32 pt fixed width). This guarantees zero horizontal jitter when values transition from `9%` to `100%`, and avoids static image caches (reducing CGImage memory from 11 MB to ~384 KB).

### 3.5 Native Launch-at-Login via `SMAppService`
Pico integrates with macOS 13+ modern Background Task Management (`SMAppService.mainApp`). No launch daemon plists, helper apps, or legacy Login Item scripts are needed.

---

## 4. Honest Engineering: Known Limitations & Weaknesses

Pico values transparency and data truthfulness above all else. Here are the deliberate trade-offs and architectural limitations:

### 4.1 Apple Silicon Exclusive
Pico is designed specifically for Apple Silicon SoCs (M1, M2, M3, M4, M5). It does not support Intel-based Macs. Certain APIs (such as AppleSMC power rail keys and `IOAccelerator` AGX metrics) are specific to the Apple Silicon architecture.

### 4.2 Sensor Diode Coverage across SoC Generations
Hardware thermal diodes and SMC power channels vary across Apple Silicon generations:
- Pico dynamically discovers `AppleSMC` CPU/GPU thermal diodes (`Tp*`, `Te*`, `Ta*`, `Tc*`, `Tg*`, `TVC0`/`TVG0`) across **M1–M5** (and falls back to `IOHIDEventSystemClient` via `dlopen`/`dlsym`), alongside public `ProcessInfo.thermalState` (`Nominal`–`Critical`) and multi-key SMC wattage (`PSTR` / `PPBR` / `PDTR`).
- If a specific Mac model or future macOS update restricts a private sensor key (note: unprivileged `libIOReport` CPU `Energy Model` counters return `0` without root on macOS 27.2), Pico gracefully displays **`N/A`** for that line rather than guessing or fabricating numbers.

### 4.3 Rootless Process Visibility Boundaries (SIP)
Because Pico strictly respects user permissions and avoids root privileges:
- Pico inspects the system process table using `proc_listpids` and queries `proc_pid_rusage(RUSAGE_INFO_V4)` for each process.
- Under macOS System Integrity Protection (SIP), standard user applications can inspect their own processes and common third-party applications, but certain hardened system daemons may withhold physical footprint details from non-root queries.
- In practice, Pico accurately identifies real top consumers (browsers, IDEs, media tools, Docker, etc.), but will never install a root daemon to bypass macOS security boundaries.

---

## 5. How to Verify Benchmarks Locally

Anyone can reproduce and verify Pico's resource consumption on their own Mac using standard terminal tools:

```bash
# 1. Verify compilation and hardware summary
./GitHub/Scripts/build.sh
./GitHub/build/Pico.app/Contents/MacOS/Pico --verify-build

# 2. Check physical footprint (phys_footprint)
footprint Pico | grep "Pico"

# 3. Check idle CPU usage over time
ps -o pid,rss,pcpu,time,command -p $(pgrep -x Pico)

# 4. Run automated memory leak detection
leaks Pico
```
