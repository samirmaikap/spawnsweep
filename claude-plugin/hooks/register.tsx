import { atom, read, update } from 'claude-code'
import type { Engine, Register } from 'claude-code'

import type { Item, ScanJSON, ScanResource, Session, Snapshot, WorktreeItem } from '../types'

const PANE = 'spawnsweep'
const APP = '/Applications/SpawnSweep.app/Contents/MacOS/SpawnSweep'
const BUNDLE_ID = 'app.spawnsweep.mac'
const SITE = 'https://samirmaikap.github.io/spawnsweep/'
// ponytail: one scan takes about 4 s of real work, so 30 s keeps the pane fresh without costing CPU.
const EVERY_MS = 30_000
const WORKTREES_SHOWN = 12

const snapshot = atom({ plugin: 'spawnsweep', key: 'snapshot' } as const, null as Snapshot | null)

/** The app's own `Fmt.bytes`: decimal units, one decimal under 10. */
function bytes(b: number): string {
  if (b <= 0) return '0 MB'
  for (const [size, name] of [[1e12, 'TB'], [1e9, 'GB'], [1e6, 'MB']] as const) {
    if (b >= size) {
      const n = b / size
      return n >= 10 ? `${Math.round(n)} ${name}` : `${n.toFixed(1)} ${name}`
    }
  }
  return `${(b / 1e6).toFixed(1)} MB`
}

function iso(text: string | null | undefined): number | undefined {
  if (!text) return undefined
  const ms = Date.parse(text)
  return Number.isNaN(ms) ? undefined : ms
}

/** `SpawnSweep --scan --json`, in releases after 0.2.1. Missing fields read as empty, so a newer version still draws. */
export function parseJson(j: Partial<ScanJSON>, at: number): Snapshot {
  const item = (r: ScanResource): Item => ({
    kind: r.kind,
    title: r.title,
    detail: r.detail,
    ...(r.memoryBytes > 0 ? { memory: bytes(r.memoryBytes) } : {}),
  })
  const worktrees: WorktreeItem[] = (j.worktrees ?? []).map(w => ({
    repo: w.repo,
    path: w.path,
    inUse: w.inUse,
    ...(w.branch ? { branch: w.branch } : {}),
    ...(w.agent ? { agent: w.agent } : {}),
  }))
  return {
    sessions: (j.sessions ?? []).map(s => ({
      project: s.project,
      agent: s.agent,
      state: s.state,
      since: iso(s.since),
      pinned: s.pinned,
      items: s.resources.map(item),
    })),
    loose: (j.unattached ?? []).map(item),
    running: j.running ?? 0,
    ports: j.ports ?? [],
    simulators: (j.simulators ?? []).map(d => d.name),
    worktrees,
    at,
    isScanning: false,
  }
}

const DATE = /\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4}/

/** Swift prints dates as `2026-10-31 08:46:43 +0000`; JavaScript wants `2026-10-31T08:46:43+00:00`. */
function parseDate(text: string): number | undefined {
  const m = DATE.exec(text)?.[0]
  return m ? iso(m.replace(' ', 'T').replace(/ ([+-]\d\d)(\d\d)$/, '$1:$2')) : undefined
}

/** `kind title · detail … · last`: the kind is the first word, the last part is `link=` or `cwd=`. */
function parseItem(line: string): { item: Item; inSession: boolean } {
  const parts = line.trim().split(' · ')
  const head = parts[0] ?? ''
  const kind = head.split(' ')[0] ?? ''
  const title = head.slice(kind.length + 1)
  const last = parts[parts.length - 1] ?? ''
  if (last.startsWith('link=')) {
    return { item: { kind, title, detail: parts.slice(1, -2).join(' · '), memory: parts[parts.length - 2] }, inSession: true }
  }
  return { item: { kind, title, detail: parts.slice(1, last.startsWith('cwd=') ? -1 : undefined).join(' · ') }, inSession: false }
}

/** The text `SpawnSweep --scan` prints in 0.2.1 and earlier (its debug format), kept so the pane works with older apps. */
export function parseScan(text: string, at: number): Snapshot {
  const sessions: Session[] = []
  const loose: Item[] = []
  let running = 0
  let ports: number[] = []
  let simulators: string[] = []
  let inLoose = false

  for (const line of text.split('\n')) {
    const session = /^SESSION (.*) \[([^\]]+)\] (.*?) pinned=(true|false) folder=/.exec(line)
    const totals = /^RUNNING (\d+)\s+DEV PORTS \d+ \[(.*)\]/.exec(line)
    const booted = /booted=(\[.*?\])\s+STACKS=/.exec(line)
    if (session) {
      const raw = session[3] ?? ''
      const state = raw.startsWith('active') ? 'active' : raw.startsWith('idle') ? 'idle' : 'ended'
      sessions.push({ project: session[1] ?? '', agent: session[2] ?? '', state, since: parseDate(raw), pinned: session[4] === 'true', items: [] })
      inLoose = false
    } else if (line.startsWith('UNATTACHED')) {
      inLoose = true
    } else if (line.startsWith('   ')) {
      const { item, inSession } = parseItem(line)
      if (inSession && !inLoose && sessions.length > 0) sessions[sessions.length - 1]?.items.push(item)
      else loose.push(item)
    } else if (totals) {
      running = Number(totals[1])
      ports = (totals[2] ?? '').split(',').map(p => Number(p.trim())).filter(p => p > 0)
    }
    if (booted) {
      try { simulators = JSON.parse(booted[1] ?? '[]') } catch { simulators = [] }
    }
  }
  return { sessions, loose, running, ports, simulators, worktrees: [], at, isScanning: false }
}

/** JSON when the app prints it; 0.2.1 and earlier ignore `--json` and print text. */
export function readScan(stdout: string, at: number): Snapshot {
  const text = stdout.trimStart()
  if (text.startsWith('{')) {
    try {
      return parseJson(JSON.parse(text) as Partial<ScanJSON>, at)
    } catch {
      // Not JSON after all: read it as text.
    }
  }
  return parseScan(stdout, at)
}

function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`
}

export function summary(s: Snapshot): string {
  const parts = [`${s.running} running`, plural(s.ports.length, 'dev port')]
  if (s.simulators.length > 0) parts.push(plural(s.simulators.length, 'simulator'))
  return parts.join(', ')
}

function age(ms: number): string {
  const m = Math.max(0, Math.round(ms / 60_000))
  if (m < 60) return `${m}m`
  const h = Math.round(m / 60)
  return h < 48 ? `${h}h` : `${Math.round(h / 24)}d`
}

function stateLine(s: Session, now: number): string {
  const when = s.since !== undefined ? ` ${age(now - s.since)}` : ''
  const state = s.state === 'active' ? 'active' : `${s.state}${when}`
  return `${s.agent}, ${state}${s.pinned ? ', pinned' : ''}`
}

/** In use first, then the ones an agent made, then by repo. */
function worktreeOrder(a: WorktreeItem, b: WorktreeItem): number {
  return Number(b.inUse) - Number(a.inUse) || Number(!!b.agent) - Number(!!a.agent) || a.repo.localeCompare(b.repo)
}


function openPane($: Engine): void {
  void $.ui.open({ id: PANE, title: 'SpawnSweep', focus: true })
}

// The terminal draws the footer badge; once it has, the status line would only repeat it.
let hasFooterBadge = false
let isBusy = false

async function refresh($: Engine): Promise<void> {
  if (isBusy) return
  isBusy = true
  await update($, snapshot, prev => (prev ? { ...prev, isScanning: true } : prev))
  try {
    const found = await $.fs.stat(APP).catch(() => undefined)
    if (!found) throw new Error(`SpawnSweep isn't installed in Applications. Get it at ${SITE}`)
    const ran = await $.process.run([APP, '--scan', '--json'], { timeoutMs: 60_000 })
    if (ran.exitCode !== 0) throw new Error(ran.stderr.trim() || `The scan stopped with exit code ${ran.exitCode}.`)
    const next = readScan(ran.stdout, await $.clock.now())
    await update($, snapshot, () => next)
    if (!hasFooterBadge) $.ui.status(`${next.running} running`)
  } catch (err) {
    const at = await $.clock.now()
    const error = err instanceof Error ? err.message : String(err)
    await update($, snapshot, prev => ({
      ...(prev ?? { sessions: [], loose: [], running: 0, ports: [], simulators: [], worktrees: [] }),
      at,
      isScanning: false,
      error,
    }))
    if (!hasFooterBadge) $.ui.status('scan failed')
  } finally {
    isBusy = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({ name: 'spawnsweep', description: "Show what's running on this Mac, from SpawnSweep" })
    // The pane opens with every session, as a tab of the side panel, so it's always a click away there.
    void $.ui.open({ id: PANE, title: 'SpawnSweep' })
    void refresh($)
    $.clock.every(EVERY_MS, () => void refresh($))
    return started
  })

  on('command.run', { command: 'spawnsweep' }, async $ => {
    await $.ui.open({ id: PANE, title: 'SpawnSweep' })
    void refresh($)
    return { text: 'SpawnSweep pane opened.' }
  })

  // One control in the footer, beside the session's mode labels: 🌔 and how many things are running; a click
  // opens the pane. A Button is what the desktop footer draws and lets you click (an image or a link there doesn't
  // show or doesn't click). The engine's labels are drawn first, as they were.
  on('ui.render', { component: 'SessionMode' }, async ($, e) => {
    const s = await read($, snapshot)
    if (!hasFooterBadge) { hasFooterBadge = true; $.ui.status(undefined) }
    const failed = s?.error !== undefined
    const count = !s ? '…' : failed ? '!' : String(s.running)
    const { Box, Text, Button } = $.ui.resolve(e)
    return (
      <Box flexDirection="row" gap={1} alignItems="center">
        {e.props.modes.length > 0 ? <Text dimColor>{e.props.modes.join(' & ')}</Text> : null}
        {/* No `label`: the desktop draws a Button's label in place of its children, so the moon and count would vanish. */}
        {/* The footer draws text, not images: the moon emoji stands in for the logo. */}
        <Button key="spawnsweep-badge" plain onPress={() => openPane($)}>🌔 {count}</Button>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const s = await read($, snapshot)

    if (!s) return <Text dimColor>Scanning…</Text>

    const time = new Date(s.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
    const row = (item: Item, key: string) => (
      <Box key={key} flexDirection="column" paddingLeft={2}>
        <Text>
          {item.title}
          {item.memory ? <Text dimColor>  {item.memory}</Text> : null}
        </Text>
        {item.detail ? <Text dimColor size="caption">{item.detail}</Text> : null}
      </Box>
    )
    const worktrees = [...s.worktrees].sort(worktreeOrder)
    const hidden = worktrees.length - WORKTREES_SHOWN

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" justifyContent="space-between" alignItems="center">
          <Text weight="semibold">{summary(s)}</Text>
          <Button key="refresh" label={s.isScanning ? 'Scanning…' : 'Refresh'} onPress={() => refresh($)} />
        </Box>

        {s.error ? <Text color="error">{s.error}</Text> : null}

        {s.sessions.length === 0 && s.loose.length === 0 && !s.error ? (
          <Text dimColor>Nothing left running. Your agents cleaned up after themselves.</Text>
        ) : null}

        {s.sessions.map((session, i) => (
          <Box key={`s${i}`} flexDirection="column">
            <Text>
              <Text weight="semibold">{session.project}</Text>
              <Text dimColor>  {stateLine(session, s.at)}</Text>
            </Text>
            {session.items.length === 0 ? (
              <Box paddingLeft={2}><Text dimColor>Nothing running</Text></Box>
            ) : (
              session.items.map((item, j) => row(item, `s${i}-${j}`))
            )}
          </Box>
        ))}

        {s.loose.length > 0 ? (
          <Box flexDirection="column">
            <Text weight="semibold">Not tied to a session</Text>
            {s.loose.map((item, j) => row(item, `l${j}`))}
          </Box>
        ) : null}

        {worktrees.length > 0 ? (
          <Box flexDirection="column">
            <Text weight="semibold">Worktrees ({worktrees.length})</Text>
            {worktrees.slice(0, WORKTREES_SHOWN).map((w, j) => (
              <Box key={`w${j}`} paddingLeft={2}>
                <Text>
                  {w.repo}
                  <Text dimColor>  {[w.branch ?? 'detached', w.agent, w.inUse ? 'in use' : undefined].filter(Boolean).join(', ')}</Text>
                </Text>
              </Box>
            ))}
            {hidden > 0 ? (
              <Box paddingLeft={2}><Text dimColor>{plural(hidden, 'more worktree')} in SpawnSweep's Storage page</Text></Box>
            ) : null}
          </Box>
        ) : null}

        <Box flexDirection="row" justifyContent="space-between" alignItems="center">
          <Text dimColor size="caption">Updated {time}. Refreshes every 30 seconds.</Text>
          <Button key="open-app" label="Open SpawnSweep" onPress={async () => { await $.process.run(['open', '-b', BUNDLE_ID]).catch(() => undefined) }} />
        </Box>
      </Box>
    )
  })
}
