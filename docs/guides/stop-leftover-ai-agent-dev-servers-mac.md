---
layout: guide
title: "Stop leftover Claude Code and Codex dev servers on Mac"
description: "Find and stop dev servers, watchers, headless browsers and tunnels left running after an AI coding session on macOS, while keeping active projects running."
permalink: /guides/stop-leftover-ai-agent-dev-servers-mac/
---

After a Claude Code, Codex or Cursor session ends, a background dev server, file watcher, headless browser or tunnel may keep running. To clean up, identify the project and confirm the session has finished, then stop the resources it still owns. An active session in the same project may depend on them.

## Check what stayed running

- **A server is still answering on localhost.** Start by [finding the process listening on its port](../port-3000-already-in-use-mac/). Match its working directory to the project you just finished.
- **The server stops and immediately returns.** Check the parent process. A task runner or watcher can restart a child process until the parent stops.
- **There is no busy port, but activity continues.** A test watcher or headless browser can keep working without a TCP listener. Inspect its command and project before stopping it.

Use the original terminal or task runner to shut down the resources when it is still available. When the same checkout is shared by two sessions, confirm that the second session has finished or can work without the resource.

## Review leftovers by agent session

Open **Sessions** in SpawnSweep and select a finished session. The cleanup preview shows resources the app associated with it, with strongly matched items selected by default. Review the list, then confirm the resources you want to stop. Source files and uncommitted changes stay in the worktree. Restarting a process launches it again with fresh runtime state. You can pin a session you intend to keep.

The optional **Claude Code SessionEnd** integration can stop strongly matched dev servers, watchers, headless browsers and tunnels automatically. It skips pinned sessions, protected ports, `/clear`, and folders where another detected agent process is still active. The free Sessions view also supports manual cleanup for Codex and Cursor. [Claude Code hooks reference](https://code.claude.com/docs/en/hooks#sessionend) · [SpawnSweep hook source](https://github.com/samirmaikap/spawnsweep/blob/main/Sources/SpawnSweep/App/CLI.swift)

A stopped session may still have a checkout on disk. [Review its Git worktree and any local files](../clean-up-git-worktrees-mac/) before removing it.
