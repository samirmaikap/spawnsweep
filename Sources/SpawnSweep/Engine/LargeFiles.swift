import Foundation

enum FileKind: String {
    case video, installer, archive, audio, image, document, other

    var symbol: String {
        switch self {
        case .video: return "film"
        case .installer: return "shippingbox"
        case .archive: return "doc.zipper"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.text"
        case .other: return "doc"
        }
    }

    /// Installers and archives by extension, everything else by Spotlight's content type tree.
    static func of(path: String, types: [String]) -> FileKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if ["dmg", "pkg", "mpkg", "xip", "iso"].contains(ext) { return .installer }
        if ["zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz"].contains(ext) || types.contains("public.archive") { return .archive }
        if types.contains("public.movie") { return .video }
        if types.contains("public.audio") { return .audio }
        if types.contains("public.image") { return .image }
        if types.contains(where: ["public.composite-content", "public.text", "public.presentation", "public.spreadsheet"].contains) { return .document }
        return .other
    }
}

struct LargeFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let bytes: Int64
    let lastUsed: Date?
    let created: Date?
    /// Content last changed. Apps write VM disks, databases and libraries without Finder ever "opening" them.
    let modified: Date?
    var kind: FileKind = .other
    /// Why it may be worth removing, most useful first.
    var reasons: [String] = []
    /// The first reason is a clear hint: never opened, untouched for six months, or already installed.
    var strong = false
    /// Inode and creation date at scan time; checked again right before the item is removed.
    var identity: String?

    var name: String { (path as NSString).lastPathComponent }
    var folder: String { ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath }
    var insight: String { reasons.prefix(2).joined(separator: " · ") }
    var inDownloads: Bool { path.hasPrefix(Shell.home + "/Downloads/") }
    /// Last opened or changed, whichever is later; when added if neither is known.
    var touched: Date? { [lastUsed, modified].compactMap { $0 }.max() ?? created }
    var stale: Bool { touched.map { Date().timeIntervalSince($0) > 180 * 86400 } ?? false }
    var neverOpened: Bool {
        !appData && lastUsed == nil && [modified, created].compactMap { $0 }.max().map { Date().timeIntervalSince($0) > 30 * 86400 } == true
    }
    /// VM disks and databases: apps use them directly, so Spotlight never records them as opened.
    var appData: Bool { ["vdi", "vmdk", "qcow2", "hdd", "img", "sqlite", "sqlite3", "db", "raw"].contains((path as NSString).pathExtension.lowercased()) }
}

@MainActor @Observable
final class LargeFileStore {
    var files: [LargeFile] = []
    var scanning = false
    var scannedAt: Date?
    /// Smallest file worth listing.
    var minBytes: Int64 = 100_000_000
    /// Files picked on the Large & old files page.
    var selected = Set<String>()
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    /// Large files nobody has opened in six months or more.
    var staleBytes: Int64 { files.filter(\.stale).reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        let min = minBytes
        Task.detached(priority: .utility) {
            let found = Edition.pro?.findLargeFiles(minBytes: min) ?? []
            await MainActor.run {
                self.files = found
                self.selected.formIntersection(found.map(\.path))
                self.scanning = false
                self.scannedAt = Date()
                if self.minBytes != min { self.scan() }   // the size changed while we were looking
            }
        }
    }

    func remove(_ paths: Set<String>) {
        files.removeAll { paths.contains($0.path) }
        selected = []
    }
}
