import Foundation
import Darwin

// CONTRACT (other files rely on these names): VolumeStats, MemoryStats, AppMemory, SystemMonitor.volume/.memory/.topApps/refresh().

/// The startup volume. `free` counts purgeable space, as Finder does.
struct VolumeStats {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 { max(0, total - free) }
}

/// Memory as Activity Monitor reports it: used = app + wired + compressed.
struct MemoryStats {
    enum Pressure { case normal, warning, critical }
    var total: Int64 = 0
    var used: Int64 = 0
    var app: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    var cached: Int64 = 0
    var swapUsed: Int64 = 0
    var pressure = Pressure.normal
}

struct AppMemory: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let bytes: Int64
    let bundleID: String?
}

/// Disk and memory for the whole Mac. AppModel calls `refresh()` on every scan tick (8 s), so it must stay cheap.
@MainActor @Observable
final class SystemMonitor {
    var volume = VolumeStats()
    var memory = MemoryStats()
    var topApps: [AppMemory] = []

    @ObservationIgnored private var lastSlow = Date.distantPast
    private let host = mach_host_self()

    func refresh() {
        memory = readMemory()
        // ponytail: disk free (may ask CacheDelete about purgeable space) and `ps` are the slow parts,
        // so they run off the main thread at most every 30 s (about every 4th tick).
        guard Date().timeIntervalSince(lastSlow) > 30 else { return }
        lastSlow = Date()
        Task { [weak self] in
            let (v, apps) = await Task.detached(priority: .utility) { (Self.readVolume(), Self.readTopApps()) }.value
            self?.volume = v
            self?.topApps = apps
        }
    }

    /// Mach VM counters, sorted the way Activity Monitor does. Microseconds, so fine on the main thread.
    private func readMemory() -> MemoryStats {
        var m = MemoryStats(total: Int64(ProcessInfo.processInfo.physicalMemory))
        var s = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            m.app = max(0, Int64(s.internal_page_count) - Int64(s.purgeable_count)) * page
            m.wired = Int64(s.wire_count) * page
            m.compressed = Int64(s.compressor_page_count) * page
            m.cached = (Int64(s.external_page_count) + Int64(s.purgeable_count)) * page
            m.used = m.app + m.wired + m.compressed
        }
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            m.pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { m.swapUsed = Int64(swap.xsu_used) }
        return m
    }

    nonisolated static func readVolume() -> VolumeStats {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return VolumeStats(total: Int64(v?.volumeTotalCapacity ?? 0), free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Resident memory per app, with helpers folded into the .app bundle they live in.
    nonisolated static func readTopApps(limit: Int = 6) -> [AppMemory] {
        let r = Shell.run("ps", ["-axo", "rss=,comm="], timeout: 5)
        return r.ok ? group(psOutput: r.out, limit: limit) : []
    }

    /// "  1234 /Applications/X.app/Contents/Frameworks/X Helper.app/…" → X. The outermost .app wins.
    nonisolated static func group(psOutput: String, limit: Int) -> [AppMemory] {
        var bytes: [String: Int64] = [:], bundles: [String: String] = [:]
        for line in psOutput.split(separator: "\n") {
            let t = line.drop { $0 == " " }
            guard let sp = t.firstIndex(of: " "), let kb = Int64(t[..<sp]), kb > 0 else { continue }
            let path = String(t[t.index(after: sp)...])
            var name = (path as NSString).lastPathComponent
            if let app = path.range(of: ".app/") {
                let bundle = String(path[..<app.lowerBound]) + ".app"
                name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
                bundles[name] = bundle
            }
            bytes[name, default: 0] += kb * 1024
        }
        return bytes.sorted { $0.value > $1.value }.prefix(limit).map { name, b in
            AppMemory(name: name, bytes: b, bundleID: bundles[name].flatMap { Bundle(path: $0)?.bundleIdentifier })
        }
    }
}
