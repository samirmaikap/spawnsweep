import SwiftUI

/// Rules that preview, ask, or act on their own; what each would catch right now; budgets; recent previews.
struct AutopilotPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let rules = model.prefs.rules
        let dryRuns = Array(model.activity.filter { $0.kind == .dryRun }.prefix(3))
        let booted = model.workspace.devices.filter(\.booted).count
        let alertsOff = model.prefs.budgetWarnings ? "" : " Budget warnings are off in Settings."
        let suggestions = RuleTemplate.allCases.filter { t in !rules.contains { RuleTemplate($0.kind) == t } }

        PageScroll {
            PageHeader(title: "A calmer workspace, automatically.", subtitle: "Start with a dry run. Decide what earns your trust.") {
                Button("New rule") { newRule() }.buttonStyle(.primary)
            }

            hero(rules)

            if !model.license.isPro {
                let previewed = model.previewsThisWeek
                ProBanner(title: "Let Autopilot do the cleanup.",
                          line: (previewed > 0 ? "Your rules previewed \(previewed) clean-up\(previewed == 1 ? "" : "s") this week and changed nothing. " : "")
                              + "With Pro, rules can ask first or act on their own, run at the end of the day or on battery, and log a way back for every change.")
            }

            Panel(title: "Your rules") {
                if rules.isEmpty {
                    EmptyState(symbol: "sparkles", title: "No rules yet.",
                               message: "Add a rule to preview what Autopilot would put away. It starts as a dry run.")
                } else {
                    RowList(items: rules) { rule in
                        let (value, caption) = readiness(rule)
                        ResourceRow(symbol: rule.kind.symbol, title: rule.name, subtitle: rule.kind.summary + ".",
                                    value: value, valueCaption: caption) {
                            badge(rule)
                            Button("Run now") { model.runNow(rule) }.buttonStyle(.quiet)
                                .accessibilityLabel("Run \(rule.name) now")
                            Button("Edit") { edit(rule) }.buttonStyle(.quiet)
                                .accessibilityLabel("Edit \(rule.name)")
                        }
                    }
                }
            }

            if !suggestions.isEmpty {
                Panel(title: "Suggested rules") {
                    RowList(items: suggestions) { t in
                        ResourceRow(symbol: t.kind(t.defaultValue).symbol, title: t.defaultName, subtitle: t.kind(t.defaultValue).summary + ".") {
                            Button("Add as dry run") {
                                model.prefs.rules.append(Rule(name: t.defaultName, kind: t.kind(t.defaultValue)))
                            }
                            .buttonStyle(.quiet)
                            .accessibilityLabel("Add \(t.defaultName) as a dry run")
                        }
                    }
                }
            }

            Panel(title: "Resource budgets") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    // The badge describes the current state, so it shows even when warnings are off.
                    BudgetTile(symbol: "iphone", tone: .lilac, title: "Booted simulators",
                               subtitle: "Notify when more than \(model.prefs.budgetSimulators) device\(model.prefs.budgetSimulators == 1 ? " is" : "s are") running. \(booted) booted now.\(alertsOff)",
                               over: booted > model.prefs.budgetSimulators,
                               review: ("Review devices", { model.go(.resources) })) {
                        ClayPicker(title: "Booted simulators", selection: $model.prefs.budgetSimulators,
                                   options: Self.options([1, 2, 3, 4, 5], model.prefs.budgetSimulators).map { ($0, "\($0) device\($0 == 1 ? "" : "s")") })
                    }
                    BudgetTile(symbol: "internaldrive", tone: .sand, title: "Worktree storage",
                               subtitle: "Notify when worktrees grow past this limit."
                                   + (model.disk.scannedAt == nil ? "" : " \(Fmt.bytes(model.disk.worktreeBytes)) now.") + alertsOff,
                               over: Double(model.disk.worktreeBytes) / 1e9 > Double(model.prefs.budgetWorktreeGB),
                               review: ("Review storage", { model.go(.storage) })) {
                        ClayPicker(title: "Worktree storage", selection: $model.prefs.budgetWorktreeGB,
                                   options: Self.options([10, 20, 30, 50, 100], model.prefs.budgetWorktreeGB).map { ($0, "\($0) GB") })
                    }
                }
            }

            Panel(title: "Latest dry run", trailing: {
                if !dryRuns.isEmpty { Button("Review") { model.go(.activity) }.buttonStyle(.quiet) }
            }) {
                if dryRuns.isEmpty {
                    EmptyState(symbol: "clock", title: "Nothing matched yet.",
                               message: "When a dry-run rule matches something, the preview appears here. Nothing changes on your Mac.")
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        RowList(items: dryRuns) { e in
                            let rule = Self.rule(of: e, in: rules)
                            ResourceRow(symbol: Self.symbol(rule?.kind), title: Self.wouldDo(e),
                                        subtitle: "Matched “\(rule?.name ?? e.title.replacingOccurrences(of: " · dry run", with: ""))”",
                                        value: Fmt.time(e.date))
                        }
                        InfoBanner(text: "Nothing changed. \(dryRuns.count == 1 ? "This action is" : "These actions are") waiting for you to review.")
                    }
                }
            }
        }
    }

    // MARK: - Rule tiles

    /// Big number on a rule tile: what it would act on now, or what's waiting for its trigger.
    private func readiness(_ rule: Rule) -> (String?, String?) {
        let now = model.matches(for: rule).count
        if now > 0 { return ("\(now)", model.effectiveMode(rule) == .dryRun ? "would go now" : "ready now") }
        if let trigger = rule.kind.trigger {
            let waiting = model.matches(for: rule, force: true).count
            if waiting > 0 { return ("\(waiting)", "waiting · \(trigger)") }
        }
        return (nil, nil)
    }

    @ViewBuilder private func badge(_ rule: Rule) -> some View {
        if !rule.enabled { Badge(text: "Paused", symbol: "pause") }
        else if Edition.hasPro && rule.mode != .dryRun && !model.license.isPro { Badge(text: "Needs Pro · dry run", style: .warning, symbol: "lock") }
        else {
            switch Edition.hasPro ? rule.mode : .dryRun {
            case .dryRun: Badge(text: "Dry run")
            case .ask: Badge(text: "Asks first", style: .pinned, symbol: "bell")
            case .auto: Badge(text: "Automatic", style: .active)
            }
        }
    }

    // MARK: - Hero

    private func hero(_ rules: [Rule]) -> some View {
        let on = rules.filter(\.enabled)
        let acting = on.filter { model.effectiveMode($0) == .auto }.count, asking = on.filter { model.effectiveMode($0) == .ask }.count
        let watching = on.count - acting - asking
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let recent = model.activity.filter { $0.date > weekAgo && ($0.dedupeKey?.hasPrefix("rule:") ?? false) }
        let done = recent.filter { $0.kind == .cleanup }.count, previews = recent.filter { $0.kind == .dryRun }.count
        let (title, line): (String, String) = {
            if on.isEmpty {
                return ("Autopilot is resting.", rules.isEmpty ? "Add a rule to start with a dry run." : "Every rule is paused. Nothing runs on its own.")
            }
            var parts: [String] = []
            if acting > 0 { parts.append("\(acting) act\(acting == 1 ? "s" : "") on \(acting == 1 ? "its" : "their") own") }
            if asking > 0 { parts.append("\(asking) ask\(asking == 1 ? "s" : "") first") }
            if watching > 0 { parts.append("\(watching) preview\(watching == 1 ? "s" : "") only") }
            return (acting + asking == 0 ? "Autopilot is observing." : "Autopilot is on.",
                    "\(on.count) rule\(on.count == 1 ? "" : "s") on: " + parts.joined(separator: ", ") + ".")
        }()
        return HeroCard(padding: 32) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).heading(22)
                    Text(line).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                StatBlock(value: "\(done)", label: "put away this week")
                StatBlock(value: "\(previews)", label: "previewed this week")
            }
        }
    }

    // MARK: - Dry-run rows

    private static func rule(of e: ActivityEntry, in rules: [Rule]) -> Rule? {
        for case .reviewRule(let id) in e.recovery { return rules.first { $0.id == id } }
        return nil
    }

    /// Entries read "Would shut down iPhone 17. Nothing changed." — keep the first sentence.
    private static func wouldDo(_ e: ActivityEntry) -> String {
        e.detail.replacingOccurrences(of: ". Nothing changed.", with: "")
    }

    private static func symbol(_ kind: RuleKind?) -> String { kind?.symbol ?? "sparkles" }

    /// Menu options, plus the current value if it was set elsewhere.
    private static func options(_ base: [Int], _ current: Int) -> [Int] {
        base.contains(current) ? base : (base + [current]).sorted()
    }

    // MARK: - Dialogs

    private func newRule() {
        let model = model
        let draft = RuleDraft(template: .simulators)
        var spec = DialogSpec(icon: "sparkles", title: "A little less to remember.", subtitle: "Pick what to watch, when, and how much to trust it.",
                              confirmTitle: "Save rule")
        spec.custom = AnyView(RuleForm(draft: draft))
        spec.action = DialogSpec.followUp {
            model.prefs.rules.append(Rule(name: draft.finalName, kind: draft.kind, mode: draft.mode))
            model.dismissDialog()
        }
        model.present(spec)
    }

    private func edit(_ rule: Rule) {
        let model = model
        let draft = RuleDraft(rule)
        let id = rule.id
        var spec = DialogSpec(icon: rule.kind.symbol, title: "Tune “\(rule.name)”.", subtitle: rule.kind.summary + ".", confirmTitle: "Save rule")
        spec.custom = AnyView(RuleForm(draft: draft, ruleID: id))
        spec.action = DialogSpec.followUp {
            if let i = model.prefs.rules.firstIndex(where: { $0.id == id }) {
                var r = model.prefs.rules[i]
                r.name = draft.finalName
                r.kind = draft.kind
                r.mode = draft.mode
                r.enabled = draft.enabled
                model.prefs.rules[i] = r
            }
            model.dismissDialog()
        }
        model.present(spec)
    }
}

// MARK: - Dialog confirm for settings and setup

extension DialogSpec {
    /// Confirm action for dialogs that change a setting rather than a resource. `work` runs off the main thread and
    /// returns an error message or nil; `then` runs on the main actor and closes the dialog or presents its own result.
    /// This skips the generic result screen, whose "Nothing changed." would be wrong for a saved setting.
    static func followUp(work: @escaping @Sendable () -> String?,
                         then: @escaping @MainActor @Sendable (String?) -> Void) -> @Sendable (Set<String>) -> Actions.Outcome {
        { _ in
            let error = work()
            DispatchQueue.main.sync { MainActor.assumeIsolated { then(error) } }
            return Actions.Outcome()
        }
    }

    static func followUp(_ then: @escaping @MainActor @Sendable () -> Void) -> @Sendable (Set<String>) -> Actions.Outcome {
        followUp(work: { nil }, then: { _ in then() })
    }
}

// MARK: - Rule templates and form

/// The rule kinds the engine runs, with the values offered for each.
private enum RuleTemplate: String, CaseIterable, Identifiable {
    case simulators, leftovers, endOfDay, battery, worktrees, recycle, lowDisk
    var id: Self { self }

    init(_ kind: RuleKind) {
        switch kind {
        case .simulatorIdle: self = .simulators
        case .endedLeftovers: self = .leftovers
        case .slimIdleWorktrees: self = .worktrees
        case .recycleMerged: self = .recycle
        case .endOfDay: self = .endOfDay
        case .onBattery: self = .battery
        case .lowDisk: self = .lowDisk
        }
    }

    var resource: String {
        switch self {
        case .simulators: return "Booted simulators"
        case .leftovers: return "Leftovers from ended sessions"
        case .endOfDay: return "Everything, at the end of the day"
        case .battery: return "Everything, while on battery"
        case .worktrees: return "Idle worktrees"
        case .recycle: return "Merged worktrees"
        case .lowDisk: return "Worktrees, when the disk runs low"
        }
    }
    var timing: String {
        switch self {
        case .simulators: return "When idle for"
        case .leftovers: return "After the session ends"
        case .endOfDay: return "Starting at"
        case .battery: return ""
        case .worktrees, .recycle: return "When untouched for"
        case .lowDisk: return "When free space is below"
        }
    }
    var action: String {
        switch self {
        case .simulators: return "Shut down the simulator. Its apps and data stay."
        case .leftovers: return "Stop what the session left running. Pinned sessions are skipped."
        case .endOfDay: return "Stop what finished sessions left running and shut down simulators no active session uses."
        case .battery: return "When your Mac is unplugged, shut down idle simulators and stop what finished sessions left running."
        case .worktrees: return "Slim the worktree. Source, local edits and .env files stay."
        case .recycle: return "Move it to the recycle bin. The branch stays in git, .env files are saved, and Restore brings it back."
        case .lowDisk: return "Slim the largest idle worktrees until there's room again. Source, local edits and .env files stay."
        }
    }
    var options: [Int] {
        switch self {
        case .simulators: return [1, 2, 4, 8, 24]
        case .leftovers: return [10, 15, 30, 60, 120]
        case .endOfDay: return [17, 18, 19, 20, 21, 22]
        case .battery: return []
        case .worktrees: return [3, 7, 14, 30, 60]
        case .recycle: return [3, 7, 14, 30]
        case .lowDisk: return [10, 20, 30, 50]
        }
    }
    var defaultValue: Int {
        switch self {
        case .simulators: return 2
        case .leftovers: return 30
        case .endOfDay: return 19
        case .battery: return 0
        case .worktrees: return 14
        case .recycle: return 7
        case .lowDisk: return 20
        }
    }
    var defaultName: String {
        switch self {
        case .simulators: return "Simulator bedtime"
        case .leftovers: return "Finished means finished"
        case .endOfDay: return "End of day"
        case .battery: return "Battery saver"
        case .worktrees: return "Quiet worktrees, slimmed"
        case .recycle: return "Merged work, tucked away"
        case .lowDisk: return "Room to breathe"
        }
    }
    func label(_ v: Int) -> String {
        switch self {
        case .simulators: return "\(v) hour\(v == 1 ? "" : "s")"
        case .leftovers: return "\(v) minutes"
        case .endOfDay: return Fmt.hour(v)
        case .battery: return ""
        case .worktrees, .recycle: return "\(v) day\(v == 1 ? "" : "s")"
        case .lowDisk: return "\(v) GB"
        }
    }
    func kind(_ v: Int) -> RuleKind {
        switch self {
        case .simulators: return .simulatorIdle(hours: v)
        case .leftovers: return .endedLeftovers(minutes: v)
        case .endOfDay: return .endOfDay(hour: v)
        case .battery: return .onBattery
        case .worktrees: return .slimIdleWorktrees(days: v)
        case .recycle: return .recycleMerged(days: v)
        case .lowDisk: return .lowDisk(gb: v)
        }
    }
}

@MainActor @Observable
private final class RuleDraft {
    var name: String
    var template: RuleTemplate
    var value: Int
    var mode = RuleMode.dryRun
    var enabled = true
    var confirmDelete = false

    init(template: RuleTemplate) {
        self.template = template
        name = template.defaultName
        value = template.defaultValue
    }

    init(_ rule: Rule) {
        name = rule.name
        template = RuleTemplate(rule.kind)
        switch rule.kind {
        case .simulatorIdle(let v), .endedLeftovers(let v), .slimIdleWorktrees(let v), .recycleMerged(let v),
             .endOfDay(let v), .lowDisk(let v): value = v
        case .onBattery: value = 0
        }
        mode = Edition.hasPro ? rule.mode : .dryRun
        enabled = rule.enabled
    }

    var kind: RuleKind { template.kind(value) }
    var finalName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? template.defaultName : n
    }
}

private struct RuleForm: View {
    @Environment(AppModel.self) private var model
    @Bindable var draft: RuleDraft
    var ruleID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Rule name") {
                TextField("Rule name", text: $draft.name)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .clayInset(radius: 12)
            }
            field("Watch") {
                ClayPicker(title: "Watch", selection: $draft.template, options: RuleTemplate.allCases.map { ($0, $0.resource) }, fullWidth: true)
            }
            if !draft.template.options.isEmpty {
                field(draft.template.timing) {
                    let opts = draft.template.options.contains(draft.value) ? draft.template.options : (draft.template.options + [draft.value]).sorted()
                    ClayPicker(title: draft.template.timing, selection: $draft.value,
                               options: opts.map { ($0, draft.template.label($0)) }, fullWidth: true)
                }
            }
            field("Action") {
                Text(draft.template.action).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            field("When it matches") {
                if !Edition.hasPro {
                    ChipTabs(selection: $draft.mode, options: [(.dryRun, RuleMode.dryRun.label)])
                } else if model.license.isPro {
                    ChipTabs(selection: $draft.mode, options: RuleMode.allCases.map { ($0, $0.label) })
                } else {
                    // Ask first and Automatic are Pro: shown, locked, and one click from the license screen.
                    HStack(spacing: 8) {
                        ChipTabs(selection: $draft.mode, options: [(.dryRun, RuleMode.dryRun.label)])
                        ForEach([RuleMode.ask, .auto], id: \.self) { m in
                            Button { model.dismissDialog(); model.go(.settings) } label: {
                                Label(m.label, systemImage: "lock.fill").font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.quiet)
                            .help("\(m.label) is part of SpawnSweep Pro")
                        }
                    }
                }
            }
            if Edition.hasPro && !model.license.isPro && draft.mode != .dryRun {
                WarningBanner(text: "This rule is set to \(draft.mode.label.lowercased()), which needs SpawnSweep Pro. Until then it previews only.")
            }
            switch draft.mode {
            case .dryRun: InfoBanner(text: "Only records what it would do, in Activity. Nothing on your Mac changes.", symbol: "eye")
            case .ask: InfoBanner(text: "Sends a notification. Review opens the preview; Not today snoozes the rule until tomorrow.", symbol: "bell")
            case .auto: WarningBanner(text: "Acts without asking: \(draft.kind.summary.lowercased()). Each change is logged in Activity with its way back.")
            }
            if ruleID != nil { editControls }
        }
        .onChange(of: draft.template) { old, new in
            if draft.name == old.defaultName || draft.name.isEmpty { draft.name = new.defaultName }
            draft.value = new.defaultValue
        }
    }

    @ViewBuilder private var editControls: some View {
        toggleRow("Rule is on", $draft.enabled)
        if draft.confirmDelete {
            HStack(spacing: 10) {
                Text("Delete “\(draft.finalName)”? This can't be undone.").font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                Button("Keep") { draft.confirmDelete = false }.buttonStyle(.quiet)
                Button("Delete") {
                    if let id = ruleID { model.prefs.rules.removeAll { $0.id == id } }
                    model.dismissDialog()
                }
                .buttonStyle(QuietButtonStyle(destructive: true))
            }
        } else {
            Button("Delete rule") { draft.confirmDelete = true }.buttonStyle(QuietButtonStyle(destructive: true))
        }
    }

    /// A switch on its own pressed-in clay segment.
    private func toggleRow(_ label: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            Spacer()
            Toggle(label, isOn: isOn).toggleStyle(.switch).tint(Theme.accent).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .clayInset(radius: 14)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            content()
        }
    }
}

/// One budget on a clay tile: icon, title and caption, the control at the bottom.
private struct BudgetTile<Control: View>: View {
    let symbol: String
    let tone: ClayTone
    let title: String
    let subtitle: String
    /// Current usage is past the budget: amber badge plus a link to where it can be reduced.
    let over: Bool
    let review: (title: String, action: () -> Void)
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(symbol: symbol, size: 44, tone: tone)
            HStack(spacing: 10) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                if over { Badge(text: "Over budget", style: .warning) }
            }
            .padding(.top, 16)
            Text(subtitle).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            if over { NavLink(title: review.title, action: review.action).padding(.top, 8) }
            Spacer(minLength: 14)
            control()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clay(radius: 22, glass: false)
    }
}
