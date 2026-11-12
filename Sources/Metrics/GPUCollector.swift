import Foundation

struct GPUDetailedMetrics {
    let deviceUtilizationPercent: Int
    let rendererUtilizationPercent: Int?
    let tilerUtilizationPercent: Int?
    let inUseSystemMemoryMB: Int
    let allocSystemMemoryMB: Int
    let serviceClass: String
}

final class GPUCollector {
    init() {
        pico_prime_gpu_baseline()
    }

    deinit {
        pico_release_gpu_service()
    }

    /// Lettura ultra-leggera per la barra dei menu / hero GPU (GPUPH via IOReport con fallback AGX).
    func readTotalPercent() -> Int? {
        var pct: Int32 = -1
        guard pico_read_gpu_bar_percent(&pct) == 0, pct >= 0 else {
            return nil
        }
        return Int(pct)
    }

    /// Lettura dettagliata per menu GPU / validazione CLI.
    func readDetailed() -> GPUDetailedMetrics? {
        var raw = pico_gpu_raw_t()
        guard pico_read_gpu_raw(&raw) == 0, raw.available else {
            return nil
        }

        let serviceName = withUnsafePointer(to: &raw.service_class.0) { String(cString: $0) }
        let inUseMB = Int(raw.in_use_system_memory / (1024 * 1024))
        let allocMB = Int(raw.alloc_system_memory / (1024 * 1024))

        return GPUDetailedMetrics(
            deviceUtilizationPercent: Int(raw.device_utilization),
            rendererUtilizationPercent: raw.renderer_utilization >= 0 ? Int(raw.renderer_utilization) : nil,
            tilerUtilizationPercent: raw.tiler_utilization >= 0 ? Int(raw.tiler_utilization) : nil,
            inUseSystemMemoryMB: inUseMB,
            allocSystemMemoryMB: allocMB,
            serviceClass: serviceName
        )
    }
}
