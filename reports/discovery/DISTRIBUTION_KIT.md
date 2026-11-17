# SpawnSweep distribution kit

Checked 2026-11-17. Copy below is for owner review. Submission, account updates, outreach, and paid placement require authorization. Existing listings and pull requests predate this audit.

## Product facts and copy

**Name** — SpawnSweep

**Tagline** — Mac menu bar cleaner for AI coding agents

**Short description** — Find what Claude Code, Codex, and Cursor left running, free occupied development ports, and review old worktrees on your Mac.

**Long description** — SpawnSweep is a native macOS menu bar utility for cleaning up after AI coding sessions. Review dev servers, watchers, simulators, and detected Docker stacks, with project and agent context where the app can identify a match. Inspect a port before freeing it and see which Git worktrees have reclaimable space. Manual cleanup shows a preview. Session sweeps exclude active and pinned sessions. The free MIT-licensed edition runs on Apple silicon with macOS 14 or later. The official download offers optional Pro features for $9 once on up to three Macs. The current release is ad hoc signed and has no Apple notarization. [Product site](https://samirmaikap.dev/spawnsweep/) · [Source and installation](https://github.com/samirmaikap/spawnsweep#readme) · [Latest release](https://github.com/samirmaikap/spawnsweep/releases/latest)

| Feature | Description to reuse |
|---|---|
| Sessions | Review detected resources by project and agent before stopping them. Detection depends on local process and session evidence. |
| Ports | See the process listening on a local port, with branch and project information where available. Review the target before releasing the port. |
| Worktrees | Inspect size and status, slim rebuildable files, or recycle an eligible checkout with supported ignored files saved for its retention period. |
| Simulators and Docker | Shut down a booted simulator or stop a detected Docker stack. Simulator shutdown retains device data. Docker uses the configured context and applies the container’s exit policy. |
| Integrations | The optional Claude Code SessionEnd hook can stop strongly matched leftovers automatically. The MCP interface exposes read-only state so a tool can check for an existing server. |
| Edition and privacy | The free edition covers routine session cleanup. The official Pro edition adds junk cleanup, large and old files, and eligible Autopilot execution modes. Scans happen locally. An activated Pro license contacts Dodo Payments for verification. |

Claims cross-checked against [resource detection](../../Sources/SpawnSweep/Engine/Scanner.swift), [cleanup actions](../../Sources/SpawnSweep/Engine/Actions.swift), [session controls](../../Sources/SpawnSweep/App/AppModel.swift), [hook and MCP](../../Sources/SpawnSweep/App/CLI.swift), and [license code](../../Sources/SpawnSweep/Engine/License.swift).

## Submission status and destinations

| Channel | Status and next action | Submission or evidence |
|---|---|---|
| Product Hunt | Draft ready. A public SpawnSweep launch did not surface in the searches checked. Check for an existing product or draft using the canonical URL while signed in under the maker's verified personal account. Choose a launch date after reviewing the gallery and verifying first launch on a clean Mac. | [Submit](https://www.producthunt.com/posts/new) · [Launch page instructions](https://help.producthunt.com/en/articles/17834537-4-build-your-product-page) |
| AlternativeTo | Existing owner-added listing. Request an update to the official website URL, retain GitHub under repository links, and align feature and edition labels with the current release. | [SpawnSweep listing and contribution interface](https://alternativeto.net/software/spawnsweep/about/) |
| OpenMacApps | Existing listing. The directory reports validating license and source on 2026-11-06. Replace the former GitHub Pages URL in its source entry with the direct product URL. | [Listing](https://openmacapps.com/apps/spawnsweep/) · [Edit listing source](https://github.com/koative/openmacapps/blob/main/content/apps/spawnsweep/index.md) |
| MacUpdate | Candidate. Prepare the official ZIP or release URL, current version and compatibility, app icon and screenshot. Account and editorial review required. | [Submit](https://member.macupdate.com/content/submit) · [Requirements](https://www.macupdate.com/help/submit-app) |
| MacMenuBar | Candidate, subject to editorial fit. The app has an actionable menu bar popover and a separate full window. Capture three actual menu bar states so the reviewer can judge where work occurs. | [Submit a menu bar app](https://macmenubar.com/submit-your-menu-bar-app/) |
| Awesome Mac | Already merged under Developer Utilities. | [Merged PR #4107](https://github.com/jaywcjlove/awesome-mac/pull/4107) |
| Awesome Swift macOS Apps | Already merged under AI Agent Monitoring. | [Merged PR #189](https://github.com/jaywcjlove/awesome-swift-macos-apps/pull/189) |
| Open Source Mac OS Apps | Existing PR is open. Review current feedback and amend the existing request if needed. That list uses `applications.json`. | [Open PR #1894](https://github.com/serhii-londar/open-source-mac-os-apps/pull/1894) · [Contribution guide](https://github.com/serhii-londar/open-source-mac-os-apps/blob/master/CONTRIBUTING.md) |
| MCP directories | TensorBlock already lists the bundled read-only MCP interface. The earlier punkpeye PR was closed without merge after its listing workflow required a Linux-container-compatible server. The bundled interface depends on native macOS resources. | [TensorBlock merged PR #5176](https://github.com/TensorBlock/awesome-mcp-servers/pull/5176) · [Closed PR #18319](https://github.com/punkpeye/awesome-mcp-servers/pull/18319) |
| Awesome Claude Code | Candidate for a maker-authored recommendation describing the optional SessionEnd hook and pane. Check for an existing entry or issue. The curator requires recommendations written by a person through the linked issue form. | [Eligibility and form](https://github.com/hesreallyhim/awesome-claude-code/blob/main/CONTRIBUTING.md#how-to-recommend-a-resource) |
| Homebrew Cask | Official cask blocked. The v0.2.3 ZIP is ad hoc signed and unnotarized, and the project is below the normal notability thresholds. On 2026-11-17 the upstream GitHub API reported 3 stars, 0 forks, and 0 subscribers. Free use with optional paid features is eligible in principle. Revisit after a versioned upstream release passes Gatekeeper. Verify arm64 and the latest macOS, calculate the SHA-256, and add working release detection. | [Cask policy](https://docs.brew.sh/Acceptable-Casks) · [Notability and livecheck](https://docs.brew.sh/Package-Acceptance-Policy) · [Submission workflow](https://docs.brew.sh/Adding-Software-to-Homebrew) |
| Show HN | Maker introduction outline ready. The maker writes the title and body in their own words under HN's policy on generated and AI-edited submissions. Use the GitHub README as the destination with a direct download and installation details. | [Submit](https://news.ycombinator.com/submit) · [Show HN requirements](https://news.ycombinator.com/showhn.html) · [HN guidelines](https://news.ycombinator.com/newsguidelines.html) |
| r/macapps | App Pile is the route to evaluate. The main feed adds account, trust, and saturated-category restrictions. The disk-cleaner label may place SpawnSweep in a restricted category. Disclose maker affiliation and notarization status, verify the current thread, and use its Problem, Comparison, and Pricing format. | [Moderator guidance](https://www.reddit.com/r/macapps/comments/1xo5ky1/rmacapps_moderation_update_phase_4_clearer_rules/) |
| r/ClaudeAI and r/ClaudeCode | Review the current showcase thread and use it if the maker can describe how Claude Code was used to build the project. Both communities request context about the implementation. | [ClaudeAI showcase](https://www.reddit.com/r/ClaudeAI/comments/1xw0qik/claude_project_showcase_discussion_hub_updated_on/) · [ClaudeCode showcase](https://www.reddit.com/r/ClaudeCode/comments/1xxn3k9/weekly_showcase_thread_what_are_you_building_with/) |
| Developer newsletters | Editorial pitch drafts ready. Console considers self-serve developer tools and pre-1.0 betas. iOS Dev Weekly accepts link suggestions, with a simulator cleanup guide as the proposed angle. | [Console selection and submission](https://console.dev/selection-criteria#submit-a-tool) · [iOS Dev Weekly link suggestion](https://suggest.iosdevweekly.com/) |
| Mac blogs and YouTube | Editorial pitch drafts ready. MacStories has a public editorial contact page. A Better Computer publishes an email contact through Birchtree and covers Mac workflows. MacMost explicitly declines product pitches via its contact form. | [MacStories editors](https://www.macstories.net/about/) · [A Better Computer contact](https://birchtree.productions/) · [MacMost contact policy](https://macmost.com/contact) |

## Product Hunt

**Launch name** — SpawnSweep

**Tagline** — Mac menu bar cleaner for AI coding agents

**Description**

> Finished a coding session, but port 3000 is still busy? SpawnSweep shows which dev servers, watchers, simulators, and detected Docker stacks are still running. Review what to stop, inspect old Git worktrees, and reclaim disk space. Free and open source for Apple silicon Macs. Optional Pro is $9 once.

**Maker's first comment**

> Hi, I'm Samir, the maker of SpawnSweep. I built it for the end of a coding session, when the chat is finished but the tools it started are still running. I wanted to answer two questions quickly. What is holding this port, and can I stop it without interrupting another project?
>
> The Ports view shows the listener and the project or agent session when SpawnSweep can identify it. Sessions groups related resources so you can review what to stop together. Storage helps you inspect old worktrees and remove rebuildable files from eligible checkouts.
>
> The free MIT-licensed app runs on Apple silicon with macOS 14 or later. Pro is $9 once for up to three Macs and adds junk cleanup, large and old files, and Autopilot execution modes. The current download hasn't been notarized by Apple. The README explains what to expect on first launch.
>
> If you run multiple agents on one Mac, what would you need to see in the cleanup preview before trusting it with a shared project? [Try SpawnSweep](https://samirmaikap.dev/spawnsweep/)

Select available launch tags for developer tools, macOS, and open source. Product Hunt's launch form currently allows a 40-character name, 60-character tagline, and 500-character description. [Product Hunt launch fields](https://help.producthunt.com/en/articles/17834537-4-build-your-product-page)

## Directory copy

**AlternativeTo update**

> SpawnSweep focuses on developer resources left behind by AI coding agents. Its Ports and Sessions views help identify a local listener and inspect the associated dev server or project before stopping it. Storage covers worktree status and space, and eligible worktree cleanup. Free MIT-licensed edition for Apple silicon Macs with macOS 14 or later. The optional $9 Pro unlock adds junk cleanup, large and old file cleanup, and eligible Autopilot modes.

**OpenMacApps correction**

> Change the website field to the canonical [SpawnSweep website](https://samirmaikap.dev/spawnsweep/). The project source and release links stay on GitHub. Suggested listing text: “Native menu bar app for reviewing what AI coding sessions leave behind on a Mac, including dev servers, busy ports, simulators, Docker stacks, and Git worktrees.”

**MacUpdate and MacMenuBar**

> SpawnSweep adds a menu bar view of local development activity. Open the popover to see detected leftovers and start a cleanup review. The full window lets you inspect listeners and Git worktree storage in more detail. The free edition runs on macOS 14 or later on Apple silicon. The current download has no Apple notarization.

## Show HN introduction outline for the maker

- Use the required `Show HN` prefix. Name the tool and say in plain language what a developer can try.
- Start with a real example from your own workflow, such as two active worktrees competing for port 3000. Include measured specifics only if you can reproduce them.
- Describe what the app can match from local evidence and how it handles ambiguous ownership. Explain the preview and the distinction between manual and optional automated cleanup.
- State the Apple silicon and macOS 14 minimum, current notarization status, and free source and download options. Invite technical questions about handling resources shared by multiple projects.

## Reddit introduction

For the current r/macapps App Pile thread, after checking its rules:

> **Problem** — I built SpawnSweep for developers who finish a Claude Code, Codex, or Cursor session and still have dev servers, test simulators, or stale worktrees using Mac resources.
>
> **Comparison** — Sluice focuses on the disk used by AI developer tools. SpawnSweep focuses on inspecting and stopping live dev servers and freeing ports, with worktree review alongside. CleanMyMac covers wider Mac maintenance, including app uninstallation. SpawnSweep's scope is local developer resources.
>
> **Pricing** — The MIT-licensed edition is free. Pro is $9 once for up to three Macs. This release has no Apple notarization and requires macOS 14+ on Apple silicon. [Features and download](https://samirmaikap.dev/spawnsweep/)

Recheck the comparison against current product pages. [Sluice](https://www.producthunt.com/products/sluice-2) · [CleanMyMac features](https://macpaw.com/cleanmymac)

For a Claude developer showcase, add a genuine example of how Claude Code was used to build the project where the thread calls for it:

> I built SpawnSweep to see which dev servers and watchers are still around after a Claude Code session. The optional SessionEnd integration can stop strongly matched leftovers. Manual cleanup shows a preview, and the hook leaves pinned sessions and protected ports alone. I'd like feedback on shared checkouts where two sessions use the same server. [Source](https://github.com/samirmaikap/spawnsweep)

## Social copy

**Short post for X or Bluesky**

> Closed the agent chat and port 3000 is still taken? SpawnSweep shows which process owns the port, with project and session context when available. Open source for macOS 14+ on Apple silicon. https://samirmaikap.dev/spawnsweep/

**LinkedIn**

> I built SpawnSweep for the tasks that outlive a coding-agent session. A dev server can still hold port 3000, a simulator can still be booted, and an old Git worktree can keep its own build output. SpawnSweep brings those together on a Mac so you can review what to stop or clean up. The core is MIT licensed. [SpawnSweep](https://samirmaikap.dev/spawnsweep/)

## Editorial and developer outreach

**Console**

> **Subject — A Mac utility for the end of an AI coding session**
>
> Hi Console team, I'm Samir, the maintainer of SpawnSweep. It's a pre-1.0 native Mac utility that shows left-running dev resources with project and agent context when available. An easy test is to leave a dev server listening, open Ports, and review the process before freeing the port. The free functions are available without an account, and the README covers the current non-notarized download. [Project and source](https://github.com/samirmaikap/spawnsweep)

**iOS Dev Weekly link submission**

> A reference for choosing between shutting down an iOS simulator and deleting an unused simulator device. It includes specific `simctl` commands and explains where Xcode manages runtimes and device data. I maintain SpawnSweep and wrote the guide as part of its documentation. [Xcode simulator cleanup guide](https://samirmaikap.dev/spawnsweep/clean-up-xcode-simulators-mac/)

**MacStories tip**

> **Subject — A menu bar tool for Mac developers running coding agents**
>
> Hi MacStories team, I'm Samir, the developer of SpawnSweep. For readers who use Claude Code or Codex on a Mac, the app shows what is still running after a session and lets users review what to stop. I'd be happy to share a current-release recording of the Ports view and discuss what happens when another project still needs the server. The free edition is MIT licensed and the download has no Apple notarization today. [Website and demo](https://samirmaikap.dev/spawnsweep/)

**A Better Computer**

> **Subject — Reviewing leftover dev servers across Mac projects**
>
> Hi Matt, your work on Workbench caught my attention because moving between projects is where I kept losing track of dev servers. I built SpawnSweep to inspect the listener and project before stopping it and to surface old worktree storage. If that workflow fits a video you're already planning, here's the source and download. A simple demo is starting a local server in one checkout and opening Ports from another. [Try SpawnSweep](https://samirmaikap.dev/spawnsweep/)

## Asset handoff

| Asset | Available now | Preparation before submission |
|---|---|---|
| Logo | [240×240 Product Hunt thumbnail](assets/product-hunt-thumbnail.png) and [256×256 app icon](../../docs/images/icon.png) | Confirm the thumbnail in the launch preview. |
| Gallery | 1270×760 Product Hunt gallery with real UI captures for [This Mac](assets/product-hunt-this-mac.jpg), [Autopilot](assets/product-hunt-autopilot.jpg), and [optional Pro](assets/product-hunt-pro.jpg) | Add actual Ports, Sessions and worktree preview captures with sample data when preparing a live walkthrough. |
| Menu bar evidence | App contains a menu bar status indicator and popover. The homepage popover example uses sample data. | For MacMenuBar, capture three actual macOS menu bar states, such as open popover, leftovers shown, and a cleanup review launched from it. |
| Video | [20-second launch MP4](../../docs/images/launch.mp4) and [animated GIF](../../docs/images/launch.gif) | Label the existing animation as an illustration. Capture a real walkthrough of identifying a listener, reviewing cleanup, and confirming the port is free. Add captions. Use an approved YouTube link if the launch form calls for it. |
| Download | [Official GitHub release](https://github.com/samirmaikap/spawnsweep/releases/latest) | Check the linked version and first launch on an Apple silicon Mac, and update signing and notarization disclosures if a new signed build ships. |

Use demo repositories and fictional filenames in captures. Keep personal paths, real session names, and environment-file contents out of screenshots. Record each approved submission's date, public URL, and status to avoid duplicate requests.
