import SwiftUI
import AppKit

/// Big files the user may not need, with the reason each one stands out. Nothing moves without a preview.
struct LargeFilesPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var sort: Sort = .size

    private var store: LargeFileStore { model.largeFiles }

    private enum Filter: String, CaseIterable {
        case all = "All", stale = "Not opened in 6 months", downloads = "Downloads", videos = "Videos", installers = "Installers & archives"
        func matches(_ f: LargeFile) -> Bool {
            switch self {
            case .all: return true
            case .stale: return f.stale
            case .downloads: return f.inDownloads
            case .videos: return f.kind == .video
            case .installers: return f.kind == .installer || f.kind == .archive
            }
        }
    }
    private enum Sort: String, CaseIterable { case size = "Size", oldest = "Oldest first" }
    private static let sizes: [(Int64, String)] = [(50_000_000, "50 MB"), (100_000_000, "100 MB"), (500_000_000, "500 MB"), (1_000_000_000, "1 GB")]
    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 18, alignment: .top)]

    var body: some View {
        let all = store.files
        let f = all.contains(where: filter.matches) ? filter : .all
        let list = sort == .size ? all.filter(f.matches)
            : all.filter(f.matches).sorted { ($0.touched ?? .distantFuture) < ($1.touched ?? .distantFuture) }
        PageScroll {
            BackLink(title: "This Mac") { model.go(.mac) }.padding(.bottom, -14)
            PageHeader(title: "Big, forgotten, and taking space.", subtitle: "Large files you haven't opened in a while.") {
                ClayPicker(title: "Minimum size", selection: Binding(get: { store.minBytes }, set: { store.minBytes = $0; store.scan() }),
                           options: Self.sizes.map { ($0.0, "Over " + $0.1) })
            }
            if store.scannedAt == nil {
                HeroCard(padding: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        SkeletonBlock(width: 300, height: 34)
                        SkeletonBlock(width: 220, height: 12)
                        SkeletonBlock(width: 420, height: 12)
                    }
                }
                SkeletonRows(count: 6)
            } else if all.isEmpty {
                Panel {
                    EmptyState(symbol: "checkmark.seal", title: "No large files here",
                               message: "Nothing over \(label(store.minBytes)) turned up in your home folder. Try a smaller size.")
                }
            } else {
                hero(all)
                if !model.license.isPro && store.staleBytes > 0 {
                    ProBanner(title: "\(Fmt.bytes(store.staleBytes)) you haven't opened in months",
                              line: "Look through everything here for free. Pro sends what you pick to the Trash, with a preview first and nothing deleted for good.")
                }
                toolbar(all, active: f, visible: list)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(list) { file in
                        LargeFileCard(file: file, selected: store.selected.contains(file.path),
                                      toggle: { store.selected.formSymmetricDifference([file.path]) },
                                      trash: { model.reviewTrash([file]) })
                    }
                }
                .animation(.easeOut(duration: 0.2), value: list.map(\.id))
            }
            InfoBanner(text: "Found with Spotlight in your home folder. Library, apps, and hidden folders are skipped. Nothing moves without a preview.",
                       symbol: "magnifyingglass")
        }
        .safeAreaInset(edge: .bottom) { selectionBar }
        .animation(.easeOut(duration: 0.2), value: store.selected.isEmpty)
    }

    private func label(_ b: Int64) -> String { Self.sizes.first { $0.0 == b }?.1 ?? Fmt.bytes(b) }

    // MARK: - Hero: the total, then what stands out

    private func hero(_ all: [LargeFile]) -> some View {
        let n = all.count
        let points = highlights(all)
        return HeroCard(padding: 30) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Fmt.bytes(store.totalBytes)).font(.system(size: 44)).tracking(-1).monospacedDigit()
                                .foregroundStyle(Theme.text).contentTransition(.numericText())
                            Text("in \(n) large file\(n == 1 ? "" : "s")").font(.system(size: 17)).foregroundStyle(Theme.secondary)
                        }
                        Text("Files over \(label(store.minBytes)) in your home folder · checked \(Fmt.ago(store.scannedAt))")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 16)
                    Button(store.scanning ? "Scanning…" : "Scan again") { store.scan() }
                        .buttonStyle(.quiet).disabled(store.scanning)
                }
                if !points.isEmpty {
                    let items = ForEach(points, id: \.text) { p in
                        HStack(spacing: 10) {
                            IconTile(symbol: p.symbol, size: 30, tone: p.tone)
                            Text(p.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).monospacedDigit()
                        }
                        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8)
                        .clayInset(radius: 14, fill: Theme.surface.opacity(0.5))
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { items }
                        VStack(alignment: .leading, spacing: 10) { items }
                    }
                }
            }
        }
    }

    private func highlights(_ all: [LargeFile]) -> [(symbol: String, text: String, tone: ClayTone)] {
        let sum = { (fs: [LargeFile]) in fs.reduce(Int64(0)) { $0 + $1.bytes } }
        var out: [(symbol: String, text: String, tone: ClayTone)] = []
        if store.staleBytes > 0 { out.append(("clock.arrow.circlepath", "\(Fmt.bytes(store.staleBytes)) not opened in 6 months", .peach)) }
        let installers = all.filter { $0.kind == .installer && $0.inDownloads }
        if !installers.isEmpty { out.append(("shippingbox", "\(Fmt.bytes(sum(installers))) of installers in Downloads", .sand)) }
        let videos = all.filter { $0.kind == .video && $0.bytes > 2_000_000_000 }.count
        if videos > 0 { out.append(("film", "\(videos) video\(videos == 1 ? "" : "s") over 2 GB", .lilac)) }
        let never = all.filter(\.neverOpened).count
        if never > 0 { out.append(("eye.slash", "\(never) never opened", .sky)) }
        let downloads = all.filter(\.inDownloads)
        if !downloads.isEmpty { out.append(("arrow.down.circle", "\(Fmt.bytes(sum(downloads))) in Downloads", .mint)) }
        return Array(out.prefix(3))
    }

    // MARK: - Filter, sort, select

    private func toolbar(_ all: [LargeFile], active: Filter, visible: [LargeFile]) -> some View {
        let tabs = ChipTabs(selection: Binding(get: { active }, set: { filter = $0 }),
                            options: Filter.allCases.compactMap { f in
                                let n = all.filter(f.matches).count
                                return f == .all || n > 0 ? (f, "\(f.rawValue) \(n)") : nil
                            })
            .monospacedDigit()
        let paths = visible.map(\.path)
        let allPicked = !paths.isEmpty && store.selected.isSuperset(of: paths)
        let controls = HStack(spacing: 10) {
            Button(allPicked ? "Clear selection" : "Select all") {
                if allPicked { store.selected.subtract(paths) } else { store.selected.formUnion(paths) }
            }
            .buttonStyle(.quiet)
            ClayPicker(title: "Sort files", selection: $sort, options: Sort.allCases.map { ($0, "Sort: " + $0.rawValue) })
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { tabs; Spacer(minLength: 12); controls }
            VStack(alignment: .leading, spacing: 12) { tabs; controls }
        }
    }

    @ViewBuilder private var selectionBar: some View {
        let picked = store.files.filter { store.selected.contains($0.path) }
        if !picked.isEmpty {
            let bytes = picked.reduce(Int64(0)) { $0 + $1.bytes }
            HStack(spacing: 14) {
                IconTile(symbol: "checkmark.circle", size: 34, tone: .sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(picked.count) selected · \(Fmt.bytes(bytes))").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text).monospacedDigit()
                    Text("They go to the Trash, so you can put any back.").font(.meta).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 12)
                Button("Clear") { store.selected = [] }.buttonStyle(.quiet)
                Button { model.reviewTrash(picked) } label: {
                    Label(model.license.isPro ? "Move to Trash…" : "Clean with Pro", systemImage: model.license.isPro ? "trash" : "lock.fill")
                }
                .buttonStyle(.primary)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .clay(radius: 20)
            .padding(.horizontal, 36).padding(.bottom, 16)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// One large file as a card: what it is, how big, where, and why it may be worth removing.
struct LargeFileCard: View {
    let file: LargeFile
    let selected: Bool
    let toggle: () -> Void
    let trash: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconTile(symbol: file.kind.symbol, size: 50, tone: file.kind.tone)
                Spacer(minLength: 8)
                Button(action: toggle) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).foregroundStyle(selected ? Theme.accent : Theme.secondary.opacity(0.6))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selected ? "Deselect \(file.name)" : "Select \(file.name)")
            }
            Text(file.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                .lineLimit(2).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)
                .padding(.top, 14)
            Text(Fmt.bytes(file.bytes)).font(.system(size: 24)).tracking(-0.5).monospacedDigit().foregroundStyle(Theme.text)
                .padding(.top, 8)
            Text(file.folder).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .lineLimit(1).truncationMode(.middle)
                .padding(.top, 4)
            Spacer(minLength: 14)
            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: file.strong ? "lightbulb" : "clock").font(.system(size: 11, weight: .semibold))
                    Text(file.insight).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12, weight: file.strong ? .medium : .regular))
                .foregroundStyle(file.strong ? Theme.amberText : Theme.secondary)
                Spacer(minLength: 8)
                Menu { menu } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More actions for \(file.name)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clay(radius: 22, glass: false)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.accent.opacity(selected ? 0.9 : hover ? 0.45 : 0), lineWidth: selected ? 2 : 1))
        .scaleEffect(hover ? 1.01 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(file.path)
        .contextMenu { menu }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var menu: some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) }
        Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }
        Divider()
        Button("Move to Trash…", action: trash)
    }
}

extension FileKind {
    var tone: ClayTone {
        switch self {
        case .video: return .lilac
        case .installer: return .sand
        case .archive: return .peach
        case .audio: return .sky
        case .image: return .mint
        case .document, .other: return .sage
        }
    }
}

extension AppModel {
    /// One preview for a set of large files. Each is checked again before it moves to the Trash.
    func reviewTrash(_ list: [LargeFile]) {
        let n = list.count, total = list.reduce(Int64(0)) { $0 + $1.bytes }
        var spec = DialogSpec(icon: "trash",
                              title: n == 1 ? "Move \(list[0].name) to the Trash?" : "Move \(n) large files to the Trash?",
                              subtitle: "About \(Fmt.bytes(total)) comes back once you empty the Trash.",
                              items: list.map { DialogItem(id: $0.path, label: $0.name, detail: ([Fmt.bytes($0.bytes)] + $0.reasons.prefix(1)).joined(separator: " · ")) },
                              notes: ["They stay in the Trash until you empty it, so you can still put any back."],
                              confirmTitle: "Move to Trash")
        spec.activityTitle = "Moved \(n) large file\(n == 1 ? "" : "s") to the Trash"
        spec.runningNote = "Checking each file again before it moves."
        let store = largeFiles
        spec.action = { chosen in
            let o = Edition.pro?.trash(list.filter { chosen.contains($0.path) }) ?? Actions.Outcome()
            let gone = Set(chosen.filter { !FileManager.default.fileExists(atPath: $0) })
            Task { @MainActor in store.remove(gone) }
            return o
        }
        spec.lockForPro(self)
        present(spec)
    }
}
