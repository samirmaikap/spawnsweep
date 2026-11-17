---
layout: guide
title: "AI coding agent cleanup on macOS"
description: "Use a repeatable end-of-session workflow to reclaim disk space and recover system resources after running Claude Code, Codex or Cursor on your Mac."
permalink: /ai-coding-agent-cleanup/
media: demo
---

To clean up after AI coding agents on Mac, first finish or pin active sessions, then review background processes and storage separately. Stop the resources tied to finished tasks, verify the ports you need are free, and review only the checkouts and build data you can safely remove.

## End-of-session checklist

1. **Save the work.** Decide where the edits and commits should live. Use `git worktree list` and review the status in each checkout before removing it.
2. **Check runtime resources.** Use `lsof -nP -iTCP -sTCP:LISTEN` to see local TCP listeners. Check watchers, headless browsers, simulators and containers for work that continues without a listener on your Mac.
3. **Stop resources you recognize.** Use the original terminal, runner or app. Recheck the port or device state afterward.
4. **Review storage separately.** Measure worktree dependencies and simulator data, then preserve untracked and ignored files you still need before deletion.

## Use SpawnSweep to review parallel sessions

SpawnSweep is an open-source macOS menu bar cleaner for AI coding agents. **Sessions** shows detected project context, **Ports** helps investigate listeners, **Resources** groups devices and Docker stacks, and **Storage** lists worktree and build data. Manual cleanup presents a preview. The app uses process and directory context, so a shared checkout or detached process can still need your judgment. [See the cleanup and recovery limits](../#safety)

## Which guide should I use?

- [Claude Code cleanup](../claude-code-cleanup/) covers the optional SessionEnd hook.
- [Codex cleanup](../codex-cleanup/) covers handoff, worktree review and local servers.
- [Cursor cleanup](../cursor-cleanup/) covers the Agents Window, terminal jobs and local checkouts.
- [Developer disk cleanup](../developer-disk-cleaner/) covers storage costs. [Orphaned processes](../orphaned-process-cleaner/) covers runtime costs.

## Can I use this routine during an active session?

Inspecting processes and disk usage can be useful at any time. Keep a resource running when another task still relies on it. Pin sessions and protect ports in SpawnSweep when you want to exclude them from sweeps.
