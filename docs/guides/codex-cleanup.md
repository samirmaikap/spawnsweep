---
layout: guide
title: "Clean up Codex worktrees and dev servers on Mac"
description: "Review abandoned OpenAI Codex worktrees, preserve changes and local configuration, and stop dev servers after a Codex task."
permalink: /codex-cleanup/
media: storage
---

After a Codex task ends, review the thread and decide where its changes should live. Hand the work off to your main checkout, commit it on a branch, or save the local changes before removing the worktree. Each worktree can have its own dependency folders, build output, running server and ignored configuration.

## Verify the worktree and save its changes

Use the worktree path shown by Codex. From the repository, run:

```sh
git worktree list
git -C "/path/to/codex-worktree" status --short --branch
git -C "/path/to/codex-worktree" status --short --ignored
```

Replace the example path with the real path. Check for commits and local changes, then check ignored files such as `.env`. Verify the thread has finished and that another task is not using its server. Codex has its own worktree lifecycle and handoff controls. [Codex worktrees documentation](https://learn.chatgpt.com/docs/environments/git-worktrees)

## Pick the cleanup that fits the task

Use **Storage** in SpawnSweep to see linked checkouts by repository. **Slim** is useful when you want to keep returning to the checkout and can reinstall dependencies. **Recycle** previews eligible worktree removal and stages eligible ignored files for restoration during the configured retention period. [Git worktree cleanup steps](../git-worktree-cleaner/)

Open **Sessions** or **Ports** to review a remaining server. SpawnSweep can associate a process by ancestry or a remembered match. A worktree path can supply a weaker association, so confirm the process before stopping it.

## Will stopping a server remove the worktree or end my Codex thread?

Server cleanup acts on the selected processes. Git worktree removal is a separate action. Finish the task and save its changes in Codex before recycling its checkout. [Review leftovers across parallel agents](../ai-coding-agent-cleanup/)
