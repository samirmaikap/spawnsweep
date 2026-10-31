// 2 · Problem: lines draw from each agent out to what it left running, and the pile keeps growing.
import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { AgentGlyph, AgentName, BgCanvas, BlurWords, Counter, Grade, Leftover, Rise, card, useBreathe, useExit } from "../components/kit";
import { clamp, theme } from "../theme";

const c = theme.colors;
const AGENT_X = 250, AGENT_W = 340, CHIP_X = 1110, CHIP_W = 560;
const agents: { name: AgentName; y: number }[] = [
  { name: "Claude Code", y: 370 }, { name: "Codex", y: 590 }, { name: "Cursor", y: 810 },
];
const leftovers = [
  { agent: 0, y: 320, label: ":3000", detail: "Next.js", mono: true },
  { agent: 0, y: 420, label: "node_modules", detail: "2.1 GB", mono: false },
  { agent: 1, y: 540, label: ":5173", detail: "Vite", mono: true },
  { agent: 1, y: 640, label: "supabase stack", detail: "3 containers", mono: false },
  { agent: 2, y: 760, label: "iPhone 16 Pro", detail: "Simulator", mono: false },
  { agent: 2, y: 860, label: ":8080", detail: "API watcher", mono: true },
];
const lineStart = (i: number) => 24 + i * 9;

export const Problem: React.FC = () => {
  const f = useCurrentFrame();
  const exit = useExit(150);
  return (
    <AbsoluteFill>
      <BgCanvas />
      <AbsoluteFill style={exit}>
        <div style={{ position: "absolute", top: 96, width: "100%" }}>
          <BlurWords text="Ports. Simulators. Docker. Build data." delay={4} per={4} size={76} color={c.ink} />
        </div>

        <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
          {leftovers.map((l, i) => {
            const a = agents[l.agent];
            const x1 = AGENT_X + AGENT_W, x2 = CHIP_X, mid = (x1 + x2) / 2;
            const t = interpolate(f, [lineStart(i), lineStart(i) + 18], [0, 1], { ...clamp, easing: theme.ease.out });
            return <path key={i} d={`M ${x1} ${a.y} C ${mid} ${a.y}, ${mid} ${l.y}, ${x2} ${l.y}`} pathLength={1}
              strokeDasharray={1} strokeDashoffset={1 - t} stroke={c.ink} strokeWidth={2.5} fill="none" strokeLinecap="round" opacity={0.75} />;
          })}
        </svg>

        {agents.map((a, i) => (
          <Rise key={a.name} delay={8 + i * 5} x={-40} y={0} style={{ position: "absolute", left: AGENT_X, top: a.y - 42 }}>
            <AgentPill name={a.name} seed={i} />
          </Rise>
        ))}
        {leftovers.map((l, i) => (
          <Rise key={l.label} delay={lineStart(i) + 12} x={-30} y={0} config="snappy"
            style={{ position: "absolute", left: CHIP_X, top: l.y - 32 }}>
            <Floating seed={i + 3}><Leftover label={l.label} detail={l.detail} mono={l.mono} width={CHIP_W} /></Floating>
          </Rise>
        ))}

        <Rise delay={98} style={{ position: "absolute", top: 960, width: "100%", display: "flex", justifyContent: "center" }}>
          <div style={{ fontFamily: theme.fonts.body, fontSize: 30, color: c.inkDim }}>
            <span style={{ color: c.ink, fontWeight: 600 }}>6 things</span> still running after the sessions ended ·{" "}
            <Counter to={150} delay={100} suffix=" GB" style={{ color: c.ink, fontWeight: 600 }} /> of leftovers
          </div>
        </Rise>
      </AbsoluteFill>
      <Grade />
    </AbsoluteFill>
  );
};

const AgentPill: React.FC<{ name: AgentName; seed: number }> = ({ name, seed }) => (
  <Floating seed={seed}>
    <div style={{ ...card(20), width: AGENT_W, height: 84, padding: "0 20px", display: "flex", alignItems: "center", gap: 18, boxSizing: "border-box" }}>
      <AgentGlyph agent={name} />
      <div style={{ fontFamily: theme.fonts.display, fontSize: 32, fontWeight: 600, color: c.ink, letterSpacing: "-0.02em" }}>{name}</div>
    </div>
  </Floating>
);

const Floating: React.FC<{ seed: number; children: React.ReactNode }> = ({ seed, children }) => (
  <div style={{ transform: useBreathe(seed) }}>{children}</div>
);
