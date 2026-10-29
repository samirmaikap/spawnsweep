import Foundation
import AppKit
import IOKit.ps

/// One thing a rule would act on right now. `id` is also the Activity dedupe key, so each target is
/// handled once per moment it became eligible (a fresh boot, a new session, a new day starts over).
struct RuleMatch: @unchecked Sendable {
    let id: String
    let label: String
    let detail: String
    let wouldDo: String
    let did: String
    let act: @Sendable () -> Actions.Outcome
}

enum Power {
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    static var freeDiskBytes: Int64 {
        let v = try? URL(fileURLWithPath: Shell.home).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}

extension AppModel {
    // MARK: - Matching

    /// What `rule` would act on now. One list drives dry runs, Ask first, Automatic and Run now, so a preview
    /// always shows exactly what the rule does. `force` skips the trigger (time of day, battery, free space).
    func matches(for rule: Rule, force: Bool = false, now: Date = Date()) -> [RuleMatch] {
        let p = "rule:\(rule.id):"
        let day = Self.dayStamp(now)
        switch rule.kind {
        case .simulatorIdle(let hours):
            return idleSimulators.compactMap { d in
                guard let booted = d.bootedAt, now.timeIntervalSince(booted) > Double(hours) * 3600 else { return nil }
                return simulatorMatch(d, key: p + d.udid + ":\(Int(booted.timeIntervalSince1970))",
                                      detail: "Idle \(Fmt.duration(now.timeIntervalSince(booted)))")
            }
        case .endedLeftovers(let minutes):
            return finishedSessions.compactMap { s in
                let since = endedAt(s)
                guard now.timeIntervalSince(since) > Double(minutes) * 60 else { return nil }
                return leftoversMatch(s, key: p + s.folder + ":\(Int(since.timeIntervalSince1970))")
            }
        case .slimIdleWorktrees(let days):
            return idleWorktrees.compactMap { w in
                guard let used = w.lastUsed, now.timeIntervalSince(used) > Double(days) * 86400 else { return nil }
                return slimMatch(w, key: p + w.path + ":\(Int(used.timeIntervalSince1970))")
            }
        case .recycleMerged(let days):
            return disk.worktrees.compactMap { w in
                // A Claude app worktree may belong to a saved chat; only a person decides that (Run now shows a warning).
            guard w.status == .merged, Actions.canRecycle(w) == nil, force || !w.mayBeClaudeManaged, let used = w.lastUsed,
                      now.timeIntervalSince(used) > Double(days) * 86400 else { return nil }
                let name = "\(w.repoName) / \(w.branch ?? "detached")"
                return RuleMatch(id: p + w.path, label: name, detail: w.sizeBytes.map(Fmt.bytes) ?? "",
                                 wouldDo: "Would move \(name) to the recycle bin", did: "Moved \(name) to the recycle bin") {
                    Self.outcome(Actions.recycle(w), freed: w.sizeBytes)
                }
            }
        case .endOfDay(let hour):
            guard force || Calendar.current.component(.hour, from: now) >= hour else { return [] }
            return settledSessions(now).map { leftoversMatch($0, key: p + day + ":" + $0.folder) }
                + idleSimulators.map { simulatorMatch($0, key: p + day + ":" + $0.udid, detail: "Booted") }
        case .onBattery:
            guard force || Power.onBattery else { return [] }
            return settledSessions(now).map { leftoversMatch($0, key: p + $0.folder + ":\(Int(($0.lastActivity ?? now).timeIntervalSince1970))") }
                + idleSimulators.map { simulatorMatch($0, key: p + $0.udid + ":\(Int(($0.bootedAt ?? now).timeIntervalSince1970))", detail: "Booted") }
        case .lowDisk(let gb):
            let free = Power.freeDiskBytes, target = Int64(gb) * 1_000_000_000
            guard force || free < target else { return [] }
            // Biggest first, and only as many as it takes to get back above the line.
            var need = force ? Int64.max : target - free
            var out: [RuleMatch] = []
            for w in idleWorktrees.sorted(by: { ($0.slimBytes ?? 0) > ($1.slimBytes ?? 0) }) where need > 0 {
                out.append(slimMatch(w, key: p + w.path + ":" + day))
                need -= w.slimBytes ?? 0
            }
            return out
        }
    }

    /// Booted simulators that no active or pinned session is using. A simulator no session started is left alone
    /// while Xcode is open: it's probably being debugged, and boot time says nothing about whether it's idle.
    var idleSimulators: [Device] {
        let sessions = workspace.sessions
        let busy = Set(sessions.filter { $0.state.isActive || $0.pinned }.flatMap(\.resources).compactMap(\.udid))
        let agentMade = Set(sessions.flatMap(\.resources).compactMap(\.udid))
        let xcodeOpen = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.dt.Xcode" }
        return workspace.devices.filter { d in
            d.booted && !d.android && !busy.contains(d.udid) && (agentMade.contains(d.udid) || !xcodeOpen)
        }
    }

    /// When a session ended: the later of its last folder change and the first scan that saw it ended.
    func endedAt(_ s: Session) -> Date {
        max(s.lastActivity ?? .distantPast, endedSeen[s.folder] ?? .distantPast)
    }

    /// Finished sessions that ended at least ten minutes ago, for the time and battery rules.
    func settledSessions(_ now: Date) -> [Session] {
        finishedSessions.filter { now.timeIntervalSince(endedAt($0)) > 600 }
    }

    /// Notes the first time each session is seen ended, and forgets sessions that came back or went away.
    private func noteEndedSessions() {
        let ended = Set(workspace.sessions.filter(\.state.isEnded).map(\.folder))
        for f in ended where endedSeen[f] == nil { endedSeen[f] = Date() }
        endedSeen = endedSeen.filter { ended.contains($0.key) }
    }

    /// Ask first and Automatic need SpawnSweep Pro in the build and an active license; otherwise every rule previews only.
    func effectiveMode(_ r: Rule) -> RuleMode { r.mode.effective(hasPro: Edition.hasPro, licensed: license.isPro) }

    /// Ended sessions with something still running (pinned and protected resources are already left out).
    var finishedSessions: [Session] { workspace.sessions.filter { $0.state.isEnded && !$0.sweepable.isEmpty } }

    /// Worktrees with enough rebuildable weight to be worth slimming, and nothing running in them.
    var idleWorktrees: [Worktree] { disk.worktrees.filter { $0.status != .inUse && ($0.slimBytes ?? 0) > 50_000_000 } }

    private func simulatorMatch(_ d: Device, key: String, detail: String) -> RuleMatch {
        RuleMatch(id: key, label: d.name, detail: detail, wouldDo: "Would shut down \(d.name)", did: "Shut down \(d.name)") {
            Actions.stop(Resource(id: "sim:\(d.udid)", kind: .simulator, title: d.name, detail: "", memoryBytes: d.memoryBytes, udid: d.udid))
        }
    }

    private func leftoversMatch(_ s: Session, key: String) -> RuleMatch {
        let rs = s.sweepable
        let n = "\(rs.count) resource\(rs.count == 1 ? "" : "s")"
        return RuleMatch(id: key, label: s.project, detail: "\(n) · \(Fmt.bytes(rs.reduce(0) { $0 + $1.memoryBytes }))",
                         wouldDo: "Would stop \(n) from \(s.project)", did: "Stopped \(n) from \(s.project)") { Actions.stopAll(rs) }
    }

    private func slimMatch(_ w: Worktree, key: String) -> RuleMatch {
        let name = "\(w.repoName) / \(w.branch ?? "detached")"
        return RuleMatch(id: key, label: name, detail: Fmt.bytes(w.slimBytes ?? 0),
                         wouldDo: "Would slim \(name)", did: "Slimmed \(name)") { Actions.slim(w) }
    }

    static func dayStamp(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - Running

    /// Called after every scan. Dry runs are recorded here; Ask first and Automatic rules are handed to SpawnSweep Pro, which notifies or acts.
    func runAutopilot() {
        noteEndedSessions()
        var acting: [(Rule, [RuleMatch])] = []
        var logged = false
        for rule in prefs.rules where rule.enabled {
            let fresh = matches(for: rule).filter { m in !activity.contains { $0.dedupeKey == m.id } }
            guard !fresh.isEmpty else { continue }
            switch effectiveMode(rule) {
            case .dryRun:
                // Dry runs get their own key, so switching the rule to act later still handles these.
                for m in fresh where Store.log(ActivityEntry(kind: .dryRun, title: "\(rule.name) · dry run", detail: "\(m.wouldDo). Nothing changed.",
                                                              recovery: [.reviewRule(id: rule.id)], dedupeKey: m.id + ":dry"),
                                               historyDays: prefs.historyDays) { logged = true }
            case .ask, .auto:
                acting.append((rule, fresh))
            }
        }
        if logged { reloadFiles() }
        Edition.pro?.act(self, acting)
    }

    /// Run now: the rule's matches as a preview, trigger ignored. Ask-first notifications pass `force: false`,
    /// so the preview lists what the notification described and nothing more.
    func runNow(_ rule: Rule, force: Bool = true) {
        let ms = matches(for: rule, force: force)
        var spec = DialogSpec(icon: rule.kind.symbol, title: "Run “\(rule.name)” now?", subtitle: rule.kind.summary + ".",
                              items: ms.map { DialogItem(id: $0.id, label: $0.label, detail: $0.detail) },
                              notes: [rule.kind.note], confirmTitle: "Run now")
        spec.activityTitle = "Ran “\(rule.name)”"
        let byID = Dictionary(ms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        spec.action = { chosen in
            var o = Actions.Outcome()
            for id in chosen.sorted() { if let m = byID[id] { o.merge(m.act()) } }
            return o
        }
        if ms.isEmpty {
            spec.title = "Nothing to put away."
            spec.subtitle = "Nothing matches “\(rule.name)” right now."
            spec.action = nil
            spec.confirmTitle = "OK"
        }
        present(spec)
    }
}
