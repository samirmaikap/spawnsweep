import Foundation
import Darwin

/// One user process, read from `ps` and libproc.
struct Proc: Hashable {
    let pid: Int32
    let ppid: Int32
    let rssBytes: Int64
    let cpu: Double
    let elapsed: TimeInterval
    let command: String       // full argument string
    var exe: String           // executable path
    var name: String { (exe as NSString).lastPathComponent }
    var start: Double         // start time, seconds since 1970
}

/// A snapshot of every process owned by the current user, plus parent/child links.
final class ProcessTable {
    private(set) var procs: [Int32: Proc] = [:]
    private(set) var children: [Int32: [Int32]] = [:]

    init() {
        let uid = getuid()
        let r = Shell.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,uid=,rss=,%cpu=,etime=,command="], timeout: 10)
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard parts.count == 7,
                  let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let owner = UInt32(parts[2]), owner == uid,
                  let rss = Int64(parts[3]), let cpu = Double(parts[4]) else { continue }
            let elapsed = Self.parseElapsed(String(parts[5]))
            let command = String(parts[6])
            let exe = Self.exePath(pid) ?? String(command.split(separator: " ").first ?? "")
            let start = Self.startTime(pid) ?? Date().addingTimeInterval(-elapsed).timeIntervalSince1970
            procs[pid] = Proc(pid: pid, ppid: ppid, rssBytes: rss * 1024, cpu: cpu, elapsed: elapsed,
                              command: command, exe: exe, start: start)
            children[ppid, default: []].append(pid)
        }
    }

    subscript(pid: Int32) -> Proc? { procs[pid] }

    private var cwdCache: [Int32: String] = [:]

    /// Working folder of a process, cached for this snapshot.
    func cwd(_ pid: Int32) -> String? {
        if let c = cwdCache[pid] { return c.isEmpty ? nil : c }
        let c = Self.cwd(of: pid) ?? ""
        cwdCache[pid] = c
        return c.isEmpty ? nil : c
    }

    func descendants(of pid: Int32) -> [Int32] {
        var out: [Int32] = [], stack = children[pid] ?? []
        while let p = stack.popLast() {
            out.append(p)
            stack.append(contentsOf: children[p] ?? [])
        }
        return out
    }

    func ancestors(of pid: Int32) -> [Int32] {
        var out: [Int32] = [], cur = procs[pid]?.ppid ?? 0, guardCount = 0
        while cur > 1, let p = procs[cur], guardCount < 64 {
            out.append(cur)
            cur = p.ppid
            guardCount += 1
        }
        return out
    }

    func refs(_ pids: [Int32]) -> [ProcRef] { pids.compactMap { p in procs[p].map { ProcRef(pid: p, start: $0.start) } } }
    func memory(_ pids: [Int32]) -> Int64 { pids.reduce(0) { $0 + (procs[$1]?.rssBytes ?? 0) } }

    // MARK: libproc

    static func cwd(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    static func exePath(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    static func startTime(_ pid: Int32) -> Double? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
    }

    /// True when the pid still belongs to the process we saw (not a reused pid).
    static func isSame(_ ref: ProcRef) -> Bool {
        guard let s = startTime(ref.pid) else { return false }
        return abs(s - ref.start) < 1
    }

    /// `ps` elapsed format: [[dd-]hh:]mm:ss
    static func parseElapsed(_ s: String) -> TimeInterval {
        var days = 0.0, rest = Substring(s)
        if let dash = s.firstIndex(of: "-") {
            days = Double(s[..<dash]) ?? 0
            rest = s[s.index(after: dash)...]
        }
        let nums = rest.split(separator: ":").map { Double($0) ?? 0 }
        var secs = 0.0
        for n in nums { secs = secs * 60 + n }
        return days * 86400 + secs
    }

    // MARK: Listening ports

    /// Every TCP port the user's processes listen on, from lsof.
    static func listeners() -> [(pid: Int32, port: Int, host: String)] {
        let r = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", "\(getuid())", "-Fpn"], timeout: 15)
        var out: [(Int32, Int, String)] = [], pid: Int32 = 0, seen = Set<String>()
        for line in r.out.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) ?? 0 }
            else if line.hasPrefix("n"), let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                let host = String(line.dropFirst()[..<colon])
                if seen.insert("\(pid):\(port)").inserted { out.append((pid, port, host)) }
            }
        }
        return out
    }
}
