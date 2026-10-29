import SwiftUI

/// ⌘K (or ⌘⇧L from anywhere): find a project, port, session or page.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    struct Hit: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let run: () -> Void
    }

    private var hits: [Hit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        var out: [Hit] = []
        for s in model.workspace.sessions {
            out.append(Hit(id: "s:\(s.folder)", symbol: s.agent.symbol, title: s.project,
                           detail: "\(s.agent.rawValue) · \(s.branch ?? "session") · \(s.resources.count) running") { model.openSession(s.folder) })
        }
        for r in model.workspace.allResources where !r.ports.isEmpty {
            let owner = model.workspace.session(for: r)?.project ?? "not tied to a session"
            out.append(Hit(id: "p:\(r.id)", symbol: "point.3.connected.trianglepath.dotted", title: ":\(r.ports.map(String.init).joined(separator: ", :"))",
                           detail: "\(r.title) · \(owner) · Free port") { model.go(.ports); model.reviewStop(r) })
        }
        for g in model.disk.repos {
            out.append(Hit(id: "r:\(g.path)", symbol: "arrow.triangle.branch", title: g.name,
                           detail: "\(g.worktrees.count) worktrees · \(Fmt.bytes(g.totalBytes))") { model.openRepo(g.path) })
        }
        for p in Page.sidebar + (Edition.hasPro ? [.junk, .largeFiles, .pro] : []) + [.welcome] {
            out.append(Hit(id: "g:\(p.rawValue)", symbol: p.symbol, title: p.title, detail: "Go to page") { model.go(p) })
        }
        out.append(Hit(id: "a:sweep", symbol: "moon", title: "End-of-day sweep", detail: "Review what finished sessions left running") {
            model.go(.sessions); model.reviewSweep()
        })
        guard !q.isEmpty else { return Array(out.prefix(9)) }
        return out.filter { ($0.title + " " + $0.detail).lowercased().contains(q) }.prefix(9).map { $0 }
    }

    var body: some View {
        let list = hits
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Find a project, port, or session…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { pick(list) }
            }
            .padding(18)
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(spacing: 2) {
                if list.isEmpty {
                    Text("No matches for “\(query)”.").font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(20)
                }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, h in
                    Button { selected = i; pick(list) } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: h.symbol, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title).font(h.title.hasPrefix(":") ? .mono(14) : .system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                                Text(h.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                            Spacer()
                            if i == selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(i == selected ? Theme.tint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 560)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 40, y: 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 110)
        .onAppear { focused = true; selected = 0 }
        .onChange(of: query) { selected = 0 }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(list.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
    }

    private func pick(_ list: [Hit]) {
        guard list.indices.contains(selected) else { return }
        let h = list[selected]
        model.paletteOpen = false
        query = ""
        h.run()
    }
}
