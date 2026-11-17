# SpawnSweep release and cleanup trust

## Verify the release before running it

On November 17, 2026, the [latest GitHub Releases URL](https://github.com/samirmaikap/spawnsweep/releases/latest) resolved to [v0.2.3](https://github.com/samirmaikap/spawnsweep/releases/tag/v0.2.3). The release ZIP returned HTTP 200. Its 3,374,770 bytes matched the SHA-256 digest published in [GitHub's release API](https://api.github.com/repos/samirmaikap/spawnsweep/releases/tags/v0.2.3).

```text
88a92466d0803df0adc383873c717874a2c82c57a5325e4ae157b14d5588b395  SpawnSweep.zip
```

| Check | v0.2.3 result |
|---|---|
| Binary and deployment target | Mach-O arm64; bundle minimum macOS 14.0 |
| `codesign --verify --strict` | Valid ad hoc signature; no Developer ID or Team ID |
| `spctl --assess --type execute --verbose=2` | Rejected |
| `xcrun stapler validate` | No stapled ticket. The release notes identify the build as unnotarized. |
| Checksum | GitHub supplied an asset digest. The release had one ZIP asset and the installer performed no checksum or signature verification. |

To repeat on a downloaded ZIP, compare the output of `shasum -a 256 SpawnSweep.zip` to the digest on the **same tagged release**. Then inspect the extracted app without launching it:

```sh
file SpawnSweep.app/Contents/MacOS/SpawnSweep
codesign -dv --verbose=2 SpawnSweep.app
codesign --verify --strict --verbose=2 SpawnSweep.app
spctl --assess --type execute --verbose=2 SpawnSweep.app
xcrun stapler validate SpawnSweep.app
```

Compare the hash to GitHub’s asset metadata to check the download matches the tagged release. Developer ID signing and Apple notarization are separate checks. [GitHub release asset fields](https://docs.github.com/en/rest/releases/assets) · [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

### Installation options

- **GitHub release ZIP.** Download from the official repository. Extract the ZIP and move the app to Applications. For the current unnotarized build, macOS can ask you to approve the individual app under **System Settings → Privacy & Security → Open Anyway**. Verify the source and release hash first.
- **Terminal installer.** [Read the installer](../../scripts/install.sh) before running it. It downloads the latest ZIP, checks the OS and binary architecture, quits an existing SpawnSweep process, replaces the bundle in `/Applications` or `~/Applications`, and opens the app. Use the tagged ZIP to pin an exact release.
- **Build from source.** [Build with the public source and Xcode 16 or Swift 6](../../README.md#build-from-source). The resulting ad hoc build includes the free edition. The Pro implementation is built separately into the official release.

### Release maintainer handoff

The [release script](../../scripts/release.sh) supports both ad hoc release builds and the Developer ID path. The Developer ID path requires Apple's paid developer program, a **Developer ID Application** signing identity, an Apple notarization credential profile in Keychain, the private Pro source checkout, and GitHub release access. It signs with hardened runtime and timestamp, submits a ZIP to Apple, staples the ticket to the app, and runs an execution assessment before uploading a draft. Keep signing credentials and the private Pro source outside the public checkout.

For the next owner-approved release, verify the published artifact from a fresh download, confirm Developer ID, Gatekeeper acceptance and stapled ticket, and attach a per-release `SHA256SUMS` file. Update the installer to resolve the ZIP and expected checksum from the same tagged release, abort before replacing or launching the app on a mismatch, and document how to check the checksum manually. Plan the rollout around the current release, which predates a standalone checksum asset. Owner access and a new release are needed for publishing and confirmation of the signed and notarized artifact.

## Privacy and local state

The [public scanner](../../Sources/SpawnSweep/Engine/Scanner.swift) processes local resources without sending the scan to a service. [Preferences, history, scan data and recycled worktree files](../../Sources/SpawnSweep/Engine/Store.swift) live under `~/Library/Application Support/SpawnSweep`. Cleanup and activity can reveal local project paths, so redact reports before sharing them.

Pro contacts Dodo Payments to activate, validate or deactivate a license. Activation sends the key and Mac name. Validation and deactivation send the key and activation identifier. The activation record is stored in Keychain. The app attempts validation after seven days since the last confirmation and retries at most daily after an unreachable result. The code allows 14 additional days of offline grace. [License implementation](../../Sources/SpawnSweep/Engine/License.swift)

The optional Claude pane and read-only MCP tools expose local resource details to the agent client where configured. Agent clients have their own data practices. [Claude integration](../../claude-plugin/README.md) · [MCP tools](../../Sources/SpawnSweep/App/CLI.swift)

## Cleanup boundaries

| Action | Guardrails and limits |
|---|---|
| Find ports and sessions | Ports covers detected development listeners and reported Docker ports. The scanner uses process ancestry, observed history and project paths. Attribution based only on a desktop app or worktree can be weak. |
| Sweep ended sessions | Automatic session sweeps use strongly matched resources and skip active or pinned sessions and protected resources. The optional Claude Code hook can act at session end without a manual preview and checks for other live agents in the same folder. |
| Stop a running resource | Manual actions offer a preview. Process stops recheck the process start time before signalling. Relaunch uses the recorded command when available. In-memory state in stopped processes is lost. |
| Slim a Git worktree | The app rechecks for running processes and removes eligible ignored, rebuildable folders that contain no tracked files. Dependencies and build outputs can require a fresh install or build. |
| Recycle a Git worktree | The app checks worktree status and saves eligible ignored files before asking Git to remove the worktree without force. It refuses the main checkout, unsaved or busy worktrees, and ignored-file backups larger than 500 MB. Saved files can be restored during the retention window, which defaults to seven days. |
| Shut down simulators or stop Docker stacks | Simulator shutdown keeps device data. Reviewing and deleting an unused device is a distinct action and removes local device data. SpawnSweep uses `docker stop` in its configured Docker context. Docker auto-remove may delete exiting containers and their anonymous volumes. [Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/) · [Auto-remove](https://docs.docker.com/reference/cli/docker/container/run/#rm) |
| Autopilot | Rules start in dry-run mode. License-enabled Ask First and Automatic modes can change resources under their rule conditions. Review rule settings on projects or resources you need to keep. |

[Cleanup actions](../../Sources/SpawnSweep/Engine/Actions.swift) · [Review dialogs](../../Sources/SpawnSweep/App/AppModel.swift) · [Autopilot rules](../../Sources/SpawnSweep/App/Autopilot.swift)

The fixture measurements in [CLEANUP_BENCHMARK.md](CLEANUP_BENCHMARK.md) cover a loopback server and ignored worktree data. They do not establish behavior for every real project, private Pro cleanup modules or an unattended agent session. [Report a suspected security issue privately](../../SECURITY.md).
