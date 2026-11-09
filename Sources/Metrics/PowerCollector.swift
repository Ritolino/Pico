import Foundation

final class PowerCollector {
    deinit {
        pico_release_smc()
    }

    func readSystemWatts() -> Double? {
        var raw = pico_power_t()
        guard pico_read_system_power(&raw) == 0, raw.available else {
            return nil
        }
        return Double(raw.system_watts)
    }

    func releaseResources() {
        pico_release_smc()
    }
}
