import Foundation

struct CPUDetailedMetrics {
    let totalPercent: Int
    let totalExact: Double
    let efficiencyClusterName: String
    let efficiencyClusterPercent: Int
    let superClusterName: String
    let superClusterPercent: Int
    let corePercents: [Int]
}

final class CPUCollector {
    private var previousTicks = pico_cpu_ticks_t()
    private var hasBaseline = false

    let totalCores: Int
    let superCores: Int
    let efficiencyCores: Int
    let superName: String
    let efficiencyName: String

    init() {
        var topo = pico_hw_topology_t()
        _ = pico_read_hw_topology(&topo)

        self.totalCores = Int(topo.total_cores)
        self.superCores = Int(topo.perflevel0_cores)
        self.efficiencyCores = Int(topo.perflevel1_cores)
        self.superName = withUnsafePointer(to: &topo.perflevel0_name.0) { String(cString: $0) }
        self.efficiencyName = withUnsafePointer(to: &topo.perflevel1_name.0) { String(cString: $0) }

        if pico_read_cpu_ticks(&self.previousTicks) == 0 {
            self.hasBaseline = true
        }
    }

    /// Lettura ultra-leggera per la barra dei menu (zero allocazioni heap).
    func readTotalPercent() -> Int? {
        var current = pico_cpu_ticks_t()
        guard pico_read_cpu_ticks(&current) == 0, current.count > 0 else {
            return nil
        }

        if !hasBaseline {
            previousTicks = current
            hasBaseline = true
            return nil
        }

        var usage = pico_cpu_usage_t()
        let rc = pico_compute_cpu_delta(&previousTicks, &current, UInt32(efficiencyCores), &usage)
        previousTicks = current

        guard rc == 0 else { return nil }
        return Int(usage.total_percent)
    }

    /// Lettura dettagliata on-demand (solo a menu CPU aperto o in modalità --dump-metrics).
    /// Su Apple Silicon (incluso M5), gli indici 0..<efficiencyCores (0..5) sono i 6 core Efficiency
    /// e gli indici efficiencyCores..<totalCores (6..9) sono i 4 core Super.
    func readDetailed() -> CPUDetailedMetrics? {
        var current = pico_cpu_ticks_t()
        guard pico_read_cpu_ticks(&current) == 0, current.count > 0 else {
            return nil
        }

        if !hasBaseline {
            previousTicks = current
            hasBaseline = true
            return nil
        }

        var usage = pico_cpu_usage_t()
        let rc = pico_compute_cpu_delta(&previousTicks, &current, UInt32(efficiencyCores), &usage)
        previousTicks = current
        guard rc == 0 else { return nil }

        let count = Int(usage.count)
        var cores = [Int](repeating: 0, count: count)
        withUnsafePointer(to: &usage.core_percent.0) { basePtr in
            for i in 0..<count {
                cores[i] = Int(basePtr[i])
            }
        }

        return CPUDetailedMetrics(
            totalPercent: Int(usage.total_percent),
            totalExact: usage.total_exact,
            efficiencyClusterName: efficiencyName,
            efficiencyClusterPercent: Int(usage.first_group_percent),
            superClusterName: superName,
            superClusterPercent: Int(usage.second_group_percent),
            corePercents: cores
        )
    }
}
