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
        let effLabel = c.efficiencyClusterName.isEmpty ? "Efficiency" : c.efficiencyClusterName
        let supLabel = c.superClusterName.isEmpty ? "Performance" : c.superClusterName
        if cpu.efficiencyCores > 0 {
            let effRange = "0..\(cpu.efficiencyCores - 1)"
            print("\(effLabel) Cluster (core \(effRange)): \(c.efficiencyClusterPercent)%")
        }
        if cpu.superCores > 0 {
            let supRange = "\(cpu.efficiencyCores)..\(cpu.efficiencyCores + cpu.superCores - 1)"
            print("\(supLabel) Cluster (core \(supRange)): \(c.superClusterPercent)%")
        }
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
    print("Thermal State: \(thermal.readThermalStateLabel())")

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
        print("  - Cached Files:               \(formatGB(r.cachedFilesBytes))")
        print("  - Free:                       \(formatGB(r.freeBytes))")
        print("  - Swap Used:                  \(formatGB(r.swapUsedBytes))")
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

private func jsonVal<T>(_ value: T?) -> Any {
    return value ?? NSNull()
}

private func jsonDouble(_ value: Double?, decimals: Int = 2) -> Any {
    guard let value, value.isFinite else { return NSNull() }
    let formatted = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    return NSDecimalNumber(string: formatted, locale: Locale(identifier: "en_US_POSIX"))
}

private func runDumpJSON() {
    var topo = pico_hw_topology_t()
    _ = pico_read_hw_topology(&topo)
    let chipBrand = withUnsafePointer(to: &topo.brand.0) { String(cString: $0) }

    let cpu = CPUCollector()
    let gpu = GPUCollector()
    let ram = RAMCollector()
    let thermal = ThermalCollector()
    let power = PowerCollector()
    let proc = ProcessCollector()

    // Brief wait (500 ms) only in CLI diagnostic mode for a valid CPU tick delta
    usleep(500_000)

    let cpuDetails = cpu.readDetailed()
    let cpuTherm = thermal.readCPUThermal()
    let sysWatts = power.readSystemWatts()
    let gpuDetails = gpu.readDetailed()
    let gpuTherm = thermal.readGPUThermal()
    let ramDetails = ram.readDetailed()
    let topProcs = proc.readTopProcesses()

    let hardwareDict: [String: Any] = [
        "chip": chipBrand,
        "total_cores": Int(topo.total_cores),
        "perf_cluster_name": cpu.superName,
        "perf_cores": cpu.superCores,
        "efficiency_cluster_name": cpu.efficiencyName,
        "efficiency_cores": cpu.efficiencyCores,
        "memory_bytes": topo.memsize_bytes
    ]

    let cpuDict: [String: Any] = [
        "total_percent": jsonVal(cpuDetails?.totalPercent),
        "total_exact": jsonDouble(cpuDetails?.totalExact, decimals: 2),
        "efficiency_cluster_percent": jsonVal(cpuDetails?.efficiencyClusterPercent),
        "perf_cluster_percent": jsonVal(cpuDetails?.superClusterPercent),
        "cores_percent": cpuDetails?.corePercents ?? [],
        "temp_avg_c": jsonDouble(cpuTherm?.averageCelsius, decimals: 1),
        "temp_hotspot_c": jsonDouble(cpuTherm?.hotspotCelsius, decimals: 1),
        "thermal_state": thermal.readThermalStateLabel().lowercased(),
        "system_power_watts": jsonDouble(sysWatts, decimals: 2)
    ]

    let gpuDict: [String: Any] = [
        "service_class": jsonVal(gpuDetails?.serviceClass),
        "utilization_percent": jsonVal(gpuDetails?.deviceUtilizationPercent),
        "renderer_percent": jsonVal(gpuDetails?.rendererUtilizationPercent),
        "tiler_percent": jsonVal(gpuDetails?.tilerUtilizationPercent),
        "vram_in_use_mb": jsonVal(gpuDetails?.inUseSystemMemoryMB),
        "vram_alloc_mb": jsonVal(gpuDetails?.allocSystemMemoryMB),
        "temp_avg_c": jsonDouble(gpuTherm?.averageCelsius, decimals: 1),
        "temp_hotspot_c": jsonDouble(gpuTherm?.hotspotCelsius, decimals: 1)
    ]

    let ramDict: [String: Any] = [
        "total_bytes": jsonVal(ramDetails?.totalBytes),
        "used_bytes": jsonVal(ramDetails?.usedBytes),
        "used_percent": jsonVal(ramDetails?.usedPercent),
        "app_bytes": jsonVal(ramDetails?.appBytes),
        "wired_bytes": jsonVal(ramDetails?.wiredBytes),
        "compressed_bytes": jsonVal(ramDetails?.compressedBytes),
        "cached_files_bytes": jsonVal(ramDetails?.cachedFilesBytes),
        "free_bytes": jsonVal(ramDetails?.freeBytes),
        "swap_used_bytes": jsonVal(ramDetails?.swapUsedBytes),
        "swap_total_bytes": jsonVal(ramDetails?.swapTotalBytes)
    ]

    let procsArray: [[String: Any]] = topProcs.map { p in
        [
            "pid": p.pid,
            "name": p.name,
            "footprint_bytes": p.footprintBytes,
            "footprint_mb": jsonDouble(p.footprintMB, decimals: 1)
        ]
    }

    let root: [String: Any] = [
        "hardware": hardwareDict,
        "cpu": cpuDict,
        "gpu": gpuDict,
        "ram": ramDict,
        "top_processes": procsArray
    ]

    if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    } else {
        fputs("{\"error\":\"json_serialization_failed\"}\n", stderr)
        exit(1)
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
    if args.contains("--json") {
        runDumpJSON()
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
