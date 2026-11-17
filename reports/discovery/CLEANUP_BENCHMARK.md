# Reproduce a local cleanup benchmark

This fixture exercises SpawnSweep's public worktree discovery and process cleanup code. It creates a disposable merged Codex-style Git worktree with a tracked source file, an ignored synthetic `.env`, and 16 MiB in ignored `node_modules`. A Python worker opens a loopback-only TCP port. The runner measures stopping that worker and slimming that worktree, then verifies the outcomes independently.

## Run

From the repository root on macOS, with Swift 6, Git and Python 3 available:

```sh
./reports/discovery/benchmark-cleanup.sh
```

The runner archives the committed public source at `HEAD` into a temporary directory, builds it with a fixture-only entry point, and removes that directory on exit. It runs each sample with a new repository and worker. It never launches the GUI or changes your installed SpawnSweep, user settings, or Git repositories. The process cleanup receives only the PID and start time of the fixture worker.

| Output column | Measurement |
|---|---|
| `eligible_worktrees` | Linked worktrees returned by `DiskScanner.worktrees`, after verifying the fixture is merged and recognized from its Codex-style path. |
| `processes_stopped` | Result of `Actions.stopProcesses`. The runner also verifies the worker is no longer running. |
| `ports_released` | The worker has a dynamically assigned listener before cleanup and the port is absent from the listener list afterward. |
| `disk_bytes_removed` | The bytes reported by `Actions.slim`, cross-checked against the change in allocated worktree size measured with `du -sk`. The runner verifies source and `.env` contents are identical after cleanup. |
| `cleanup_ms` | Wall time from before process stop to after worktree Slim. Build, fixture setup, discovery and final verification are outside that interval. |

## Measured results

November 17, 2026. Three samples on Apple M5 Pro, arm64, macOS 26.6.2 and Swift 6.4, public source commit `920af124eade039b9d7ff2d2d58d57a9b2474192`.

| Run | Worktrees identified | Processes stopped | Ports released | Allocated bytes removed | Cleanup duration |
|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 1 | 1 | 16,777,216 | 1,131.4 ms |
| 2 | 1 | 1 | 1 | 16,777,216 | 1,125.0 ms |
| 3 | 1 | 1 | 1 | 16,777,216 | 1,125.5 ms |

The disk result reflects the size of the test payload. The timing reflects this fixture on one machine. It provides evidence for linked worktree discovery, PID validation, loopback port release, and protection of tracked source and ignored configuration during Slim. End-to-end desktop interactions, attribution from a live agent, worktree Recycle and Restore, and Pro features are outside this fixture.
