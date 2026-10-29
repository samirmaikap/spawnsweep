import SwiftUI

/// Menu bar companion: what's running right now, grouped by session, with one click to stop or review.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let ws = model.workspace
        let sessions = ws.sessions.filter { !$0.resources.isEmpty }
            .sorted { ($0.needsAttention ? 0 : 1, $0.project) < ($1.needsAttention ? 0 : 1, $1.project) }
        let attached = Set(sessions.flatMap(\.resources).compactMap(\.udid))
        // Stacks already shown through a session or as an unattached resource aren't listed a second time.
        let stackNames = Set((sessions.flatMap(\.resources) + ws.unattached).compactMap(\.stackProject))
        let looseSims = ws.devices.filter { $0.booted && !attached.contains($0.udid) }
        let looseStacks = ws.stacks.filter { !stackNames.contains($0.project) }
        let quiet = sessions.isEmpty && ws.unattached.isEmpty && looseSims.isEmpty && looseStacks.isEmpty

        VStack(alignment: .leading, spacing: 14) {
            header(running: sessions.count + ws.unattached.count + looseSims.count + looseStacks.count)
            stats

            if quiet {
                quietCard
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(ws.tunnels) { t in
                            Button { open { model.go(.safety) } } label: {
                                Label("Public tunnel open: \(t.tool)" + (t.targetPort.map { " → :\($0)" } ?? ""), systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.amberText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .clayInset(radius: 12, fill: Theme.warningFill)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(sessions) { s in SessionCard(session: s, open: open) }
                        if !ws.unattached.isEmpty {
                            group(title: "Not tied to a session") {
                                ForEach(ws.unattached) { r in
                                    row(symbol: r.kind.symbol, title: label(r), detail: Fmt.bytes(r.memoryBytes)) {
                                        Button(r.kind == .server ? "Free" : "Stop") { open { model.reviewStop(r) } }.buttonStyle(.quiet)
                                    }
                                }
                            }
                        }
                        if !looseSims.isEmpty || !looseStacks.isEmpty {
                            group(title: "Also running") {
                                ForEach(looseSims) { d in
                                    row(symbol: "iphone", title: d.name, detail: d.runtime) {
                                        Button("Review") { open { model.go(.resources) } }.buttonStyle(.quiet)
                                    }
                                }
                                ForEach(looseStacks) { st in
                                    row(symbol: "shippingbox", title: st.project, detail: "\(st.containers.count) container\(st.containers.count == 1 ? "" : "s")") {
                                        Button("Review") { open { model.go(.resources) } }.buttonStyle(.quiet)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !model.license.isPro && model.junk.totalBytes > 1_000_000_000 {
                Button { open { model.go(.pro) } } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: "crown.fill", size: 26, tone: ClayTone(fill: Theme.amberFill, glyph: Theme.proGold))
                        Text("\(Fmt.bytes(model.junk.totalBytes)) of junk ready to clean").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                        Spacer()
                        ProPill()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(ClayBackground(radius: 14, fill: AnyShapeStyle(Theme.proGradient), glass: false, raised: false))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            autopilot
            footer
        }
        .padding(18)
        .frame(width: 380)
        .onAppear { model.system.refresh() }
        .background {
            ZStack {
                VisualEffect(material: .popover, blending: .behindWindow)
                LinearGradient(colors: [Theme.bg.opacity(0.85), Theme.sidebar.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    // MARK: - Pieces

    private func header(running: Int) -> some View {
        let attention = model.attentionSessions.count
        let status = running == 0 ? "All quiet."
            : "\(running) running" + (attention > 0 ? " · \(attention) need\(attention == 1 ? "s" : "") a look" : "")
        return HStack(spacing: 12) {
            AppMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("SpawnSweep").font(.display(17)).tracking(-0.3).foregroundStyle(Theme.text)
                Text(status).font(.system(size: 12)).foregroundStyle(attention > 0 ? Theme.amberText : Theme.secondary)
            }
            Spacer()
            Text("⌘ ⇧ L").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4).clayInset(radius: 8)
        }
    }

    private var stats: some View {
        let ws = model.workspace
        return HStack(spacing: 10) {
            stat("network", .sky, "\(Set(ws.allResources.flatMap(\.ports)).count)", "Ports open")
            let mem = model.system.memory, vol = model.system.volume
            stat("memorychip", mem.pressure == .normal ? .lilac : .peach,
                 mem.total > 0 ? "\(Fmt.memory(mem.used)) / \(Fmt.memory(mem.total))" : "…",
                 mem.pressure == .normal ? "Memory used" : "Memory is tight")
            stat("internaldrive", .sand, vol.total > 0 ? Fmt.bytes(vol.free) : "…", "Disk free")
        }
    }

    private func stat(_ symbol: String, _ tone: ClayTone, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IconTile(symbol: symbol, size: 28, tone: tone)
            Text(value).font(.system(size: 16)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clay(radius: 16, glass: false)
    }

    private var quietCard: some View {
        HStack(spacing: 16) {
            Moon(size: 46, rings: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing left running.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Servers, simulators and stacks your agents start will show up here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clay(radius: 20, fill: Theme.heroGradient, glass: false)
    }

    private var autopilot: some View {
        let on = model.prefs.rules.filter(\.enabled)
        let acting = on.filter { model.effectiveMode($0) != .dryRun }
        let next = on.compactMap { r in r.kind.trigger.map { "\(r.name) \($0)" } }.first
        let line = on.isEmpty ? "Paused" : acting.isEmpty ? "\(on.count) rule\(on.count == 1 ? "" : "s"), dry run only"
            : "\(acting.count) of \(on.count) rule\(on.count == 1 ? "" : "s") acting or asking"
        return Button { open { model.go(.autopilot) } } label: {
            HStack(spacing: 10) {
                IconTile(symbol: "sparkles", size: 26, tone: .mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Autopilot · " + line).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                    if let next { Text(next).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .clayInset(radius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        let n = model.sweepResources.count
        return VStack(spacing: 10) {
            if n > 0 {
                Button { open { model.go(.sessions); model.reviewSweep() } } label: {
                    Text("Put away \(n) leftover\(n == 1 ? "" : "s")").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
            }
            HStack {
                Button("Open workspace") { open { model.go(.sessions) } }.buttonStyle(.quiet)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func group<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clay(radius: 18, glass: false)
    }

    private func row<A: View>(symbol: String, title: String, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            action()
        }
    }

    private func label(_ r: Resource) -> String {
        guard let p = r.ports.first else { return r.title }
        return ":\(p) · " + (r.cwd.map { ($0 as NSString).lastPathComponent } ?? r.title)
    }

    private func open(_ then: @escaping () -> Void) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { then() }
    }
}

/// One session in the popover: agent, project, state, and a chip for each thing it has running.
private struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let session: Session
    let open: (@escaping () -> Void) -> Void

    var body: some View {
        let s = session
        VStack(alignment: .leading, spacing: 10) {
            Button { open { model.openSession(s.folder) } } label: {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: s.agent.symbol, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(s.project).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 4)
                            s.badge
                        }
                        Text([s.agent.rawValue, s.branch].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                ForEach(s.resources.prefix(3)) { r in chip(r) }
                if s.resources.count > 3 { Chip(text: "+\(s.resources.count - 3)") }
                Spacer(minLength: 4)
                Text(Fmt.bytes(s.memoryBytes)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
            }

            if s.needsAttention && !s.sweepable.isEmpty {
                Button { open { model.reviewClose(s) } } label: {
                    Text("Stop \(s.sweepable.count == 1 ? "it" : "all \(s.sweepable.count)")").frame(maxWidth: .infinity)
                }
                .buttonStyle(.quiet)
            }
        }
        .padding(12)
        .clay(radius: 18, glass: false)
    }

    private func chip(_ r: Resource) -> some View {
        let text: String = {
            switch r.kind {
            case .server: return r.ports.first.map { ":\($0)" } ?? r.title
            case .stack: return r.stackProject ?? "Docker"
            default: return r.title
            }
        }()
        return Label(text, systemImage: r.kind.symbol)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Theme.tint.shadow(.inner(color: Theme.clayShade, radius: 2, x: 1, y: 1))))
    }
}
