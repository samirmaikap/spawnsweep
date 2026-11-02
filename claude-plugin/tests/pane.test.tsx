import { expect, mock, test } from 'claude-code/testing'

import { parseScan, readScan, summary } from '../hooks/register'

// Real `SpawnSweep --scan` output from SpawnSweep 0.2.1, trimmed.
const SCAN = `SESSION shop-frontend [Claude app] idle(since: 2026-10-31 08:46:43 +0000) pinned=false folder=/Users/me/Sites/shop-frontend
   server Next.js :3110 · Server + child processes · 2d 1h · 24 MB · link=weak
SESSION travel-site [Codex] idle(since: 2026-10-30 15:51:48 +0000) pinned=true folder=/Users/me/Sites/travel-site
   server Vite :4175 · Server + child processes · 3d · 13 MB · link=weak
   stack travel-site stack · 1 container grouped as one stack · 0 MB · link=weak
UNATTACHED
   simulator iPhone 17 Pro · iOS 26.5 · Booted 2h 8m ago · cwd=-
DEVICES booted=["iPhone 17 Pro"]  STACKS=["travel-site(1)"]  TUNNELS=0
RUNNING 4  DEV PORTS 3 [3000, 3110, 4175]
`

const NOW = Date.parse('2026-11-02T10:46:43Z')

// What `SpawnSweep --scan --json` prints, version 1.
const JSON_SCAN = JSON.stringify({
  version: 1,
  scannedAt: '2026-11-02T10:46:43Z',
  running: 2,
  ports: [3110],
  sessions: [{
    project: 'shop-frontend', agent: 'Claude app', folder: '/Users/me/Sites/shop-frontend', branch: 'main',
    state: 'idle', since: '2026-10-31T08:46:43Z', pinned: false,
    resources: [{ kind: 'server', title: 'Next.js :3110', detail: 'Server + child processes', ports: [3110], memoryBytes: 24_000_000, startedAt: null, cwd: '/Users/me/Sites/shop-frontend' }],
  }],
  unattached: [{ kind: 'simulator', title: 'iPhone 17 Pro', detail: 'iOS 26.5', ports: [], memoryBytes: 0, startedAt: null, cwd: null }],
  simulators: [{ name: 'iPhone 17 Pro', runtime: 'iOS 26.5', bootedAt: '2026-11-02T08:38:00Z' }],
  worktrees: [
    { repo: 'spawnsweep', repoPath: '/Users/me/Sites/spawnsweep', path: '/Users/me/.codex/worktrees/a1/spawnsweep', branch: 'scan-json', agent: 'Codex', inUse: false },
    { repo: 'chat-api', repoPath: '/Users/me/Sites/chat-api', path: '/Users/me/Sites/chat-api-billing', branch: 'billing', agent: null, inUse: true },
  ],
})

test('parses sessions, their items, loose items and totals', () => {
  const s = parseScan(SCAN, NOW)
  expect(s.sessions.map(x => x.project)).toEqual(['shop-frontend', 'travel-site'])
  expect(s.sessions[0]?.agent).toBe('Claude app')
  expect(s.sessions[0]?.state).toBe('idle')
  expect(s.sessions[0]?.since).toBe(Date.parse('2026-10-31T08:46:43Z'))
  expect(s.sessions[1]?.pinned).toBe(true)
  expect(s.sessions[0]?.items[0]).toEqual({ kind: 'server', title: 'Next.js :3110', detail: 'Server + child processes · 2d 1h', memory: '24 MB' })
  expect(s.sessions[1]?.items.length).toBe(2)
  expect(s.loose).toEqual([{ kind: 'simulator', title: 'iPhone 17 Pro', detail: 'iOS 26.5 · Booted 2h 8m ago' }])
  expect(s.running).toBe(4)
  expect(s.ports).toEqual([3000, 3110, 4175])
  expect(s.simulators).toEqual(['iPhone 17 Pro'])
  expect(summary(s)).toBe('4 running, 3 dev ports, 1 simulator')
})

test('reads the JSON scan, worktrees included', () => {
  const s = readScan(JSON_SCAN, NOW)
  expect(s.sessions[0]?.since).toBe(Date.parse('2026-10-31T08:46:43Z'))
  expect(s.sessions[0]?.items[0]).toEqual({ kind: 'server', title: 'Next.js :3110', detail: 'Server + child processes', memory: '24 MB' })
  expect(s.loose[0]).toEqual({ kind: 'simulator', title: 'iPhone 17 Pro', detail: 'iOS 26.5' })
  expect(s.worktrees.map(w => w.branch)).toEqual(['scan-json', 'billing'])
  expect(s.worktrees[1]?.inUse).toBe(true)
  expect(summary(s)).toBe('2 running, 1 dev port, 1 simulator')
})

test('an app before --json prints text, and the pane still reads it', () => {
  const s = readScan(SCAN, NOW)
  expect(s.sessions.length).toBe(2)
  expect(s.worktrees).toEqual([])
})

test('an empty Mac reads as nothing running', () => {
  const s = parseScan('UNATTACHED\nDEVICES booted=[]  STACKS=[]  TUNNELS=0\nRUNNING 0  DEV PORTS 0 []\n', NOW)
  expect(s.sessions).toEqual([])
  expect(s.loose).toEqual([])
  expect(summary(s)).toBe('0 running, 0 dev ports')
})

test('the pane draws the scan on every surface that docks a pane', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  on('command.register', () => ({ value: { command: 'spawnsweep' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: 0 } }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: SCAN, stderr: '' } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await clock.settle()

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'spawnsweep',
      surface,
      component: 'Pane',
      requestId: 'spawnsweep',
      props: { title: 'SpawnSweep', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
    })
    expect((await ui.find({ type: 'Text', text: /4 running, 3 dev ports, 1 simulator/ }))).toBeDefined()
    expect((await ui.find({ type: 'Text', text: /Next\.js :3110/ }))).toBeDefined()
    expect((await ui.find({ type: 'Text', text: /Not tied to a session/ }))).toBeDefined()
    await ui.press({ key: 'refresh' })
    await ui.unmount()
  }
})

test('the pane lists worktrees from the JSON scan, in-use ones first', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  on('command.register', () => ({ value: { command: 'spawnsweep' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: 0 } }))
  on('process.run', (_, e) => ({ value: { exitCode: 0, stdout: e.argv.includes('--json') ? JSON_SCAN : SCAN, stderr: '' } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await clock.settle()

  const ui = await $.ui.mount({
    plugin: 'spawnsweep',
    surface: 'desktop',
    component: 'Pane',
    requestId: 'spawnsweep',
    props: { title: 'SpawnSweep', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
  })
  expect(await ui.find({ type: 'Text', text: /Worktrees \(2\)/ })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: /^chat-api/ }))?.text).toBe('chat-api  billing, in use')
  await ui.unmount()
})

test('the pane opens with the session, the count is the status line, and the terminal footer badge opens the pane', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const opened: string[] = []
  const statuses: unknown[] = []
  on('command.register', () => ({ value: { command: 'spawnsweep' } }))
  on('ui.open', (_, e) => { opened.push(e.id); return { value: { isPlaced: true } } })
  on('ui.status', (_, e) => { statuses.push(e); return { value: undefined } })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: 0 } }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: JSON_SCAN, stderr: '' } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await clock.settle()
  expect(opened).toEqual(['spawnsweep'])   // opened with the session
  expect(JSON.stringify(statuses)).toContain('2 running')

  const footer = await $.ui.mount({ plugin: 'spawnsweep', surface: 'terminal', component: 'SessionMode', props: { modes: ['focus'] } })
  expect((await footer.find({ type: 'Text', text: /focus/ }))?.text).toBe('focus')
  expect((await footer.find({ key: 'spawnsweep-badge' }))?.text).toBe('☾ 2')
  await footer.press({ key: 'spawnsweep-badge' })
  await footer.unmount()
  expect(opened).toEqual(['spawnsweep', 'spawnsweep'])
})
