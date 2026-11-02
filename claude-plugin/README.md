<p align="center">
  <img src=".claude-plugin/icon.png" width="96" alt="SpawnSweep icon">
</p>

# SpawnSweep pane for Claude Code

A side pane in Claude Code and the Claude desktop app that shows what your AI coding agents left running on this Mac: each agent session with its dev servers, ports and Docker stacks, simulators and other things no session claims, and, with newer SpawnSweep releases, your git worktrees.

The pane opens beside your chat when a Claude session starts, and `/spawnsweep` brings it back if you close it. A moon with the count of what's running (`🌔 4`) sits in the footer, beside the model name; click it to open the pane. The pane reads what the [SpawnSweep](https://samirmaikap.github.io/spawnsweep/) Mac app reports. It refreshes every 30 seconds, and has a **Refresh** button and an **Open SpawnSweep** button for when you want to clean something up.

## Requirements

- macOS with [SpawnSweep](https://github.com/samirmaikap/spawnsweep#install) installed in `/Applications`. The free edition is enough.
- Claude Code or the Claude desktop app, recent enough to run plugins with function hooks.

## Install

At the prompt of a Claude Code terminal session:

```
/plugin install spawnsweep --marketplace samirmaikap/spawnsweep
```

Answer `y` to add the marketplace, then pick a scope (user scope loads it in every session).

From a shell:

```bash
claude plugin install spawnsweep --marketplace samirmaikap/spawnsweep
```

In the Claude desktop app, where `/plugin` doesn't run: click **+** next to the prompt box, then **Plugins**, **Add marketplace** with `samirmaikap/spawnsweep`, then **Add plugin**. A plugin installed from a terminal at the user scope also loads in the desktop app's Code tab.

## How it works

Every 30 seconds the pane runs `/Applications/SpawnSweep.app/Contents/MacOS/SpawnSweep --scan --json` and draws the result. SpawnSweep 0.2.1 and earlier print text instead of JSON; the pane reads that too, without worktrees. Nothing leaves your Mac, and the pane never stops or removes anything: cleaning up stays in the SpawnSweep app, with its preview.

## Develop

```bash
claude plugin validate claude-plugin
claude plugin test claude-plugin
claude --plugin-dir claude-plugin
```

MIT licensed, like the rest of SpawnSweep.
