// Synthesizes the soundtrack as 16-bit WAVs into public/sfx: a calm 100 BPM pad bed and a small hit kit.
// Deterministic (seeded noise), no downloads. Run: node scripts/sfx.mjs
import { writeFileSync, mkdirSync } from "node:fs";

const SR = 44100;
const BPM = 100, BEAT = 60 / BPM; // 0.6 s
const TOTAL = 33 * BEAT + 1.2; // video is 33 beats; a little tail for the last chord

let seed = 7;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;
const midi = (n) => 440 * 2 ** ((n - 69) / 12);

function wav(path, channels) {
  const n = channels[0].length, ch = channels.length;
  let peak = 0;
  for (const c of channels) for (const v of c) peak = Math.max(peak, Math.abs(v));
  const gain = peak > 0 ? 0.89 / peak : 1;
  const buf = Buffer.alloc(44 + n * ch * 2);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * ch * 2, 4); buf.write("WAVE", 8);
  buf.write("fmt ", 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(ch, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * ch * 2, 28); buf.writeUInt16LE(ch * 2, 32); buf.writeUInt16LE(16, 34);
  buf.write("data", 36); buf.writeUInt32LE(n * ch * 2, 40);
  for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, channels[c][i] * gain)) * 32767), 44 + (i * ch + c) * 2);
  }
  writeFileSync(path, buf);
}

// One-pole low-pass, in place.
function lowpass(x, cutoffAt) {
  let y = 0;
  for (let i = 0; i < x.length; i++) {
    const a = 1 - Math.exp((-2 * Math.PI * cutoffAt(i / SR)) / SR);
    y += a * (x[i] - y); x[i] = y;
  }
  return x;
}

// MARK: Music bed — Fmaj9, Am7, Dm9, Cmaj9, eight beats each, soft plucks from the problem scene on.
function music() {
  const n = Math.ceil(TOTAL * SR);
  const L = new Float32Array(n), R = new Float32Array(n);
  const chords = [[41, 53, 57, 60, 64, 67], [45, 52, 57, 60, 64, 67], [38, 50, 57, 60, 64, 65], [36, 48, 55, 59, 62, 64]];
  const chordLen = 8 * BEAT;
  const voice = (t, f) => Math.sin(2 * Math.PI * f * t) + 0.32 * Math.sin(4 * Math.PI * f * t) + 0.12 * Math.sin(6 * Math.PI * f * t);

  // Pad: each chord fades in over 0.9 s and out over 1.4 s past its end, so chords overlap smoothly.
  chords.forEach((notes, ci) => {
    const start = ci * chordLen, end = ci === chords.length - 1 ? TOTAL - 0.2 : start + chordLen;
    for (let i = Math.floor(start * SR); i < Math.min(n, Math.ceil((end + 1.4) * SR)); i++) {
      const t = i / SR, local = t - start;
      const env = Math.min(1, local / 0.9) * (t > end ? Math.max(0, 1 - (t - end) / 1.4) : 1);
      let l = 0, r = 0;
      notes.forEach((m, k) => {
        const f = midi(m), amp = (k === 0 ? 0.5 : 0.22) * env;
        l += amp * voice(t, f * 0.9985); r += amp * voice(t, f * 1.0015);
      });
      L[i] += l; R[i] += r;
    }
  });

  // Plucks: eighth notes up the chord, from beat 5 (the problem scene) to beat 27 (the end card).
  const plucks = new Float32Array(n);
  for (let b = 5 * 2; b < 27 * 2; b++) {
    const t0 = b * (BEAT / 2), chord = chords[Math.min(3, Math.floor(t0 / chordLen))];
    const note = chord[1 + ((b * 3) % (chord.length - 1))] + 12;
    for (let i = Math.floor(t0 * SR); i < Math.min(n, Math.floor((t0 + 0.6) * SR)); i++) {
      const t = i / SR - t0;
      plucks[i] += 0.16 * Math.exp(-t / 0.18) * (Math.sin(2 * Math.PI * midi(note) * t) + 0.2 * Math.sin(4 * Math.PI * midi(note) * t));
    }
  }
  // A ping-pong echo gives the plucks some room.
  const d = Math.floor(BEAT * 0.75 * SR);
  for (let i = 0; i < n; i++) {
    L[i] += plucks[i] + (i >= d ? 0.35 * plucks[i - d] : 0);
    R[i] += plucks[i] + (i >= 2 * d ? 0.25 * plucks[i - 2 * d] : 0);
  }
  lowpass(L, (t) => 1800 + 900 * Math.sin(t / 3)); lowpass(R, (t) => 1800 + 900 * Math.sin(t / 3));
  // Fade the very end out.
  for (let i = 0; i < n; i++) { const t = i / SR, g = t > TOTAL - 1.6 ? Math.max(0, (TOTAL - t) / 1.6) : 1; L[i] *= g; R[i] *= g; }
  return [L, R];
}

// MARK: Hits
function whoosh(len = 0.55) {
  const n = Math.ceil(len * SR), x = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / len / SR; x[i] = rand() * Math.sin(Math.PI * t ** 0.7) ** 2; }
  return [lowpass(x, (t) => 400 + 5200 * Math.sin(Math.PI * Math.min(1, t / len)))];
}
function pop() {
  const n = Math.ceil(0.14 * SR), x = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR, f = 260 + 700 * Math.exp(-t / 0.025); ph += (2 * Math.PI * f) / SR; x[i] = Math.sin(ph) * Math.exp(-t / 0.045); }
  return [x];
}
function tick() {
  const n = Math.ceil(0.05 * SR), x = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / SR; x[i] = (Math.sin(2 * Math.PI * 2300 * t) * 0.7 + rand() * 0.3) * Math.exp(-t / 0.008); }
  return [x];
}
function click() {
  const n = Math.ceil(0.09 * SR), x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, a = Math.exp(-t / 0.006), b = t > 0.035 ? Math.exp(-(t - 0.035) / 0.008) * 0.6 : 0;
    x[i] = Math.sin(2 * Math.PI * 1500 * t) * a + Math.sin(2 * Math.PI * 1100 * t) * b;
  }
  return [x];
}
function thump() {
  const n = Math.ceil(0.6 * SR), x = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR, f = 42 + 80 * Math.exp(-t / 0.05); ph += (2 * Math.PI * f) / SR; x[i] = Math.sin(ph) * Math.exp(-t / 0.22); }
  return [x];
}
function shimmer() {
  const len = 2.2, n = Math.ceil(len * SR), x = new Float32Array(n);
  const freqs = [1318.5, 1760, 2093, 2637, 3136];
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.min(1, t / 0.06) * Math.exp(-t / 0.7);
    x[i] = freqs.reduce((s, f, k) => s + Math.sin(2 * Math.PI * f * t * (1 + 0.002 * Math.sin(2 * Math.PI * 5 * t)) + k) / (k + 1), 0) * env;
  }
  return [x];
}

mkdirSync("public/sfx", { recursive: true });
wav("public/sfx/music.wav", music());
for (const [name, fn] of Object.entries({ whoosh, pop, tick, click, thump, shimmer })) wav(`public/sfx/${name}.wav`, fn());
console.log("wrote public/sfx: music, whoosh, pop, tick, click, thump, shimmer");
