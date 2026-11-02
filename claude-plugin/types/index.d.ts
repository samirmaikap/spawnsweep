/** One thing running: a dev server, watcher, browser, simulator or Docker stack. */
export type Item = { kind: string; title: string; detail: string; memory?: string }

export type Session = {
  project: string
  agent: string
  state: 'active' | 'idle' | 'ended'
  /** When it went idle or ended, in ms since the epoch. */
  since?: number
  pinned: boolean
  items: Item[]
}

/** A linked git worktree (not a repo's main checkout). */
export type WorktreeItem = { repo: string; path: string; branch?: string; agent?: string; inUse: boolean }

export type Snapshot = {
  sessions: Session[]
  /** Running things no agent session claims. */
  loose: Item[]
  running: number
  ports: number[]
  simulators: string[]
  /** Empty when the app is too old to print `--scan --json`. */
  worktrees: WorktreeItem[]
  /** When the last scan finished, in ms since the epoch. */
  at: number
  isScanning: boolean
  error?: string
}

/** A resource in `SpawnSweep --scan --json`. Times are ISO 8601, sizes in bytes. */
export type ScanResource = {
  kind: string
  title: string
  detail: string
  ports: number[]
  memoryBytes: number
  startedAt: string | null
  cwd: string | null
}

/** What `SpawnSweep --scan --json` prints, version 1. */
export type ScanJSON = {
  version: number
  scannedAt: string
  running: number
  ports: number[]
  sessions: {
    project: string
    agent: string
    folder: string
    branch: string | null
    state: 'active' | 'idle' | 'ended'
    since: string | null
    pinned: boolean
    resources: ScanResource[]
  }[]
  unattached: ScanResource[]
  simulators: { name: string; runtime: string; bootedAt: string | null }[]
  worktrees: { repo: string; repoPath: string; path: string; branch: string | null; agent: string | null; inUse: boolean }[]
}

declare module 'claude-code' {
  interface PluginState {
    'spawnsweep-pane': { snapshot: Snapshot | null }
  }
}
