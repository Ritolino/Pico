import Foundation

struct ProcessInfoItem {
    let pid: Int32
    let name: String
    let footprintBytes: UInt64
    var footprintMB: Double {
        return Double(footprintBytes) / (1024.0 * 1024.0)
    }
}

final class ProcessCollector {
    func readTopProcesses() -> [ProcessInfoItem] {
        var raw = pico_top_processes_t()
        guard pico_read_top_processes(&raw) == 0 else {
            return []
        }
        var result = [ProcessInfoItem]()
        result.reserveCapacity(Int(raw.count))

        for i in 0..<Int(raw.count) {
            let pid = pico_get_top_process_pid(&raw, Int32(i))
            let fp = pico_get_top_process_footprint(&raw, Int32(i))
            let name: String
            if let cStr = pico_get_top_process_name(&raw, Int32(i)) {
                name = String(cString: cStr)
            } else {
                name = "PID \(pid)"
            }
            result.append(ProcessInfoItem(
                pid: pid,
                name: name.isEmpty ? "PID \(pid)" : name,
                footprintBytes: fp
            ))
        }
        return result
    }
}
