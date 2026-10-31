import SwiftUI

/// The preview dialog every resource-changing action goes through (§8):
/// what's affected, what happens, what stays, and a specific confirm button.
struct DialogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let spec = model.dialog {
            VStack(alignment: .leading, spacing: 0) {
                IconTile(symbol: spec.icon, size: 56)
                    .padding(.bottom, 22)
                Text(title(spec)).heading(24)
                Text(subtitle(spec)).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                switch spec.phase {
                case .preview: preview(spec)
                case .running: running
                case .done(_, let failures): done(failures)
                }
            }
            .padding(34)
            .frame(width: 520)
            .clay(radius: 28)
        }
    }

    private func title(_ s: DialogSpec) -> String {
        switch s.phase {
        case .preview: return s.title
        case .running: return "Working…"
        case .done(_, let f): return f.isEmpty ? "Done." : "Partly done."
        }
    }

    private func subtitle(_ s: DialogSpec) -> String {
        switch s.phase {
        case .preview: return s.subtitle
        case .running: return s.runningNote
        case .done(let summary, _): return summary
        }
    }

    @ViewBuilder private func preview(_ spec: DialogSpec) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !spec.items.isEmpty {
                // ponytail: long previews scroll inside a fixed box; short ones keep their natural height.
                Group {
                    if spec.items.count > 6 { ScrollView { itemList(spec) }.frame(height: 300) } else { itemList(spec) }
                }
                .clayInset(radius: 16)
                .padding(.top, 20)
            }
            if let custom = spec.custom { custom.padding(.top, 20) }
            VStack(spacing: 10) {
                if let w = spec.warning { WarningBanner(text: w) }
                ForEach(spec.notes, id: \.self) { InfoBanner(text: $0) }
            }
            .padding(.top, 20)
            HStack(spacing: 10) {
                Spacer()
                if spec.action != nil {
                    Button("Cancel") { model.dismissDialog() }.buttonStyle(.quiet)
                        .keyboardShortcut(.cancelAction)
                }
                Button(spec.confirmTitle) {
                    if spec.action != nil { model.confirmDialog() } else { model.dismissDialog() }
                }
                .buttonStyle(spec.destructive ? AnyButtonStyle(DestructiveButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle(large: true)))
                .keyboardShortcut(spec.destructive ? nil : KeyboardShortcut.defaultAction)   // Return never confirms a permanent delete
                .disabled(spec.action != nil && spec.items.contains { !$0.required } && !spec.items.contains(where: \.checked))
            }
            .padding(.top, 24)
        }
    }

    private func itemList(_ spec: DialogSpec) -> some View {
        VStack(spacing: 0) {
            ForEach(spec.items) { item in
                Button { model.toggleItem(item.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(item.checked ? Theme.accent : Theme.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label).font(.system(size: 14)).foregroundStyle(Theme.text)
                            if let w = item.warning {
                                Label(w, systemImage: "exclamationmark.triangle.fill").font(.meta).foregroundStyle(Theme.amberText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Text(item.detail).font(.meta).foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.required)
                if item.id != spec.items.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private var running: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("This can take a moment for large folders.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
        .padding(.top, 24)
    }

    @ViewBuilder private func done(_ failures: [String]) -> some View {
        let lines = Self.grouped(failures)
        VStack(alignment: .leading, spacing: 10) {
            // Same rule as the preview: a long list scrolls in a fixed box, so Done always stays on screen.
            let list = VStack(spacing: 10) { ForEach(lines, id: \.self) { WarningBanner(text: $0) } }
            if lines.count > 4 { ScrollView { list }.frame(height: 260) } else { list }
            if !failures.isEmpty {
                InfoBanner(text: "Anything that couldn't change was left exactly as it was.")
            }
            HStack {
                Button("View activity") { model.dismissDialog(); model.go(.activity) }.buttonStyle(.link).foregroundStyle(Theme.accent)
                Spacer()
                Button("Done") { model.dismissDialog() }.buttonStyle(.primaryLarge).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(.top, 20)
    }

    /// Folds "Skipped DerivedData · A: Xcode is open." and its 24 siblings into "Skipped 25 DerivedData items: Xcode is open.".
    /// Lines group by verb, category (the part before " · ") and reason; anything else passes through. First-seen order.
    static func grouped(_ failures: [String]) -> [String] {
        let verbs = ["Skipped ", "Couldn't remove ", "Kept "]
        var order: [String] = []
        var groups: [String: (line: String, verb: String, category: String?, reason: String, count: Int)] = [:]
        for f in failures {
            var key = f, verb = "", category: String?, reason = ""
            if let v = verbs.first(where: f.hasPrefix), let colon = f.range(of: ": ") {
                verb = v
                let name = String(f[f.index(f.startIndex, offsetBy: v.count)..<colon.lowerBound])
                category = name.range(of: " · ").map { String(name[..<$0.lowerBound]) }
                reason = String(f[colon.upperBound...])
                key = v + "|" + (category ?? "") + "|" + reason
            }
            if groups[key] == nil { order.append(key); groups[key] = (f, verb, category, reason, 0) }
            groups[key]!.count += 1
        }
        return order.map { k in
            let g = groups[k]!
            guard g.count > 1, !g.verb.isEmpty else { return g.line }
            return "\(g.verb)\(g.count) \(g.category.map { "\($0) items" } ?? "items"): \(g.reason)"
        }
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 13)
            .background(Theme.destructive.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Type-erased button style, so a dialog can pick primary or destructive at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
