import Foundation
import CoreGraphics

/// What a Space Lens item is. It decides the moon's color and what you can do with it.
enum LensKind: String, Sendable {
    case project       // a folder with .git or package.json
    case rebuildable   // node_modules, .next, build output inside a repo, and known tool caches: tools make it again
    case yourFiles     // documents, media, downloads, anything else you made
    case appData       // ~/Library and the dot folders in your home folder
    case apps          // /Applications
    case system        // macOS and shared system folders
    case unmeasured    // space the disk uses that no folder accounts for: snapshots, purgeable, hidden system data
    case other
}

/// The whole disk, measured once: folder sizes as far down as the scan went, which folders were skipped, and how
/// full the disk is. Browsing reads from here, so it's instant; deeper folders are measured when opened.
struct LensMap: Sendable {
    var sizes: [String: Int64] = [:]
    var children: [String: [String]] = [:]
    var locked: Set<String> = []
    var diskTotal: Int64 = 0
    var diskUsed: Int64 = 0
    var cancelled = false

    /// Size and used space of the volume holding `root`, as Finder counts it.
    static func diskUsage(_ root: String) -> (total: Int64, used: Int64)? {
        guard let v = try? URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacity else { return nil }
        return (Int64(total), Int64(total - free))
    }

    /// Fills `children` from `sizes`; call once after the scan.
    mutating func index() {
        children = [:]
        for path in sizes.keys where path != "/" {
            children[(path as NSString).deletingLastPathComponent, default: []].append(path)
        }
    }


    /// After something goes to the Trash: it disappears and every folder above it shrinks by its size.
    mutating func remove(_ path: String, bytes: Int64) {
        for key in sizes.keys where key == path || key.hasPrefix(path + "/") { sizes[key] = nil }
        var dir = (path as NSString).deletingLastPathComponent
        while true {
            if let s = sizes[dir] { sizes[dir] = max(0, s - bytes) }
            if dir == "/" || dir.isEmpty { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        let parent = (path as NSString).deletingLastPathComponent
        children[parent]?.removeAll { $0 == path }
        diskUsed = max(0, diskUsed - bytes)
    }
}

/// What the scan is doing right now, for the scanning screen.
struct LensProgress: Sendable {
    var path = ""
    var bytes: Int64 = 0
    var fraction = 0.0
}

/// Stops a running scan: no new folders start, and the `du` processes already running are ended.
final class LensScan: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var running: [Process] = []

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Registers a process to end on cancel. False (and the process is ended) if the scan was already cancelled.
    func track(_ p: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        running.append(p)
        return true
    }

    func cancel() {
        lock.lock(); cancelled = true; let ps = running; running = []; lock.unlock()
        for p in ps where p.isRunning { p.terminate() }
    }
}

/// One folder or file in Space Lens, measured.
struct LensNode: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    var name: String
    let isDir: Bool
    var bytes: Int64
    var kind: LensKind
    /// Not measured: macOS protects it and SpawnSweep doesn't have Full Disk Access.
    var locked = false
}

/// Whether macOS lets SpawnSweep read everything. Checked without a prompt: the privacy database is only readable with
/// Full Disk Access. Without it, Space Lens skips the places macOS would ask about instead of asking folder by folder.
enum LensAccess {
    /// Readable only with Full Disk Access, so reading it asks nothing and tells us whether we have it.
    static let probe = Shell.home + "/Library/Application Support/com.apple.TCC/TCC.db"
    static var full: Bool { FileManager.default.isReadableFile(atPath: probe) }
    static let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

/// One folder level, ready to draw: the biggest items as moons (the rest folded into one "N smaller" moon) and where
/// each sits. Packed once when a level finishes measuring, so hovering and redrawing never repack.
struct LensLayout: Sendable {
    static let maxMoons = 22
    let moons: [LensNode]
    let radii: [CGFloat]
    let points: [CGPoint]
    let bounds: CGRect

    static func smallerPath(_ folder: String) -> String { folder + "/\u{0}smaller" }

    init(folder: String, nodes: [LensNode]) {
        let all = nodes.filter { $0.bytes > 0 }
        var shown = Array(all.prefix(Self.maxMoons))
        if all.count > Self.maxMoons {
            let rest = all.dropFirst(Self.maxMoons)
            shown.append(LensNode(path: Self.smallerPath(folder), name: "\(rest.count) smaller", isDir: false,
                                  bytes: rest.reduce(0) { $0 + $1.bytes }, kind: .other))
        }
        moons = shown
        radii = shown.map { CGFloat(Double($0.bytes).squareRoot()) }
        let gap: CGFloat = 5 * (radii.first ?? 120) / 120   // about 5 points once scaled to the panel
        points = Pack.positions(radii, gap: gap)
        let xs = zip(points, radii).flatMap { [$0.x - $1, $0.x + $1] }, ys = zip(points, radii).flatMap { [$0.y - $1, $0.y + $1] }
        bounds = xs.isEmpty ? .zero : CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

/// Greedy circle packing: biggest first at the center, each next circle touching the cluster as close to the middle
/// as it fits. ponytail: O(n² · 120) tries; fine for the ≤23 moons Space Lens shows, front-chain packing if that grows.
enum Pack {
    static func positions(_ radii: [CGFloat], gap: CGFloat) -> [CGPoint] {
        var placed: [(c: CGPoint, r: CGFloat)] = []
        for r in radii {
            if placed.isEmpty { placed.append((.zero, r)); continue }
            var best = CGPoint.zero, bestD = CGFloat.infinity
            for p0 in placed {
                for k in 0..<120 {
                    let a = Double(k) / 120 * 2 * .pi, d = p0.r + r + gap
                    let p = CGPoint(x: p0.c.x + d * cos(a), y: p0.c.y + d * sin(a))
                    guard placed.allSatisfy({ hypot($0.c.x - p.x, $0.c.y - p.y) >= $0.r + r + gap - 0.01 }) else { continue }
                    let dist = hypot(p.x * 0.8, p.y)   // a little wider than tall, like the panel
                    if dist < bestD { bestD = dist; best = p }
                }
            }
            placed.append((best, r))
        }
        return placed.map(\.c)
    }
}
