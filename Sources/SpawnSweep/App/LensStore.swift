import SwiftUI

/// Space Lens state: where you are, what's been measured, what's selected or under the pointer.
/// Measuring runs off the main thread, one folder level at a time, and results stay until a rescan.
@Observable @MainActor
final class LensStore {
    var stack: [String] = [Shell.home]
    var nodes: [String: [LensNode]] = [:]
    /// Packed once per level when it finishes measuring; the page only scales it to fit.
    var layouts: [String: LensLayout] = [:]
    var measuring: Set<String> = []
    /// Items measured so far and in all, for the progress shown while a level measures.
    var progress: [String: (done: Int, total: Int)] = [:]
    var selected: String?
    var hovered: String?

    var current: String { stack.last ?? Shell.home }

    func open(_ path: String) {
        stack.append(path)
        selected = nil; hovered = nil
        load(path)
    }

    func up(to index: Int) {
        stack = Array(stack.prefix(index + 1))
        selected = nil; hovered = nil
        load(current)
    }

    func select(_ node: LensNode) {
        selected = node.path
        if node.isDir { load(node.path) }   // measured in the background so its breakdown is ready
    }

    func load(_ path: String, force: Bool = false) {
        guard Edition.hasPro, force || (nodes[path] == nil && !measuring.contains(path)) else { return }
        measuring.insert(path)
        progress[path] = (0, 0)
        Task.detached {
            Edition.pro?.lensChildren(of: path) { ns, total, done in
                // Only the finished level is drawn; packing happens here, off the main thread, exactly once.
                let layout = done ? LensLayout(folder: path, nodes: ns) : nil
                Task { @MainActor in
                    // Progress can land after the final result; once a level is done, only a rescan replaces it.
                    guard self.measuring.contains(path) else { return }
                    if done {
                        self.nodes[path] = ns
                        self.layouts[path] = layout
                        self.measuring.remove(path)
                    } else if ns.count > (self.progress[path]?.done ?? 0) {
                        self.progress[path] = (ns.count, total)
                    }
                }
            }
        }
    }

    func rescan() {
        let keep = current
        nodes = [:]; layouts = [:]; measuring = []; progress = [:]
        load(keep, force: true)
    }

    /// Takes an item that went to the Trash off every level, so totals and moons update without a rescan.
    func drop(_ path: String) {
        for key in nodes.keys where nodes[key]?.contains(where: { $0.path == path }) == true {
            nodes[key]?.removeAll { $0.path == path }
            layouts[key] = LensLayout(folder: key, nodes: nodes[key] ?? [])
        }
        nodes[path] = nil; layouts[path] = nil
        if selected == path { selected = nil }
        if hovered == path { hovered = nil }
    }

    func node(_ path: String?) -> LensNode? {
        guard let path else { return nil }
        for list in nodes.values { if let n = list.first(where: { $0.path == path }) { return n } }
        return nil
    }
}
