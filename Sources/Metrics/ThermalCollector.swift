import Foundation

struct ThermalReading {
    let averageCelsius: Double
    let hotspotCelsius: Double
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

    func releaseResources() {
        pico_release_smc()
    }
}
