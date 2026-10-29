# SpawnSweep — Design Guidelines

## Design intent

**A calm, precise macOS utility that makes a busy development workspace feel under control.**

The interface should feel premium through proportion, spacing, material, and care. Sage green, soft daylight surfaces, and a sculpted moon establish the identity. Detailed resource information stays clear and practical.

Reference mockups (2x PNGs): `~/Downloads/SpawnSweep UI Images/` — 01-sessions … 11-welcome-setup, session-*, worktree-detail, storage-*, resources-*, dialog-*, menu-bar-companion. Mockup data is illustrative; the app shows real data.

## 1. Color

| Role | Light | Dark |
|---|---|---|
| App background | `#F7F9F5` | `#202D25` |
| Sidebar / secondary surface | `#E6EDE3` | `#2B3B30` |
| Raised surface | `#FFFFFF` | `#2A392F` |
| Primary text | `#263A30` | `#E5EEE9` |
| Secondary text | `#748278` | `#A5B7AB` |
| Dividers / borders | `#DFE6DB` | `#46594A` |
| Primary action | `#527D61` | `#527D61` |
| Primary button text | `#FFFFFF` | `#FFFFFF` |

Use the primary action color for the main next step, enabled switches, and selected controls. Keep large areas neutral.

Status: Active = sage tint + dot + "Active". Idle = neutral sage badge with elapsed time. Ended with running resources = muted amber badge. Pinned = neutral badge with pin icon. Warning = soft amber surface with explanation. Destructive = system red at the final confirmation. Color always accompanies a label or icon.

## 2. Typography

SF Pro (system font); SF Mono for ports, commands, commit hashes, paths.

| Role | Size | Weight |
|---|---:|---|
| Main page heading | 28–30 pt | Medium |
| Cleanup summary heading | 24–26 pt | Medium |
| Dialog heading | 23–25 pt | Medium |
| Prominent resource value | 22–24 pt | Regular |
| Section heading | 13–14 pt | Medium |
| Body and controls | 12–13 pt | Regular |
| Metadata and badges | 11–12 pt | Regular |

Tighter tracking for large headings. Tabular numerals for values. Never shrink text to fit.

## 3. Layout and spacing

4 pt scale: 4, 8, 12, 16, 24, 32, 48. Sidebar ~190–210. Content inset 28–32. Between sections 24–32. Panel padding 18–24. Resource rows 14–16 vertical padding. Icon–label gap 8–12. Align headings, panels, lists to one left edge; values and row actions consistently on the right. Two columns for comparable items (port cards); one column for settings, activity, detailed lists.

## 4. Glass and surfaces

Glass in sidebar, menu bar popover, toolbar, modal backdrop only. Main reading surfaces stay stable. Fine highlight on raised edges; broad, soft, low-contrast shadows. Support Reduce Transparency and Increase Contrast.

Radius: popover 20–22, cleanup summary 18–20, content panel 12–14, buttons/inputs 7–9, badges 5–6.

## 5. The moon motif

Sculpted sage moon, prominent in the session overview, smaller in onboarding and menu bar companion. Decorative only — never a gauge or score.

## 6. Navigation and page patterns

Sidebar order: Sessions, Ports board, Resources, Storage, Recycle bin, Autopilot, Connections, Safety, Activity, Settings. Onboarding reachable from setup/settings.

- Sessions: lead with the cleanup opportunity; owner, project, branch, state, remaining resources, memory, review action.
- Ports board: port number easy to scan; project, service, branch, uptime, session state.
- Resources: devices, Docker stacks, browsers/watchers separately; a stack is one unit.
- Storage: reclaimable separate from total; explain exactly what slimming preserves.
- Recycle bin: branch, saved commit, removal date, time remaining, Restore.
- Autopilot: trigger, scope, action, dry-run status visible; budgets in their own section.
- Connections: status and setup steps; distinguish observing sessions from installing cleanup hooks.
- Safety: public tunnels, env-file locations, protected resources. Never display secret values.
- Activity: chronological; what changed and which recovery actions exist.

## 7. Components

One primary action per decision area; secondary = quiet outlined; navigation = minimal chrome. Labels: Review cleanup, Free port, Stop stack, Slim worktree, Restore worktree, Push & remove.

Resource rows: Icon → name → ownership/context → value → action. Switches for persistent preferences, buttons for immediate actions. SF Symbols, restrained outline style.

## 8. Interaction and safety

Every resource-changing action begins with a preview: resources affected, operation, what stays untouched, interruption/data-loss consequences, a specific confirm button. Active and pinned sessions stay out of sweeps. Worktree removal shows uncommitted changes and merge/push status; verify a required push before removal, else keep the worktree. **Restore** for files, **Relaunch** for stopped processes, **Undo** only for truly reversible actions. In the menu bar, one click opens the relevant review.

## 9. Motion and feedback

Hover/press 100–150 ms; popover/dialog 150–220 ms; expanding details 180–240 ms. Honor Reduce Motion; no looping decoration. Progress state during cleanup, then a specific result ("Stopped 6 resources. Freed 2.4 GB of memory."). Partial failures stay visible with retry and explanation.

## 10. Voice

Calm precision. "2 finished sessions still have resources running." "Your code and local changes stay in place." "This worktree has 2 commits that haven't been pushed." "Nothing changed. Review this dry run." No vague promises, alarm, or claims that stopping preserves live state.

## Quality standard

Purpose and next action obvious; ownership and protection visible; technical details readable; keyboard navigation and focus; light, dark, reduced transparency, increased contrast; destructive actions explain consequences; empty, loading, error, success and partial-success states designed.
