import Foundation
import CoreGraphics

/// What a Space Lens item is. It decides the moon's color and what you can do with it.
enum LensKind: String, Sendable {
    case project       // a folder with .git or package.json
    case rebuildable   // node_modules, .next, build output… inside a repo: tools make it again
    case yourFiles     // documents, media, downloads, anything else you made
    case appData       // ~/Library and the dot folders in your home folder
    case other
}

/// One folder or file in Space Lens, measured.
struct LensNode: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let isDir: Bool
    var bytes: Int64
    var kind: LensKind
    /// Not measured: macOS protects it and SpawnSweep doesn't have Full Disk Access.
    var locked = false
}

/// Whether macOS lets SpawnSweep read everything. Checked without a prompt: the privacy database is only readable with
/// Full Disk Access. Without it, Space Lens skips the places macOS would ask about instead of asking folder by folder.
enum LensAccess {
    static var full: Bool { FileManager.default.isReadableFile(atPath: Shell.home + "/Library/Application Support/com.apple.TCC/TCC.db") }
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
