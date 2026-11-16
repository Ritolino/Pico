import Foundation

struct ThermalReading {
    let averageCelsius: Double
    let hotspotCelsius: Double
}

struct FanReading {
    let fanCount: Int
    let rpm: [Int]

    var formattedLabel: String {
        guard !rpm.isEmpty else { return "N/A" }
        if rpm.count == 1 {
            return "\(rpm[0]) RPM"
        }
        return rpm.map(String.init).joined(separator: " / ") + " RPM"
    }
}

final class ThermalCollector {
    deinit {
        pico_release_smc()
    }

    func readCPUThermal() -> ThermalReading? {
        var raw = pico_thermal_t()
        guard pico_read_cpu_thermal(&raw) == 0, raw.available else {
            return nil
        }
        return ThermalReading(
            averageCelsius: Double(raw.avg_temp_c),
            hotspotCelsius: Double(raw.hotspot_temp_c)
        )
    }

    func readGPUThermal() -> ThermalReading? {
        var raw = pico_thermal_t()
        guard pico_read_gpu_thermal(&raw) == 0, raw.available else {
            return nil
        }
        return ThermalReading(
            averageCelsius: Double(raw.avg_temp_c),
            hotspotCelsius: Double(raw.hotspot_temp_c)
        )
    }

    /// Stato termico di sistema pubblico Apple (M1–M5+ senza API private, zero costi a riposo).
    /// Mappa la scala di sistema ad una nomenclatura coerente (Normal, Warning, Critical).
    func readThermalStateLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "Normal"
        case .fair, .serious:
            return "Warning"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }

    func readFanSpeed() -> FanReading? {
        var raw = pico_fan_t()
        guard pico_read_fan_speed(&raw) == 0, raw.available, raw.fan_count > 0 else {
            return nil
        }
        var rpms: [Int] = []
        let rawTuple = (raw.rpm.0, raw.rpm.1, raw.rpm.2, raw.rpm.3)
        let values = [rawTuple.0, rawTuple.1, rawTuple.2, rawTuple.3]
        for i in 0..<min(Int(raw.fan_count), 4) {
            if values[i] >= 0.0 {
                rpms.append(Int(values[i].rounded()))
            }
        }
        guard !rpms.isEmpty else { return nil }
        return FanReading(fanCount: Int(raw.fan_count), rpm: rpms)
    }

    func releaseResources() {
        pico_release_smc()
    }
}
