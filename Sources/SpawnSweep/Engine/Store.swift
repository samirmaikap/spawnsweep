import Foundation

/// Everything SpawnSweep remembers, as small JSON files in ~/Library/Application Support/SpawnSweep.
/// The app and its command-line helpers (hook, MCP) share these files.
enum Store {
    static let dir: String = {
        let current = Shell.home + "/Library/Application Support/SpawnSweep"
        // SpawnSweep was first called "Lights Out": carry its rules, recycle bin and history over, once.
        let legacy = Shell.home + "/Library/Application Support/Lights Out"
        let fm = FileManager.default
        if !fm.fileExists(atPath: current), fm.fileExists(atPath: legacy) { try? fm.moveItem(atPath: legacy, toPath: current) }
        return current
    }()
    static let binDir = dir + "/RecycleBin"

    struct State: Codable {
        var prefs = Prefs()
        var marks: [String: AgentMark] = [:]

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            prefs = c.value(.prefs, or: Prefs())
            marks = c.value(.marks, or: [:])
        }
    }

    private static func url(_ name: String) -> URL { URL(fileURLWithPath: dir + "/" + name) }

    private static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ name: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(value) { try? data.write(to: url(name), options: .atomic) }
    }

    static func loadState() -> State { load("state.json", as: State.self) ?? State() }
    static func saveState(_ s: State) { save(s, "state.json") }

    static func loadActivity() -> [ActivityEntry] { load("activity.json", as: [ActivityEntry].self) ?? [] }

    /// Appends an entry unless one with the same dedupe key exists. Prunes past the history window.
    @discardableResult
    static func log(_ entry: ActivityEntry, historyDays: Int = 30) -> Bool {
        var all = loadActivity()
        if let key = entry.dedupeKey, all.contains(where: { $0.dedupeKey == key }) { return false }
        let cutoff = Date().addingTimeInterval(-Double(historyDays) * 86400)
        all = ([entry] + all).filter { $0.date > cutoff }
        save(all, "activity.json")
        return true
    }

    /// The last completed disk scan, shown instantly at launch while a fresh one runs.
    static func loadDisk() -> DiskSnapshot? { load("disk.json", as: DiskSnapshot.self) }
    static func saveDisk(_ d: DiskSnapshot) { save(d, "disk.json") }

    static func loadBin() -> [BinEntry] { load("bin.json", as: [BinEntry].self) ?? [] }

    private static let binLock = NSLock()
    /// Every bin.json write goes through here, so a recycle, a restore and the purge can't overwrite each other.
    /// ponytail: in-process lock; the hook/MCP helpers never write bin.json. Use flock if one ever does.
    static func updateBin(_ change: (inout [BinEntry]) -> Void) {
        binLock.lock(); defer { binLock.unlock() }
        var b = loadBin()
        change(&b)
        save(b, "bin.json")
    }

    /// An entry's saved-files folder. Nil for any id the app didn't make (always a UUID), so a damaged
    /// bin.json can never point a delete at "..", "/" or the bin itself.
    static func binFolder(_ id: String) -> String? { UUID(uuidString: id) == nil ? nil : binDir + "/" + id }
}
