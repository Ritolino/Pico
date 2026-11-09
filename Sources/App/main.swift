import AppKit
import Foundation

private func formatGB(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
    return String(format: "%.2f GB", gb)
}

private func printHardwareSummary() {
    var buffer = [CChar](repeating: 0, count: 256)
    let status = pico_cshim_hw_summary(&buffer, buffer.count)
    if status == 0 {
        let summary = String(cString: buffer)
        print("Pico [OK] — \(summary)")
    } else {
        print("Pico [ERROR] — Unable to read hardware summary via CShim")
        exit(1)
    }
}

private func runDumpMetrics() {
    printHardwareSummary()
    let cpu = CPUCollector()
    let gpu = GPUCollector()
    let ram = RAMCollector()
    let thermal = ThermalCollector()
    let power = PowerCollector()

    // Brief wait (500 ms) via usleep only in CLI diagnostic mode for a valid CPU tick delta
    usleep(500_000)

    print("\n--- [CPU Metrics & Details] ---")
    if let c = cpu.readDetailed() {
        print(String(format: "Total CPU: %d%% (exact: %.2f%%)", c.totalPercent, c.totalExact))
        print("Efficiency Cluster (core 0..5 - \(c.efficiencyClusterName)): \(c.efficiencyClusterPercent)%")
        print("Super Cluster      (core 6..9 - \(c.superClusterName)): \(c.superClusterPercent)%")
        let coresStr = c.corePercents.enumerated().map { "Core\($0.offset): \($0.element)%" }.joined(separator: " | ")
        print("Per-Core: \(coresStr)")
    } else {
        print("CPU: N/A")
    }

    if let t = thermal.readCPUThermal() {
        print(String(format: "Average CPU Temperature: %.1f °C | CPU Hotspot: %.1f °C", t.averageCelsius, t.hotspotCelsius))
    } else {
        print("CPU Temperature: N/A")
    }

    if let w = power.readSystemWatts() {
        print(String(format: "Total System Power (PSTR): %.2f W", w))
    } else {
        print("Total System Power: N/A")
    }

    print("\n--- [GPU Metrics & Details] ---")
    if let g = gpu.readDetailed() {
        print("IOKit Service: \(g.serviceClass)")
        print("Device Utilization: \(g.deviceUtilizationPercent)%")
        print("Renderer Utilization: \(g.rendererUtilizationPercent.map { "\($0)%" } ?? "N/A")")
        print("Tiler Utilization: \(g.tilerUtilizationPercent.map { "\($0)%" } ?? "N/A")")
        print("VRAM In Use / Alloc: \(g.inUseSystemMemoryMB) MB / \(g.allocSystemMemoryMB) MB")
    } else {
        print("GPU: N/A")
    }

    if let t = thermal.readGPUThermal() {
        print(String(format: "Average GPU Temperature: %.1f °C | GPU Hotspot: %.1f °C", t.averageCelsius, t.hotspotCelsius))
    } else {
        print("GPU Temperature: N/A")
    }

    print("\n--- [RAM Metrics & Top Processes] ---")
    if let r = ram.readDetailed() {
        print("Total RAM: \(formatGB(r.totalBytes))")
        print("Formula A (Activity Monitor: App + Wired + Compressed): \(formatGB(r.usedBytes)) (\(r.usedPercent)%)")
        print("  - App (internal - purgeable): \(formatGB(r.appBytes))")
        print("  - Wired:                      \(formatGB(r.wiredBytes))")
        print("  - Compressed:                 \(formatGB(r.compressedBytes))")
        print("  - Cached Files (reclaimable): \(formatGB(r.cachedFilesBytes))")
        print("  - Free:                       \(formatGB(r.freeBytes))")
        print("Formula B (active - purgeable + wired + compr):         \(formatGB(r.formulaBUsedBytes)) (\(r.formulaBPercent)%)")
        print("Formula C (total - free, top-style):                    \(formatGB(r.formulaCUsedBytes)) (\(r.formulaCPercent)%)")
    } else {
        print("RAM: N/A")
    }

    let proc = ProcessCollector()
    let top = proc.readTopProcesses()
    print("\nTop 5 Processes (phys_footprint via libproc):")
    for (idx, p) in top.enumerated() {
        let padName = p.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        print(String(format: "  %d. [PID %d] %@: %.1f MB", idx + 1, p.pid, padName, p.footprintMB))
    }
}

private func getSelfFootprintKB() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    return UInt64(info.phys_footprint) / 1024
}

private func runStressMenus(iterations: Int) {
    let cpu = CPUCollector()
    let gpu = GPUCollector()
    let ram = RAMCollector()
    let controller = MenuController(cpu: cpu, gpu: gpu, ram: ram)

    // Warm-up
    autoreleasepool {
        controller.menuWillOpen(controller.cpuMenu)
        controller.menuDidClose(controller.cpuMenu)
        controller.menuWillOpen(controller.gpuMenu)
        controller.menuDidClose(controller.gpuMenu)
        controller.menuWillOpen(controller.ramMenu)
        controller.menuDidClose(controller.ramMenu)
    }

    let beforeKB = getSelfFootprintKB()

    for _ in 0..<iterations {
        autoreleasepool {
            controller.menuWillOpen(controller.cpuMenu)
            controller.updateCPUMenu()
            controller.menuDidClose(controller.cpuMenu)

            controller.menuWillOpen(controller.gpuMenu)
            controller.updateGPUMenu()
            controller.menuDidClose(controller.gpuMenu)

            controller.menuWillOpen(controller.ramMenu)
            controller.updateRAMMenu()
            controller.menuDidClose(controller.ramMenu)
        }
    }

    let afterKB = getSelfFootprintKB()
    let deltaKB = Int64(afterKB) - Int64(beforeKB)
    print("Pico [TEST-06: Stress Test \(iterations) cycles of CPU, GPU & RAM menu opening/closing]")
    print("phys_footprint before: \(beforeKB) KB | after: \(afterKB) KB | delta: \(deltaKB) KB")
}

autoreleasepool {
    let args = CommandLine.arguments
    if args.contains("--verify-build") {
        printHardwareSummary()
        exit(0)
    }
    if args.contains("--dump-metrics") {
        runDumpMetrics()
        exit(0)
    }
    if let idx = args.firstIndex(of: "--stress-menus") {
        let count = (idx + 1 < args.count) ? (Int(args[idx + 1]) ?? 50) : 50
        runStressMenus(iterations: count)
        exit(0)
    }
    if args.contains("--test-login-item") {
        print("Pico [SMAppService Diagnostic]")
        print("Bundle Path:", Bundle.main.bundleURL.path)
        print("Bundle ID:  ", Bundle.main.bundleIdentifier ?? "nil")
        let status = LoginItemManager.status
        print("Login Item: ", LoginItemManager.statusDescription(status))
        exit(0)
    }
    if args.contains("--toggle-login-item") {
        print("Initial Status: ", LoginItemManager.statusDescription(LoginItemManager.status))
        let afterToggle = LoginItemManager.toggle()
        print("Toggled State:  ", afterToggle, "->", LoginItemManager.statusDescription(LoginItemManager.status))
        // Revert back if needed or let the caller decide
        exit(0)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
