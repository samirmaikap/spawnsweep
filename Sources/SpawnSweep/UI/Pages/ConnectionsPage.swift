import SwiftUI
import AppKit

/// Agent connections (observing vs. the cleanup hook) and the local MCP server.
struct ConnectionsPage: View {
    @Environment(AppModel.self) private var model

    private static let agents: [(agent: Agent, name: String, symbol: String)] = [
        (.claudeCode, "Claude Code", "terminal"),
        (.codex, "Codex", "terminal"),
        (.cursor, "Cursor", "cursorarrow"),
        (.claudeApp, "Claude app", "bubble.left"),
        (.gemini, "Gemini & Aider", "terminal")
    ]

    var body: some View {
        let _ = model.dialog?.id   // re-read statuses when a setup dialog opens or closes
        let statuses = Self.agents.map { Integrations.status(of: $0.agent) }
        let mcpOn = Integrations.mcpConfigured()

        PageScroll {
            PageHeader(title: "Good habits, built in.", subtitle: "Help your agents reuse what exists and put away what they start.")

            Panel(title: "Agent connections") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(Array(Self.agents.enumerated()), id: \.offset) { i, a in
                        tile(a.agent, a.name, a.symbol, statuses[i])
                    }
                }
            }

            Panel(title: "SpawnSweep MCP", boxed: true) {
                HStack(alignment: .top, spacing: 20) {
                    IconTile(symbol: "point.3.connected.trianglepath.dotted", size: 56)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Let agents find and reuse a running server before starting another.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        Text("“Is a dev server already running for this repo?”")
                            .font(.mono(13)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        HStack(spacing: 10) {
                            Button("Configure MCP") { configureMCP(added: mcpOn) }.buttonStyle(.primaryLarge)
                            Chip(text: "Local connection only")
                            if mcpOn { Badge(text: "Added to Claude Code", style: .success) }
                        }
                    }
                }
            }
        }
    }

    private func tile(_ agent: Agent, _ name: String, _ symbol: String, _ status: Integrations.Status) -> some View {
        let detail: String
        let connected: Bool
        switch status {
        case .connected(let s): detail = s; connected = true
        case .available(let s): detail = s; connected = false
        case .notFound: detail = "Not found on this Mac"; connected = false
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconTile(symbol: symbol, size: 52)
                Spacer(minLength: 10)
                if connected { Badge(text: "Connected", style: .success) }
                else if status == .notFound { Badge(text: "Not found") }
            }
            Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).padding(.top, 16)
            Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            Spacer(minLength: 14)
            Button(connected ? "Configure" : status == .notFound ? "Details" : "Connect") { open(agent, name, status) }
                .buttonStyle(.quiet)
                .accessibilityLabel("\(connected ? "Configure" : "Connect") \(name)")
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .clay(radius: 22, glass: false)
    }

    // MARK: - Dialogs

    private func open(_ agent: Agent, _ name: String, _ status: Integrations.Status) {
        switch agent {
        case .claudeCode: claudeCode(status)
        case .claudeApp: claudeApp(status)
        default: observed(agent, name, status)
        }
    }

    private func claudeCode(_ status: Integrations.Status) {
        let model = model
        let installed = Integrations.claudeHookInstalled()
        var spec = DialogSpec(icon: "terminal",
                              title: installed ? "Claude Code is connected." : "Connect Claude Code.",
                              subtitle: "Two ways SpawnSweep works with Claude Code.",
                              notes: [installed ? "Removing the hook leaves the rest of settings.json as it is."
                                                : "Your current settings.json is copied to settings.json.bak first. Everything else in it stays as it is."],
                              confirmTitle: installed ? "Remove hook" : "Install hook",
                              custom: AnyView(ClaudeCodeSetup(installed: installed)))
        if status == .notFound {
            spec.warning = "Claude Code isn't set up on this Mac yet (there's no ~/.claude folder). Install it, then come back to add the hook."
            spec.confirmTitle = "OK"
        } else {
            spec.action = DialogSpec.followUp(work: {
                do {
                    if installed { try Integrations.removeClaudeHook() } else { _ = try Integrations.installClaudeHook() }
                    return nil
                } catch { return error.localizedDescription }
            }, then: { error in
                if let error {
                    model.present(DialogSpec(icon: "terminal", title: "The hook wasn't changed.",
                                             subtitle: "~/.claude/settings.json is as it was.", warning: error, confirmTitle: "OK"))
                } else if installed {
                    model.present(DialogSpec(icon: "terminal", title: "Hook removed.",
                                             subtitle: "SpawnSweep still observes Claude Code sessions. Nothing stops on its own when one ends.",
                                             confirmTitle: "Done"))
                } else {
                    model.present(DialogSpec(icon: "terminal", title: "Claude Code is connected.",
                                             subtitle: "When a session ends, SpawnSweep puts away what it started.",
                                             notes: ["Your previous settings are saved at ~/.claude/settings.json.bak."],
                                             confirmTitle: "Done"))
                }
            })
        }
        model.present(spec)
    }

    private func claudeApp(_ status: Integrations.Status) {
        let model = model
        var spec = DialogSpec(icon: "bubble.left", title: "Claude app worktrees.",
                              subtitle: status == .notFound ? "The Claude app isn't in /Applications." : "Managed by the Claude app.",
                              notes: ["SpawnSweep shows the app's worktrees in Storage. Any of them can be slimmed. Once a worktree's work is merged and nothing is running in it, it can also go to the recycle bin, where it can be restored. Unmerged ones stay put; remove those from Claude › Settings › Storage."],
                              confirmTitle: "OK")
        if status != .notFound {
            spec.confirmTitle = "Open Claude"
            spec.action = DialogSpec.followUp {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
                model.dismissDialog()
            }
        }
        model.present(spec)
    }

    private func observed(_ agent: Agent, _ name: String, _ status: Integrations.Status) {
        var notes = ["Nothing is installed and \(name) settings stay as they are. There's no session-end hook for \(name) yet, so leftovers are put away from Sessions or by Autopilot."]
        switch agent {
        case .codex: notes.insert("Worktrees in ~/.codex/worktrees appear in Storage.", at: 0)
        case .cursor: notes.insert("Worktrees in ~/.cursor/worktrees appear in Storage. Cursor's agent is tracked while cursor-agent runs.", at: 0)
        default: break
        }
        let subtitle: String
        switch status {
        case .connected(let s), .available(let s): subtitle = s + "."
        case .notFound: subtitle = "\(name) isn't installed on this Mac."
        }
        model.present(DialogSpec(icon: "terminal", title: "\(name) sessions.", subtitle: subtitle,
                                 notes: notes, confirmTitle: "Done",
                                 custom: AnyView(Explainer(text: "SpawnSweep finds \(name) by scanning running processes. For each session it sees the folder it works in and what it started: dev servers, watchers, headless browsers, simulators and Docker stacks."))))
    }

    private func configureMCP(added: Bool) {
        let model = model
        var spec = DialogSpec(icon: "point.3.connected.trianglepath.dotted", title: "Give agents a shared view.",
                              subtitle: added ? "Claude Code already has the SpawnSweep MCP server."
                                              : "Add the local SpawnSweep MCP server to your agent. It can find running dev servers before starting another.",
                              notes: ["Local connection only. The server runs on this Mac over standard input and output. Nothing is sent over the network."],
                              confirmTitle: "Done",
                              custom: AnyView(MCPSetup()))
        if !added {
            spec.confirmTitle = "Add to Claude Code"
            spec.action = DialogSpec.followUp(work: {
                let r = Integrations.addMCPToClaudeCode()
                if r.ok { return nil }
                let msg = (r.err.isEmpty ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
                return msg.isEmpty ? "The claude command exited with code \(r.code)." : msg
            }, then: { error in
                if let error {
                    model.present(DialogSpec(icon: "point.3.connected.trianglepath.dotted", title: "Claude Code wasn't changed.",
                                             subtitle: "Copy the command and run it in a terminal instead.",
                                             warning: error, confirmTitle: "OK", custom: AnyView(CommandBox(text: Integrations.mcpCommand))))
                } else {
                    model.present(DialogSpec(icon: "point.3.connected.trianglepath.dotted", title: "SpawnSweep MCP is added.",
                                             subtitle: "New Claude Code sessions can ask what's already running. Sessions open now pick it up after a restart.",
                                             confirmTitle: "Done"))
                }
            })
        }
        model.present(spec)
    }
}

// MARK: - Dialog bodies

private struct Explainer: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct ClaudeCodeSetup: View {
    let installed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            item("eye", "Observing sessions", badge: Badge(text: "Always on", style: .success),
                 "Read-only. SpawnSweep reads running processes and their folders to see what each session started. Nothing is installed.")
            item("moon", "Session-end hook", badge: installed ? Badge(text: "Installed", style: .success) : Badge(text: "Not installed"),
                 "When a session ends, SpawnSweep stops the dev servers, watchers, headless browsers and tunnels it started in that folder. Pinned sessions and protected ports are kept, and each stop is logged in Activity.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Merged into ~/.claude/settings.json").font(.meta).foregroundStyle(Theme.secondary)
                Text(Integrations.hookSnippet)
                    .font(.mono(11)).foregroundStyle(Theme.text).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func item(_ symbol: String, _ title: String, badge: Badge, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                    badge
                }
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MCPSetup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run this in a terminal, or let SpawnSweep add it to Claude Code:")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            CommandBox(text: Integrations.mcpCommand)
            Text("Agents can call running_for_repo and list_sessions. Both only report what's running. They never stop anything.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A command in SF Mono with a copy button.
private struct CommandBox: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text).font(.mono(11)).foregroundStyle(Theme.text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .help(copied ? "Copied" : "Copy command")
            .accessibilityLabel(copied ? "Copied" : "Copy command")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
