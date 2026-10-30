import SwiftUI

/// Everything listening on a port (dev servers and Docker stacks), attached to an agent session or not.
struct PortsPage: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter = Filter.all

    private enum Filter: Hashable { case all, ended }

    var body: some View {
        PageScroll {
            PageHeader(title: "Every port. Accounted for.", subtitle: "See what’s listening, where it came from, and what can stop.")
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                    TextField("Search port or project…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(width: 280)
                .clayInset(radius: 14)
                Spacer()
                ChipTabs(selection: $filter, options: [(.all, "All ports"), (.ended, "Ended sessions")])
            }
            ForEach(model.workspace.tunnels) { t in
                Button { model.reviewStop(t.resource) } label: {
                    WarningBanner(text: "\(t.tool) is exposing \(t.targetPort.map { "localhost:" + String($0) } ?? "a local port") to the internet. Review the tunnel before leaving.")
                }
                .buttonStyle(.plain)
                .help("Review the tunnel")
            }
            if model.workspace.scannedAt == .distantPast {
                LazyVGrid(columns: columns, spacing: 16) {
                    PortCardSkeleton()
                    PortCardSkeleton()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Checking which ports are open")
            } else if listening.isEmpty {
                EmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "No ports open.", message: "Dev servers and Docker stacks your agents and you start will appear here.")
            } else if shown.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: filter == .ended ? "No ports from ended sessions." : "No matching ports.",
                           message: "Try a port number or project name.")
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(shown) { PortCard(resource: $0) }
                }
            }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var listening: [Resource] {
        model.workspace.portResources
    }

    private var shown: [Resource] {
        let q = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "").lowercased()
        return listening.filter { r in
            let owner = model.workspace.session(for: r)
            if filter == .ended, owner?.state.isEnded != true { return false }
            if q.isEmpty { return true }
            let fields = [r.title, owner?.project, owner?.branch, r.cwd].compactMap { $0 } + r.ports.map(String.init)
            return fields.joined(separator: " ").lowercased().contains(q)
        }
    }
}

private struct PortCard: View {
    @Environment(AppModel.self) private var model
    let resource: Resource

    var body: some View {
        let r = resource
        let owner = model.workspace.session(for: r)
        let port = r.ports.first ?? 0
        let pinned = owner?.pinned ?? false
        let isProtected = pinned || r.ports.contains(where: model.isProtected(port:))
        let service = r.title.replacingOccurrences(of: " :" + String(port), with: "")

        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    IconTile(symbol: "network", size: 46, tone: .sky)
                    Text(":" + String(port)).font(.mono(26)).monospacedDigit().foregroundStyle(Theme.text)
                    Spacer()
                    owner?.badge ?? Badge(text: "Not tied to a session")
                }
                Text(owner?.project ?? r.cwd.map { ($0 as NSString).lastPathComponent } ?? "Unknown project")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                    .padding(.top, 14)
                Text([service, owner?.branch].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Chip(text: "localhost")
                    Chip(text: Fmt.bytes(r.memoryBytes))
                    ForEach(r.ports.dropFirst(), id: \.self) { Chip(text: ":" + String($0)) }
                }
                .padding(.top, 14)
                HStack {
                    if let start = r.startedAt {
                        Text("Up " + Fmt.duration(Date().timeIntervalSince(start)))
                            .font(.meta).monospacedDigit().foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if isProtected {
                        Button {} label: { Label("Protected", systemImage: "lock") }
                            .buttonStyle(.quiet)
                            .disabled(true)
                            .help(pinned ? "This session is pinned. Unpin it to free the port." : "Unprotect the port from this card's menu.")
                    } else {
                        Button(r.kind == .server ? "Free port" : "Stop") { model.reviewStop(r) }.buttonStyle(.quiet)
                    }
                }
                .padding(.top, 18)
                if let note = r.restartNote {
                    Label(note, systemImage: "arrow.clockwise")
                        .font(.meta).foregroundStyle(Theme.amberText)
                        .padding(.top, 10)
                }
            }
        }
        .contextMenu {
            ForEach(r.ports, id: \.self) { p in
                Button((model.isProtected(port: p) ? "Unprotect port :" : "Protect port :") + String(p)) {
                    model.toggleProtected(port: p)
                }
            }
            if let owner {
                Divider()
                Button("View session") { model.openSession(owner.folder) }
            }
        }
    }
}

/// First-scan placeholder in the shape of a PortCard: port line, project, service, chips, footer. No looping animation (§9).
private struct PortCardSkeleton: View {
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SkeletonBlock(width: 84, height: 26)
                    Spacer()
                    SkeletonBlock(width: 64, height: 20)
                }
                SkeletonBlock(width: 150, height: 14).padding(.top, 18)
                SkeletonBlock(width: 210, height: 11).padding(.top, 9)
                HStack(spacing: 8) {
                    SkeletonBlock(width: 68, height: 22)
                    SkeletonBlock(width: 56, height: 22)
                }
                .padding(.top, 14)
                HStack {
                    SkeletonBlock(width: 70, height: 11)
                    Spacer()
                    SkeletonBlock(width: 82, height: 28)
                }
                .padding(.top, 18)
            }
        }
    }
}
