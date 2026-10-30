import SwiftUI
import AppKit

/// This Mac › Space Lens: the home folder as a cluster of clay moons, sized by disk use.
/// Click selects, double-click opens a folder; the side panel explains the selection and offers the one safe action.
struct SpaceLensPage: View {
    @Environment(AppModel.self) private var model
    private var lens: LensStore { model.lens }

    var body: some View {
        PageScroll {
            BackLink(title: "This Mac") { model.go(.mac) }.padding(.bottom, -14)
            PageHeader(title: "See where your space went.", subtitle: "Your home folder by size. Click to look closer, double-click to open.") {
                Button { lens.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.quiet)
                    .disabled(lens.measuring.contains(lens.current))
            }
            breadcrumb
            if !LensAccess.full { accessBanner }
            HStack(alignment: .top, spacing: 22) {
                cluster
                LensDetail(node: lens.node(lens.selected) ?? folderNode)
            }
        }
        .onAppear { lens.load(lens.current) }
    }

    /// The folder you're in, as a node, for the side panel when nothing is selected.
    private var folderNode: LensNode {
        let path = lens.current
        let total = (lens.nodes[path] ?? []).reduce(Int64(0)) { $0 + $1.bytes }
        let parent = lens.nodes[(path as NSString).deletingLastPathComponent]?.first { $0.path == path }
        return LensNode(path: path, name: path == Shell.home ? "Home" : (path as NSString).lastPathComponent,
                        isDir: true, bytes: total, kind: parent?.kind ?? .yourFiles)
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            ForEach(Array(lens.stack.enumerated()), id: \.offset) { i, path in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary) }
                let last = i == lens.stack.count - 1
                Button { if !last { lens.up(to: i) } } label: {
                    Text(i == 0 ? "Home" : (path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: last ? .semibold : .medium))
                        .foregroundStyle(last ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .clayInset(radius: 10, fill: last ? Theme.tintStrong : Theme.tint)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if lens.measuring.contains(lens.current) {
                let p = lens.progress[lens.current] ?? (0, 0)
                ProgressView().controlSize(.small)
                Text(p.total > 0 ? "Measuring… \(p.done) of \(p.total)" : "Measuring…").font(.meta).monospacedDigit().foregroundStyle(Theme.secondary)
            } else if let list = lens.nodes[lens.current] {
                Text("\(Fmt.bytes(list.reduce(0) { $0 + $1.bytes })) · \(list.count) item\(list.count == 1 ? "" : "s")")
                    .font(.meta).foregroundStyle(Theme.secondary)
            }
        }
    }

    /// Measuring shows a breathing moon and progress; the moons appear once, when the level is fully measured.
    private var cluster: some View {
        let layout = lens.layouts[lens.current]
        let measuring = lens.measuring.contains(lens.current)
        return VStack(alignment: .leading, spacing: 10) {
            Group {
                if measuring || layout == nil {
                    scanning
                } else if let layout, layout.moons.isEmpty {
                    Text("Nothing here takes up space.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let layout {
                    moons(layout)
                }
            }
            .frame(height: 430)
            HStack(spacing: 16) {
                ForEach([LensKind.project, .rebuildable, .yourFiles, .appData, .other], id: \.self) { k in
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: LensMoon.palette(k)[1])).frame(width: 10, height: 10)
                        Text(LensMoon.legend(k)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .clay(radius: 30, fill: Theme.heroGradient, glass: false)
    }

    /// The packed layout, scaled to the panel. Hover and selection only restyle moons; nothing is repacked.
    private func moons(_ layout: LensLayout) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, b = layout.bounds
            let k = min((w - 40) / max(1, b.width), (h - 40) / max(1, b.height))
            ZStack {
                ForEach(Array(layout.moons.enumerated()), id: \.element.path) { i, n in
                    LensMoon(node: n, r: layout.radii[i] * k, safe: model.lensSafeBytes(n),
                             hovered: lens.hovered == n.path, selected: lens.selected == n.path,
                             dimmed: lens.hovered != nil && lens.hovered != n.path)
                        .position(x: w / 2 + (layout.points[i].x - b.midX) * k, y: h / 2 + (layout.points[i].y - b.midY) * k)
                        .onHover { inside in
                            if inside { lens.hovered = n.path } else if lens.hovered == n.path { lens.hovered = nil }
                        }
                        .onTapGesture(count: 2) { if n.isDir { lens.open(n.path) } }
                        .onTapGesture { lens.select(n) }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: lens.hovered)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: lens.selected)
        }
    }

    private var scanning: some View {
        let p = lens.progress[lens.current] ?? (0, 0)
        let name = lens.current == Shell.home ? "your home folder" : (lens.current as NSString).lastPathComponent
        return VStack(spacing: 14) {
            ScanningMoon()
            Text("Measuring \(name)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            if p.total > 0 {
                ProgressView(value: Double(p.done), total: Double(p.total)).tint(Theme.accentLight).frame(width: 260)
                Text("\(p.done) of \(p.total) items. Big folders like Library can take a minute.")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.secondary)
            } else {
                Text("Listing what's inside…").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessBanner: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "lock.shield", size: 32, tone: .sky)
            VStack(alignment: .leading, spacing: 2) {
                Text("Desktop, Documents, Downloads and other apps' data are skipped.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text("macOS would ask about each one. Give SpawnSweep Full Disk Access once to measure everything, then quit and reopen it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { NSWorkspace.shared.open(LensAccess.settings) }.buttonStyle(.quiet)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .clayInset(radius: 18)
    }
}

/// A moon that breathes while Space Lens measures, and only then. Still when Reduce Motion is on.
struct ScanningMoon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Moon(size: 104, rings: true)
            .scaleEffect(on && !reduceMotion ? 1.05 : 0.95)
            .opacity(on || reduceMotion ? 1 : 0.7)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .frame(width: 170, height: 160)
            .accessibilityHidden(true)
    }
}

/// A folder or file as a clay moon, with the app icon's moon gradient in the color of what it is.
/// Hover lifts it and says how much is safe to clear; the selected moon stays a little lifted.
struct LensMoon: View {
    let node: LensNode
    let r: CGFloat
    let safe: Int64
    var hovered = false
    var selected = false
    var dimmed = false

    static func palette(_ k: LensKind) -> [UInt32] {
        switch k {
        case .project: return [0xF7FAEC, 0xD3E2BE, 0x9DBB88, 0x5F8A66]
        case .rebuildable: return [0xF0FAF5, 0xC7EBD8, 0x86C9A6, 0x3F8A66]
        case .yourFiles: return [0xFBF6EA, 0xEAD9B4, 0xC9A86E, 0x8E6E3A]
        case .appData: return [0xF1F6FC, 0xCFE0F2, 0x93B4D8, 0x557BA6]
        case .other: return [0xF6F3FD, 0xDCD3F3, 0xA899D6, 0x6A5BA6]
        }
    }
    static func ink(_ k: LensKind) -> Color {
        switch k {
        case .yourFiles: return Color(hex: 0x4A3712)
        case .appData: return Color(hex: 0x1E3A5A)
        case .other: return Color(hex: 0x3A2F66)
        default: return Color(hex: 0x24382C)
        }
    }
    static func legend(_ k: LensKind) -> String {
        switch k {
        case .project: return "Projects"
        case .rebuildable: return "Safe to clear"
        case .yourFiles: return "Your files"
        case .appData: return "App data"
        case .other: return "Other"
        }
    }

    var body: some View {
        let lift: CGFloat = hovered ? 1.12 : selected ? 1.06 : 1
        ZStack {
            Circle()
                .fill(RadialGradient(colors: Self.palette(node.kind).map { Color(hex: $0) },
                                     center: UnitPoint(x: 0.3, y: 0.24), startRadius: 0, endRadius: r * 1.7))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 1.5))
                .frame(width: r * 2, height: r * 2)
                .shadow(color: .black.opacity(lift > 1 ? 0.5 : 0.32), radius: r * (lift > 1 ? 0.2 : 0.12), x: r * 0.03, y: r * (lift > 1 ? 0.13 : 0.07))
            if r > 38 || hovered {
                VStack(spacing: 3) {
                    Text(node.name).font(.system(size: r > 90 ? 16 : r > 55 ? 13 : 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(Fmt.bytes(node.bytes)).font(.system(size: r > 90 ? 14 : 11, weight: .medium)).monospacedDigit().opacity(0.8)
                    if hovered && safe > 0 && Double(safe) > Double(node.bytes) * 0.05 {
                        Text("\(Fmt.bytes(safe)) safe to clear")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x24563A))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.75)))
                            .padding(.top, 4)
                    }
                }
                .foregroundStyle(Self.ink(node.kind))
                .frame(width: max(r * 1.6, hovered ? 120 : 0))
            }
        }
        .scaleEffect(lift)
        .opacity(dimmed ? 0.55 : 1)
        .zIndex(hovered ? 2 : selected ? 1 : 0)
        .contentShape(Circle())
        .help("\(node.name) · \(Fmt.bytes(node.bytes))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(Fmt.bytes(node.bytes)), \(Self.legend(node.kind))")
        .accessibilityAddTraits(.isButton)
    }
}

/// The side panel: what the selection (or the folder you're in) is, its biggest parts, and what you can do.
struct LensDetail: View {
    @Environment(AppModel.self) private var model
    let node: LensNode

    var body: some View {
        let lens = model.lens
        let parts = node.path.hasSuffix("/\u{0}smaller") ? smallerItems : (lens.nodes[node.path] ?? [])
        let slim = model.lensSlimmable(node)
        let slimBytes = slim.reduce(Int64(0)) { $0 + ($1.slimBytes ?? 0) }
        let canTrash = [.yourFiles, .rebuildable, .other].contains(node.kind) && !node.path.hasSuffix("/\u{0}smaller")
            && node.path != lens.current && Actions.trashRefusal(node.path, busy: []) == nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: node.isDir ? "folder" : "doc", size: 44, tone: tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("\(Fmt.bytes(node.bytes)) · \(LensMoon.legend(node.kind))").font(.meta).foregroundStyle(Theme.secondary)
                }
            }
            if !parts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(parts.prefix(5)) { part($0) }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .clayInset(radius: 16)
            } else if node.isDir && lens.measuring.contains(node.path) {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Measuring what's inside…").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            Text(note(slimBytes: slimBytes)).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                if slimBytes > 0 {
                    Button { model.reviewBulkSlim(slim) } label: { Label("Slim \(Fmt.bytes(slimBytes))", systemImage: "scissors").fixedSize() }
                        .buttonStyle(.primary)
                }
                if canTrash {
                    Button { model.reviewLensTrash(node) } label: { Label("Move to Trash", systemImage: "trash").fixedSize() }
                        .buttonStyle(slimBytes > 0 ? AnyButtonStyle(QuietButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                }
                HStack(spacing: 8) {
                    if node.isDir && node.path != lens.current { Button("Open") { lens.open(node.path) }.buttonStyle(.quiet) }
                    if !node.path.hasSuffix("/\u{0}smaller") {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }.buttonStyle(.quiet)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 330, alignment: .leading)
        .clay(radius: 24, glass: false)
    }

    private var smallerItems: [LensNode] {
        Array((model.lens.nodes[model.lens.current] ?? []).filter { $0.bytes > 0 }.dropFirst(LensLayout.maxMoons))
    }

    private var tone: ClayTone {
        switch node.kind {
        case .project: return .sage
        case .rebuildable: return .mint
        case .yourFiles: return .sand
        case .appData: return .sky
        case .other: return .lilac
        }
    }

    private func note(slimBytes: Int64) -> String {
        if node.path.hasSuffix("/\u{0}smaller") { return "Smaller items in this folder, biggest first." }
        switch node.kind {
        case .rebuildable: return "Tools make this again when you need it, for example with npm install."
        case .appData: return "App data. Junk clears the parts that are safe to remove; the rest belongs to your apps."
        case .project where slimBytes > 0, .yourFiles where slimBytes > 0:
            return "Slim removes only rebuildable folders in idle agent worktrees. Code, branches and git history stay."
        case .project: return "A project. Its code and history stay; nothing here is cleared for you."
        default: return "Your files. Move to Trash keeps them in the Trash until you empty it."
        }
    }

    private func part(_ p: LensNode) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: LensMoon.palette(p.kind)[2])).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                Text(p.locked ? "Needs Full Disk Access" : p.kind == .rebuildable ? "Safe to clear, rebuilt on demand" : p.kind == .appData ? "App data" : "Yours, kept")
                    .font(.system(size: 11)).foregroundStyle(p.kind == .rebuildable && !p.locked ? Color(hex: 0x8FD4AE) : Theme.secondary)
            }
            Spacer()
            Text(p.locked ? "—" : Fmt.bytes(p.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .padding(.vertical, 8)
    }
}
