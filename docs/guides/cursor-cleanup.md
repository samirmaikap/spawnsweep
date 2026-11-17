---
layout: guide
title: "Clean up after Cursor agents on macOS"
description: "Review local dev servers, terminal jobs and Git worktrees left after a Cursor Agent task, then stop or remove the resources you recognize."
permalink: /cursor-cleanup/
media: demo
---

Finish the Cursor Agent task, review its terminal commands and inspect the local checkout before stopping any server or removing a worktree. Cursor can run an agent in a separate checkout with its own dependencies. Commands from a worktree setup step can leave independent local resources.

## Check the task environment first

Use the path shown in the Agents Window or the terminal. Run `pwd` from the relevant terminal, then run `git worktree list` from the repository to distinguish the main checkout from a linked one. Cursor can initialize worktrees through `.cursor/worktrees.json`. Look at that file for installs and setup commands if repeated worktrees consume disk space. [Cursor worktree documentation](https://cursor.com/docs/configuration/worktrees)

If a local app is still responding, [look up its listening port](../localhost-port-cleaner/) and check the working directory. Stop the command through its integrated terminal or runner when available.

## Review the resources on this Mac

SpawnSweep detects supported local Cursor agent processes and can use a Cursor worktree path as a hint. Open **Sessions** to review matched resources, **Ports** to identify a listener, or **Storage** for linked checkouts and their sizes. A folder-based match is weaker than process ancestry, and a shared server can serve tasks in several worktrees.

## Can I use SpawnSweep to clean a Cursor Cloud Agent machine?

SpawnSweep scans the local Mac. Manage cloud and remote SSH tasks in their own environments. For copied local worktrees, [verify Git status and preserve local files](../git-worktree-cleaner/) before cleanup.
