---
layout: guide
title: "Port 3000 already in use on Mac? Find and free it"
description: "Find the process listening on port 3000 in macOS, identify its project, and stop the correct dev server when Next.js or an AI coding agent reports a busy port."
permalink: /guides/port-3000-already-in-use-mac/
---

Run `lsof -nP -iTCP:3000 -sTCP:LISTEN` in Terminal to see what is listening on TCP port 3000. Check the process and its working directory before stopping it. A previous `next dev` command can still own the port after you finish a Claude Code, Codex or Cursor session.

## Identify the server and project

```sh
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

The `COMMAND` column shows the executable and `PID` identifies the process. When the executable is a generic name like `node`, use the PID to see its full command and working directory. Replace `12345` with the PID you found.

```sh
ps -p 12345 -o pid,ppid,command
lsof -a -p 12345 -d cwd
```

A working directory inside another checkout or Git worktree often explains why the server belongs to someone else's project or another task of your own. For a different port, substitute its number in the first command.

## Stop the server and verify the port

1. If you still have the original terminal, press **Control-C** there. For a service managed by a runner such as Docker Compose, stop the service through that runner.
2. For a standalone process you own, check its PID again and run `kill -TERM 12345` using the verified PID.
3. Rerun the first `lsof` command. If the listener returns with a new PID, look for the parent watcher or runner that restarted it. If the old service is still needed, leave it running and configure the new server to use a different port.

See `man lsof`, `man ps` and `man kill` in macOS Terminal for command details.

## Find a busy port from the menu bar

Open **Ports** in SpawnSweep to see local listeners together. Where the app can identify them, the row includes the project, Git branch and agent session. Select **Free port** on the listener you recognize and review the process before confirming. Pinned sessions and protected ports stay blocked from this action.

If a port conflict is one symptom of a finished coding session, [review its other leftover processes](../stop-leftover-ai-agent-dev-servers-mac/).
