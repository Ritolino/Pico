<p align="center">
  <img src="assets/app_icon.png" width="128" height="128" alt="Pico App Icon">
</p>

# Pico

[![Platform](https://img.shields.io/badge/Platform-macOS%20Apple%20Silicon-blue?logo=apple&logoColor=white)](https://github.com/Ritolino/Pico)
[![Architecture](https://img.shields.io/badge/Architecture-Native%20AppKit%20%2B%20Swift%20%2B%20C-purple)](https://github.com/Ritolino/Pico)
[![Memory Footprint](https://img.shields.io/badge/RAM%20Footprint-~15%20MB-brightgreen)](docs/BENCHMARKS_AND_DESIGN.md)
[![CPU Idle](https://img.shields.io/badge/CPU%20Idle-0.0%25-brightgreen)](docs/BENCHMARKS_AND_DESIGN.md)
[![Release](https://img.shields.io/badge/Release-v1.0.0-orange)](https://github.com/Ritolino/Pico/releases/tag/v1.0.0)
[![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

An **ultra-lightweight, zero-overhead, privacy-first** system monitor for the macOS menu bar, purpose-built for **Apple Silicon** (M1 / M2 / M3 / M4 / M5). Designed as a minimalist, battery-friendly alternative to resource-heavy monitoring suites like *Stats* and *iStat Menus*.

[**🇮🇹 Leggi il README in lingua italiana (README.it.md)**](README.it.md)

---

### ⬇️ Download Pre-built App (No Installation Required)

| Platform | Supported Hardware | Package Format | Download Link |
| :--- | :--- | :--- | :--- |
| **🍏 macOS** | Apple Silicon (M1 / M2 / M3 / M4 / M5) | Standalone Bundle (.zip) | [**Download Pico v1.0.0 (.zip)**](https://github.com/Ritolino/Pico/releases/download/v1.0.0/Pico-v1.0.0-macOS.zip) |

*Simply download the `.zip`, drag `Pico.app` into `/Applications`, and launch it. It automatically registers to launch at login with zero configuration.*

---

## ✨ Features

- **🔒 100% Private, Zero Telemetry & Zero Root**:
  - Operates completely offline with zero network sockets, zero analytics, and zero tracking.
  - Requires **no administrator privileges (`sudo`)**. Everything runs strictly in-process with standard user permissions.
- **⚡ Ultra-Lightweight (~15 MB RAM) & Zero CPU Idle (0.0%)**:
  - Maintains a physical memory footprint of just **~15 MB** (`phys_footprint`) — only ~3 MB above the bare macOS AppKit baseline (`12 MB`).
  - Consumes **0.0% CPU at rest**: a single coalesced timer ticking every `3.0 seconds` samples only 3 kernel counters.
  - **Zero Subprocesses**: Never spawns `top`, `ps`, `vm_stat`, `ioreg`, or `sysctl`. Eliminates CPU spikes, context switching, and battery drain.
- **📊 Three Dedicated Menu Bar Indicators (`NSStatusItem`)**:
  - Deterministically ordered from left to right: **CPU**, **GPU**, and **RAM**.
  - High-legibility two-line typography with prominent enlarged percentages (10.5 pt) and compact category labels (7.0 pt bold).
  - Perfectly optically centered with macOS system status icons (Battery, Wi-Fi, Control Center).
  - Single-instance dynamic template rendering (32 pt fixed width): eliminates horizontal jitter and reduces image backing stores from 11 MB to just 384 KB.
  - Native support for Light Mode, Dark Mode, and MacBook Pro notch displays.
- **🔍 On-Demand Subsystem Menus (Click to Inspect)**:
  - Attached directly flush against the menu bar (solving the macOS notch gap bug).
  - High-overhead queries activate **only** while a menu is open (`1.0 s` tick) and immediately deallocate upon closing:
    - **Total CPU Menu**: Total usage, per-cluster breakdown (**Super** & **Efficiency** cores on M5), individual core loads, average temperature, true silicon **Hotspot**, and real-time **System Power in Watts (`W`)**.
    - **GPU Menu**: Graphics engine utilization (`AGXAcceleratorG17G`), average temperature, and GPU Hotspot.
    - **RAM Menu**: Used Memory matching Activity Monitor's **Formula A** (`App + Wired + Compressed`), memory breakdown (`App`, `Wired`, `Compressed`, `Cached Files`, `Free`), and **Top 5 processes** by real memory footprint in MB scanned in < 2ms via zero-allocation C buffer.
- **🚀 Native macOS Launch-at-Login**:
  - Built-in integration with modern macOS Background Task Management (`SMAppService.mainApp`) on macOS 13+ (Ventura, Sonoma, Sequoia, Tahoe). No background daemons or helper plist clutter.
- **🎯 Activity Monitor Quick Shortcuts**:
  - Direct menu actions to open macOS Activity Monitor pre-navigated to CPU, Memory, or GPU History tabs.
- **🎨 Custom Renaissance Vector Identity ("The Gauge")**:
  - Handcrafted technical gauge design inspired by Leonardo da Vinci's scientific sketches, featuring Apple HIG squircle geometry and functional color sectors: Terracotta (CPU), Azzurro (GPU), and Salvia (RAM).

---

## 📊 Pico vs. Other macOS System Monitors

| Feature / Metric | 🍏 **Pico** | **MenuMeters** | **Stats** | **iStat Menus** |
| :--- | :--- | :--- | :--- | :--- |
| **Physical RAM Footprint** | **~15 MB** *(constant)* | ~30 – 60 MB | **~100 – 250 MB** *(scales with modules)* | **~150 – 300 MB** *(app + daemons)* |
| **Relative Memory Overhead** | **Baseline (0%)** | **+100% to +300%** *(2× to 4× larger)* | **+550% to +1,550%** *(6× to 16× larger)* | **+900% to +1,900%** *(10× to 20× larger)* |
| **Idle CPU Usage** | **0.0%** (3.0s coalesced) | 0.3% – 1.0% | 0.5% – 2.0% | 1.0% – 3.0% |
| **Subprocesses Spawned** | **0 (None)** | None | Spawns `ioreg`, `sysctl` | Background daemons |
| **Root (`sudo`) Required** | **No** | No | No | Yes (Privileged helper) |
| **UI Framework** | **Pure Native AppKit + C** | Legacy AppKit | SwiftUI + AppKit | AppKit + Daemons |
| **RAM Formula Accuracy** | **Activity Monitor Formula A** | Basic vm_stat | Total - Free (inaccurate) | Total - Free |
| **Apple Silicon Thermals & Watts** | **Per-core diodes & PSTR** | Basic | SMC sensors | Helper SMC |
| **Notch Display Margin Alignment** | **Flush (Zero Notch Gap Bugfix)** | Detached menu | Detached floating window | Detached menu |
| **Launch at Login Engine** | **Native `SMAppService`** | Legacy Login Items | Launch Agent | Helper Daemon |

*\*Real-world memory notes: Suites like Stats and iStat Menus grow rapidly from ~100 MB up to 250+ MB when thermal sensors, live graphs, and frequent sampling are enabled. Pico maintains a strictly constant ~15 MB footprint because it stores zero graph history buffers in memory and queries high-overhead sensors strictly while an NSMenu is open.*

---

## 🛠 System Requirements

| Specification | Requirement |
| :--- | :--- |
| **Operating System** | macOS 14.0 (Sonoma) or newer *(macOS 15 Sequoia / 27 Tahoe fully supported)* |
| **Hardware Architecture** | Apple Silicon only (`arm64` — M1, M2, M3, M4, M5, Pro, Max, Ultra) |
| **Memory Footprint** | `~15 MB` resident physical RAM |
| **Privileges** | Standard user permissions (Zero root / No `sudo`) |

---

## 💡 Frequently Asked Questions (FAQ)

### What makes Pico different from Stats or iStat Menus?
Most system monitors are feature-heavy suites with graph histories, animations, and network sniffers that consume 80–220 MB of RAM and constantly wake the CPU. Pico is designed for users who want clean, instant CPU, GPU, and RAM percentages in their menu bar with virtually zero resource cost (~15 MB RAM, 0.0% CPU) and zero battery impact.

### How does Pico calculate RAM usage accurately?
Pico implements Apple's exact Activity Monitor Formula A:
$$\text{Used Memory} = \text{App Memory} + \text{Wired Memory} + \text{Compressed Memory}$$
Many third-party tools subtract Free Memory from Total Memory, incorrectly counting cached disk files as "used memory" and leading users to believe their RAM is exhausted.

### Does Pico monitor CPU temperatures and wattage on Apple Silicon?
Yes. Clicking the CPU or GPU indicator queries hardware thermal diodes (including individual efficiency/performance cores and true silicon Hotspot) and total instantaneous system power in Watts (`PSTR`) via in-process Mach, IOKit, and AppleSMC calls, with zero subprocess overhead.

---

### 🎨 Visual Identity — "The Gauge"

<p align="center">
  <img src="assets/pico_gauge_multi_scale.png" width="720" alt="Pico Vector Gauge Icon Multi-Scale">
</p>

Designed as a Renaissance scientific instrument encapsulated in Apple HIG concentric squircle geometry:
- **Terracotta** (`#E28B58`): Top-left quadrant — CPU computation and thermal power.
- **Azzurro Polvere** (`#97ABB4`): Top-right quadrant — GPU graphics acceleration.
- **Verde Salvia** (`#A3AE8D`): Lower semicircle — RAM memory stability.
- Precision 45° technical radial diagonals across all sectors and a faceted needle set at 39.5°.

---

## 📖 Architecture & Benchmarks

For full technical documentation, empirical memory charts, and an honest analysis of design trade-offs:
👉 **[Read Benchmarks, Architecture & Engineering Design](docs/BENCHMARKS_AND_DESIGN.md)**

---

## 🛠 Compilation and Installation from Source

Requirements:
- macOS 13+ (Ventura, Sonoma, Sequoia, Tahoe / 27.2) on Apple Silicon.
- Command Line Tools (`clang` and `swiftc`). No full Xcode installation required.

```bash
# Clone the repository
git clone https://github.com/Ritolino/Pico.git
cd Pico

# Build and install directly into /Applications
./Scripts/install.sh
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
