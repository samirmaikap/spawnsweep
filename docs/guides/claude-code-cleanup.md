---
layout: guide
title: "Clean up after Claude Code on Mac"
description: "Stop servers, test watchers and tunnels left by Claude Code. Review which project started them and learn when to use the optional SessionEnd hook."
permalink: /claude-code-cleanup/
media: demo
---

Finish the Claude Code task, check the project for a running server or watcher, and stop only the resources you no longer need. If you run several Claude Code sessions in the same checkout, a background server may still be serving another session.

## Find what the session left running

Check the task output for a server URL or command such as `npm run dev`, `vitest --watch` or a tunnel command. If the server reported port 3000, run `lsof -nP -iTCP:3000 -sTCP:LISTEN`. Substitute the actual port when it differs. Use the original terminal or runner to stop the job when it is still open. Check the [orphaned-process guide](../orphaned-process-cleaner/) for watchers and browsers without a listener.

Claude Code can run parallel tasks in linked Git checkouts. Run `git worktree list` from the repo to identify those paths before assuming two sessions share a working directory. [Claude Code's parallel worktree documentation](https://code.claude.com/docs/en/common-workflows#run-parallel-sessions-with-worktrees)

## Review a finished Claude Code session in SpawnSweep

In **Sessions**, select the project and review what SpawnSweep associated with it. Manual cleanup shows the resources before they stop. The [Claude pane](../#claude-pane) can show the same session context alongside the chat.

In **Connections**, the optional **Claude Code SessionEnd** integration stops strongly matched dev servers, watchers, headless browsers and tunnels when Claude Code reports a session end. It skips `/clear`, pinned sessions, protected ports and folders with another detected agent process. Closing a Claude desktop chat may leave its host process alive, so use the manual views when session state is uncertain. [Claude Code hook reference](https://code.claude.com/docs/en/hooks#sessionend)

## Will the hook delete Claude chat history or worktrees?

The hook only stops eligible processes. Worktree cleanup is a separate action with a preview. Use the [Git worktree guide](../git-worktree-cleaner/) if you also need to recover disk space.
