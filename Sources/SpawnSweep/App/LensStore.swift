import SwiftUI
import AppKit

/// Space Lens state. The whole disk is measured once into `map`; after that, browsing reads each folder from it.
/// Contents and "can't tick" reasons are worked out off the main thread, so hovering and redrawing stay cheap.
@Observable @MainActor
final class LensStore {
    enum Phase { case idle, scanning, ready }

    var phase: Phase = .idle
    var map: LensMap?
    var progress = LensProgress()
    var stoppedEarly = false
    var stack: [String] = ["/"]
    var forward: [String] = []
    var levels: [String: [LensNode]] = [:]
    var layouts: [String: LensLayout] = [:]
    var loading: Set<String> = []
    /// Ticked for removal, by path.
    var checked: [String: LensNode] = [:]
    /// Why an item can't be ticked, by path. Items with no entry can be.
    var refusals: [String: String] = [:]
    var hovered: String?
    /// Space Lens only scans with Full Disk Access. Rechecked whenever SpawnSweep comes back to the front.
    var hasAccess = LensAccess.full
    /// When this scan began, and how much of the disk is in use, for the time and percent tiles while it runs.
    var startedAt = Date()
    var diskUsed: Int64 = 0

    private var scan: LensScan?
    private var generation = 0

    var current: String { stack.last ?? "/" }
    var checkedBytes: Int64 { checked.values.reduce(0) { $0 + $1.bytes } }

    func refreshAccess() { hasAccess = LensAccess.full }

    /// How far the scan is, by bytes measured against the disk's used space. Capped below 1 because snapshots
    /// and purgeable space are in use but never measured.
    var done: Double { diskUsed > 0 ? min(0.99, Double(progress.bytes) / Double(diskUsed)) : progress.fraction }

    /// Opens Full Disk Access in System Settings. Trying the protected file first is what makes macOS list
    /// SpawnSweep there with its switch off, ready to turn on.
    func requestAccess() {
        _ = FileHandle(forReadingAtPath: LensAccess.probe)
        NSWorkspace.shared.open(LensAccess.settings)
    }

    func start() {
        refreshAccess()
        guard hasAccess else { requestAccess(); return }
        guard Edition.hasPro, phase != .scanning else { return }
        generation += 1
        let gen = generation, s = LensScan()
        scan = s
        phase = .scanning; progress = LensProgress(); stoppedEarly = false
        startedAt = Date(); diskUsed = LensMap.diskUsage("/")?.used ?? 0
        map = nil; levels = [:]; layouts = [:]; loading = []; checked = [:]; refusals = [:]; stack = ["/"]; forward = []; hovered = nil
        Task.detached {
            let m = Edition.pro?.lensMap(scan: s) { p in
                Task { @MainActor in if self.generation == gen && self.phase == .scanning { self.progress = p } }
            }
            await MainActor.run {
                guard self.generation == gen else { return }
                if let m, !m.cancelled {
                    self.map = m; self.phase = .ready; self.load("/")
                } else {
                    self.phase = .idle; self.stoppedEarly = true
                }
            }
        }
    }

    /// Stop: running measurements end at once and the screen goes back to the start.
    func stop() {
        scan?.cancel()
        generation += 1
        phase = .idle; stoppedEarly = true
    }

    func open(_ path: String) { stack.append(path); forward = []; hovered = nil; load(path) }
    func back() { guard stack.count > 1 else { return }; forward.append(stack.removeLast()); hovered = nil; load(current) }
    func goForward() { guard let next = forward.popLast() else { return }; stack.append(next); hovered = nil; load(next) }
    func up(to index: Int) {
        guard index < stack.count - 1 else { return }
        stack = Array(stack.prefix(index + 1)); forward = []; hovered = nil; load(current)
    }

    func toggle(_ n: LensNode) {
        guard refusals[n.path] == nil, levels[current]?.contains(where: { $0.path == n.path }) == true else { return }
        if checked[n.path] == nil { checked[n.path] = n } else { checked[n.path] = nil }
    }

    func load(_ path: String) {
        guard let map, levels[path] == nil, !loading.contains(path) else { return }
        loading.insert(path)
        let gen = generation, s = scan ?? LensScan()
        Task.detached {
            let nodes = Edition.pro?.lensLevel(path, map: map, scan: s) ?? []
            let layout = LensLayout(folder: path, nodes: nodes)
            let reasons = Dictionary(nodes.compactMap { n in Self.refusal(n, map: map).map { (n.path, $0) } }, uniquingKeysWith: { a, _ in a })
            await MainActor.run {
                guard self.generation == gen else { return }
                self.levels[path] = nodes; self.layouts[path] = layout
                self.refusals.merge(reasons) { $1 }
                self.loading.remove(path)
            }
        }
    }

    /// Why `n` can't be ticked, or nil. Remove checks all of this again, plus what's running, right before it acts.
    nonisolated static func refusal(_ n: LensNode, map: LensMap) -> String? {
        if n.kind == .unmeasured { return "macOS keeps this for snapshots and purgeable data, and frees it on its own when space runs low." }
        if n.locked { return "SpawnSweep needs Full Disk Access to look inside." }
        if let why = Actions.trashRefusal(n.path, busy: []) { return why }
        if n.isDir && map.containsRepo(n.path) { return "It holds git repositories. Open it and remove only what's safe to clear." }
        return nil
    }

    /// After Remove: what really went to the Trash leaves the map, the lists and the moons, and folder totals shrink.
    func removed(_ nodes: [LensNode]) {
        for n in nodes {
            map?.remove(n.path, bytes: n.bytes)
            checked[n.path] = nil
            for key in levels.keys where levels[key]?.contains(where: { $0.path == n.path }) == true {
                levels[key]?.removeAll { $0.path == n.path }
            }
        }
        // Folder sizes changed up the tree, so every level shown so far is rebuilt from the map.
        let shown = Array(levels.keys)
        levels = [:]; layouts = [:]
        for path in shown where path == current { load(path) }
    }
}
