import Foundation

struct RAMDetailedMetrics {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedFilesBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let usedPercent: Int
    let pressureLabel: String

    // Formule alternative per confronto e validazione empirica (Fase 2)
    let formulaBUsedBytes: UInt64
    let formulaBPercent: Int
    let formulaCUsedBytes: UInt64
    let formulaCPercent: Int
}

final class RAMCollector {
    /// Lettura ultra-leggera per la barra dei menu (Formula A — Activity Monitor).
    func readTotalPercent() -> Int? {
        var raw = pico_ram_raw_t()
        guard pico_read_ram_raw(&raw) == 0, raw.available, raw.total_bytes > 0 else {
            return nil
        }

        let appPages = raw.internal_pages > raw.purgeable_pages
            ? (raw.internal_pages - raw.purgeable_pages)
            : 0
        let usedPages = appPages &+ raw.wire_pages &+ raw.compressor_pages
        let usedBytes = usedPages &* raw.page_size

        let pct = (Double(usedBytes) / Double(raw.total_bytes)) * 100.0
        return min(100, max(0, Int(pct.rounded())))
    }

    /// Livello di pressione memoria di sistema (Activity Monitor / XNU Jetsam).
    /// Mappa la sysctl kern.memorystatus_vm_pressure_level: 1 -> Normal, 2 -> Warning, 4 -> Critical.
    func readPressureLabel() -> String {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return "N/A"
        }
        switch level {
        case 1:
            return "Normal"
        case 2:
            return "Warning"
        case 4:
            return "Critical"
        default:
            return "N/A"
        }
    }

    /// Lettura completa con scomposizione App / Wired / Compressa e formule candidate.
    func readDetailed() -> RAMDetailedMetrics? {
        var raw = pico_ram_raw_t()
        guard pico_read_ram_raw(&raw) == 0, raw.available, raw.total_bytes > 0 else {
            return nil
        }

        let pageSize = raw.page_size

        // Formula A (Ufficiale XNU / Activity Monitor):
        // App = internal - purgeable; Used = App + Wired + Compressed
        let appPages = raw.internal_pages > raw.purgeable_pages
            ? (raw.internal_pages - raw.purgeable_pages)
            : 0
        let appBytes = appPages &* pageSize
        let wiredBytes = raw.wire_pages &* pageSize
        let compressedBytes = raw.compressor_pages &* pageSize
        let usedBytes = appBytes &+ wiredBytes &+ compressedBytes
        let cachedBytes = (raw.external_pages &+ raw.purgeable_pages) &* pageSize
        let freeBytes = raw.free_pages &* pageSize
        let usedPct = min(100, max(0, Int(((Double(usedBytes) / Double(raw.total_bytes)) * 100.0).rounded())))

        // Formula B (Alternativa "active + wired + compressed - purgeable"):
        let activeMinusPurgeable = raw.active_pages > raw.purgeable_pages
            ? (raw.active_pages - raw.purgeable_pages)
            : 0
        let formulaBPages = activeMinusPurgeable &+ raw.wire_pages &+ raw.compressor_pages
        let formulaBBytes = formulaBPages &* pageSize
        let formulaBPct = min(100, max(0, Int(((Double(formulaBBytes) / Double(raw.total_bytes)) * 100.0).rounded())))

        // Formula C (Alternativa grezza estilo top: "total - free"):
        let formulaCBytes = raw.total_bytes > freeBytes ? (raw.total_bytes - freeBytes) : 0
        let formulaCPct = min(100, max(0, Int(((Double(formulaCBytes) / Double(raw.total_bytes)) * 100.0).rounded())))

        return RAMDetailedMetrics(
            totalBytes: raw.total_bytes,
            usedBytes: usedBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedFilesBytes: cachedBytes,
            freeBytes: freeBytes,
            swapUsedBytes: raw.swap_used_bytes,
            swapTotalBytes: raw.swap_total_bytes,
            usedPercent: usedPct,
            pressureLabel: readPressureLabel(),
            formulaBUsedBytes: formulaBBytes,
            formulaBPercent: formulaBPct,
            formulaCUsedBytes: formulaCBytes,
            formulaCPercent: formulaCPct
        )
    }

    static func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.2f GB", gb)
    }

    static func formatSwap(_ bytes: UInt64) -> String {
        if bytes < 1024 * 1024 {
            return "0.00 GB"
        }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb < 1023.5 {
            return String(format: "%.0f MB", mb)
        }
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.2f GB", gb)
    }
}
