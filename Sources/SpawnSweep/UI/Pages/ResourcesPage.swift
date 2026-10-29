import SwiftUI

struct ResourcesPage: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .devices
    @State private var showAllUnused = false

    private enum Tab: Hashable { case devices, stacks, watchers }

    /// True until the first workspace scan lands.
    private var firstScan: Bool { model.workspace.scannedAt == .distantPast }

    var body: some View {
        PageScroll {
            PageHeader(title: "The things behind the sessions.",
                       subtitle: "Devices, stacks, browsers, and watchers. Together in one place.")
            VStack(alignment: .leading, spacing: 20) {
                ChipTabs(selection: $tab, options: [(.devices, "Devices"), (.stacks, "Docker stacks"), (.watchers, "Browsers & watchers")])
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .devices: devices
                    case .stacks: stacks
                    case .watchers: watchers
                    }
                }
            }
        }
    }

    // MARK: - Devices

    @ViewBuilder private var devices: some View {
        let booted = model.workspace.devices.filter(\.booted)
        Panel(title: "Booted devices") {
            if booted.isEmpty {
                if firstScan { ProgressLine(text: "Looking for running devices…") }
                else {
                    EmptyState(symbol: "iphone", title: "No devices running",
                               message: "Booted simulators and emulators appear here.")
                }
            } else {
                RowList(items: booted) { d in
                    let r = resource("sim:\(d.udid)")
                    let owner = r.flatMap(model.workspace.session(for:))
                    ResourceRow(symbol: "iphone", title: d.runtime.isEmpty ? d.name : "\(d.name) · \(d.runtime)",
                                subtitle: context(owner, fallback: d.bootedAt.map { "Booted \(Fmt.ago($0)) · no agent session" } ?? "No agent session"),
                                value: memory(d.memoryBytes)) {
                        action(r, owner: owner, label: "Shut down")
                    }
                    .contextMenu { menu(r, owner: owner, label: "Shut Down") }
                }
            }
        }
        let unused = model.disk.unusedDevices.sorted { $0.dataBytes > $1.dataBytes }
        let rest = unused.dropFirst(Self.unusedLimit)
        Panel(title: "Unused devices", trailing: {
            if unused.count > 1 {
                Button("Review all · \(Fmt.bytes(model.disk.unusedDeviceBytes))") { model.reviewDeleteDevices(unused) }
                    .buttonStyle(.quiet).monospacedDigit()
            }
        }) {
            if unused.isEmpty {
                if model.disk.simulatorDevices.isEmpty && (model.disk.inProgress || model.diskScanning) {
                    ProgressLine(text: "Checking simulator devices…")
                } else {
                    EmptyState(symbol: "iphone", title: "No unused devices",
                               message: "Simulators nobody has booted for 30 days appear here.")
                }
            } else {
                VStack(spacing: 0) {
                    RowList(items: showAllUnused ? unused : Array(unused.prefix(Self.unusedLimit))) { d in
                        ResourceRow(symbol: "iphone", title: d.runtime.isEmpty ? d.name : "\(d.name) · \(d.runtime)",
                                    subtitle: (d.lastUsed.map { "Last used \(Fmt.ago($0))" } ?? "Never used") + " · no active session",
                                    value: d.dataBytes > 0 ? Fmt.bytes(d.dataBytes) : nil) {
                            Button("Review removal") { model.reviewDeleteDevice(d) }.buttonStyle(.quiet)
                        }
                    }
                    if !rest.isEmpty {
                        ShowMoreButton(expanded: showAllUnused, hiddenCount: rest.count,
                                       detail: Fmt.bytes(rest.reduce(Int64(0)) { $0 + $1.dataBytes })) { showAllUnused.toggle() }
                    }
                }
            }
        }
    }

    private static let unusedLimit = 5

    // MARK: - Docker stacks

    @ViewBuilder private var stacks: some View {
        let list = model.workspace.stacks
        Panel(title: "Local Docker stacks") {
            if list.isEmpty {
                if firstScan { ProgressLine(text: "Looking for Docker stacks…") }
                else {
                    EmptyState(symbol: "shippingbox", title: "No Docker stacks running",
                               message: "Running Compose projects and containers appear here, one row per stack.")
                }
            } else {
                RowList(items: list) { s in
                    let r = resource("stack:\(s.project)")
                    let owner = r.flatMap(model.workspace.session(for:))
                    ResourceRow(symbol: "shippingbox", title: stackTitle(s), subtitle: stackDetail(s, owner: owner),
                                value: memory(s.memoryBytes)) {
                        action(r, owner: owner, label: "Stop stack")
                    }
                    .help(s.workingDir ?? s.project)
                    .contextMenu { menu(r, owner: owner, label: "Stop Stack") }
                }
            }
        }
        InfoBanner(text: "A stack stops as a unit. Volumes and local database files stay on disk.")
    }

    private func stackTitle(_ s: Stack) -> String {
        if s.names.contains(where: { $0.contains("supabase") }) { return "Supabase / \(s.project)" }
        return s.workingDir != nil ? "Compose / \(s.project)" : s.project   // working dir comes from the Compose label
    }

    private func stackDetail(_ s: Stack, owner: Session?) -> String {
        let n = s.containers.count
        var parts = ["\(n) container\(n == 1 ? "" : "s") grouped as one stack"]
        let ports = Array(Set(s.ports)).sorted()
        if !ports.isEmpty {
            parts.append("port\(ports.count == 1 ? "" : "s") " + ports.prefix(4).map(String.init).joined(separator: ", ")
                         + (ports.count > 4 ? " +\(ports.count - 4)" : ""))
        }
        if let owner { parts.append(context(owner, fallback: "")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Browsers & watchers

    @ViewBuilder private var watchers: some View {
        let all = model.workspace.allResources
        let browsers = all.filter { $0.kind == .browser }, watchers = all.filter { $0.kind == .watcher }
        if browsers.isEmpty && watchers.isEmpty {
            Panel {
                if firstScan { ProgressLine(text: "Looking for browsers and watchers…") }
                else {
                    EmptyState(symbol: "eye", title: "No browsers or watchers running",
                               message: "Headless browsers and file watchers started for your projects appear here.")
                }
            }
        } else {
            if !browsers.isEmpty { Panel(title: "Headless browsers") { processRows(browsers, label: "Close") } }
            if !watchers.isEmpty { Panel(title: "Watchers") { processRows(watchers, label: "Stop") } }
        }
    }

    private func processRows(_ rs: [Resource], label: String) -> some View {
        RowList(items: rs) { r in
            let owner = model.workspace.session(for: r)
            let place = owner?.project ?? r.cwd.map { ($0 as NSString).lastPathComponent }
            let subtitle = ([place, owner?.branch].compactMap { $0 } + [owner.map { Self.state($0) } ?? "no agent session", r.detail])
                .joined(separator: " · ")
            ResourceRow(symbol: r.kind.symbol, title: r.title, subtitle: subtitle, value: memory(r.memoryBytes)) {
                action(r, owner: owner, label: label)
            }
            .help(r.command ?? r.title)
            .contextMenu { menu(r, owner: owner, label: label) }
        }
    }

    // MARK: - Shared row pieces

    private func resource(_ id: String) -> Resource? { model.workspace.allResources.first { $0.id == id } }

    private func memory(_ b: Int64) -> String? { b > 0 ? Fmt.bytes(b) : nil }

    /// "project · Agent · idle for 2h 14m"
    private func context(_ s: Session?, fallback: String) -> String {
        guard let s else { return fallback }
        return [s.project, s.agent.rawValue, Self.state(s)].joined(separator: " · ")
    }

    private static func state(_ s: Session) -> String {
        if s.pinned { return "pinned" }
        switch s.state {
        case .active: return "active"
        case .idle(let since): return "idle for \(Fmt.duration(Date().timeIntervalSince(since)))"
        case .ended: return "session ended"
        }
    }

    /// Protected and active things show a badge instead of a stop button; the context menu still offers a reviewed stop.
    @ViewBuilder private func action(_ r: Resource?, owner: Session?, label: String) -> some View {
        if owner?.pinned == true || (r?.ports.contains(where: model.isProtected(port:)) ?? false) {
            Badge(text: "Protected", style: .success)
        } else if owner?.state.isActive == true {
            Badge(text: "Active", style: .active)
        } else if let r {
            Button(label) { model.reviewStop(r) }.buttonStyle(.quiet)
        }
    }

    @ViewBuilder private func menu(_ r: Resource?, owner: Session?, label: String) -> some View {
        if let r { Button("\(label)…") { model.reviewStop(r) } }
        if let owner { Button("View Session") { model.openSession(owner.folder) } }
    }
}
