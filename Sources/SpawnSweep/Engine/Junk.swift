import Foundation

struct JunkItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let bytes: Int64
    /// Inode and creation date at scan time; checked again right before the item is removed.
    var identity: String? = nil
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// What happens when it's cleaned and why it's safe.
    let note: String
    var items: [JunkItem]
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    /// Trash only: macOS keeps it private without Full Disk Access, so it can't be listed or measured.
    var unreadable = false
}

@MainActor @Observable
final class JunkStore {
    var categories: [JunkCategory] = []
    var scanning = false
    var scannedAt: Date?
    var totalBytes: Int64 { categories.reduce(0) { $0 + $1.bytes } }
    private var rescanQueued = false

    /// Rebuildable categories cleaned together by "Clean safe junk". Installers and Trash need their own look.
    static let safeIDs = ["caches", "dev", "xcode", "logs"]
    var safeBytes: Int64 { categories.filter { Self.safeIDs.contains($0.id) }.reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !scanning else { rescanQueued = true; return }
        scanning = true
        Task.detached {
            let found = Edition.pro?.findJunk() ?? []
            await MainActor.run {
                self.categories = found
                self.scannedAt = Date()
                self.scanning = false
                if self.rescanQueued { self.rescanQueued = false; self.scan() }
            }
        }
    }

    /// The preview for one or more categories. Every item is checked again when it runs.
    func review(_ ids: [String]) -> DialogSpec {
        let cats = categories.filter { ids.contains($0.id) && !$0.unreadable }
        let picks = cats.flatMap { c in c.items.map { (c.id, $0) } }.sorted { $0.1.bytes > $1.1.bytes }
        let total = picks.reduce(Int64(0)) { $0 + $1.1.bytes }
        let n = picks.count, s = n == 1 ? "" : "s"
        let trash = ids == ["trash"], installers = ids == ["installers"]
        let titles = Dictionary(cats.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var spec = DialogSpec(
            icon: cats.count == 1 ? cats[0].symbol : "bubbles.and.sparkles",
            title: trash ? "Empty the Trash?" : installers ? "Move \(n) old installer\(s) to the Trash?" : "Clean \(Fmt.bytes(total)) of junk?",
            subtitle: "\(n) item\(s) · \(Fmt.bytes(total))" + (cats.count == 1 ? " · \(cats[0].title.lowercased())" : ""),
            items: picks.map { cat, item in
                DialogItem(id: item.path, label: item.name,
                           detail: cats.count > 1 ? "\(titles[cat] ?? "") · \(Fmt.bytes(item.bytes))" : Fmt.bytes(item.bytes))
            },
            notes: [cats.count == 1 ? cats[0].note : "Apps and tools rebuild these as needed. Caches of apps that are open are left alone."],
            confirmTitle: trash ? "Empty Trash" : installers ? "Move to Trash" : "Clean",
            destructive: trash)
        if trash { spec.warning = "This deletes them for good. They can't be restored from SpawnSweep or the Trash." }
        spec.activityTitle = trash ? "Emptied the Trash · \(Fmt.bytes(total))"
            : installers ? "Moved \(n) old installer\(s) to the Trash" : "Cleaned \(Fmt.bytes(total)) of junk"
        spec.runningNote = installers ? "Moving each installer to the Trash." : "Checking each item again, then removing it."
        spec.action = { chosen in
            let (o, removed) = Edition.pro?.cleanJunk(picks.filter { chosen.contains($0.1.path) }) ?? (Actions.Outcome(), [])
            Task { @MainActor in self.drop(removed); self.scan() }
            return o
        }
        if picks.isEmpty {
            spec.title = "Nothing to clean"; spec.subtitle = "There's no junk here right now."
            spec.action = nil; spec.confirmTitle = "OK"; spec.warning = nil; spec.destructive = false
        }
        return spec
    }

    /// Takes cleaned items off the page right away; the rescan that follows confirms the rest.
    private func drop(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        for i in categories.indices { categories[i].items.removeAll { paths.contains($0.path) } }
        categories.removeAll { $0.items.isEmpty && !$0.unreadable }
    }
}
