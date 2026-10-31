// 3 · Turn: the leftovers snap into SpawnSweep's session cards, each under the agent that started it.
import React from "react";
import { AbsoluteFill } from "remotion";
import { AgentGlyph, AgentName, BgCanvas, BlurWords, Grade, Leftover, Moon, Rise, card, useExit } from "../components/kit";
import { theme } from "../theme";

const c = theme.colors;
const sessions: { project: string; agent: AgentName; meta: string; badge: string; rows: [string, string, boolean][] }[] = [
  { project: "decize-webapp", agent: "Claude Code", meta: "Claude Code · ended 2h ago", badge: "Needs attention",
    rows: [[":3000", "Next.js · 412 MB", true], ["node_modules", "2.1 GB", false], ["iPhone 16 Pro", "Simulator", false]] },
  { project: "rey-adventures", agent: "Codex", meta: "Codex · idle 22 min", badge: "Idle",
    rows: [[":5173", "Vite · 96 MB", true], ["supabase stack", "3 containers", false], [":8080", "API watcher", true]] },
];

export const Turn: React.FC = () => {
  const exit = useExit(96);
  return (
    <AbsoluteFill>
      <BgCanvas />
      <AbsoluteFill style={exit}>
        <div style={{ position: "absolute", top: 96, width: "100%" }}>
          <BlurWords text="Every leftover, with the agent that started it." delay={2} size={68} color={c.ink}
            hero={["agent"]} heroColor={c.accent} />
        </div>
        <Rise delay={8} y={50} style={{ position: "absolute", left: 230, top: 240 }}>
          <div style={{ ...card(30), width: 1460, padding: 32, boxSizing: "border-box", background: "#F7FAF4" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 26 }}>
              <Moon size={38} />
              <div style={{ fontFamily: theme.fonts.display, fontSize: 28, fontWeight: 600, color: c.ink }}>SpawnSweep</div>
              <div style={{ flex: 1 }} />
              <div style={{ fontFamily: theme.fonts.body, fontSize: 20, fontWeight: 500, color: c.accent, padding: "8px 16px",
                borderRadius: 12, background: "#DCE9D5" }}>Sessions</div>
            </div>
            <div style={{ display: "flex", gap: 28 }}>
              {sessions.map((s, si) => (
                <div key={s.project} style={{ ...card(24), flex: 1, padding: 26, display: "flex", flexDirection: "column", gap: 14 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 16, marginBottom: 6 }}>
                    <AgentGlyph agent={s.agent} />
                    <div>
                      <div style={{ fontFamily: theme.fonts.display, fontSize: 30, fontWeight: 600, color: c.ink, letterSpacing: "-0.02em" }}>{s.project}</div>
                      <div style={{ fontFamily: theme.fonts.body, fontSize: 19, color: c.inkDim }}>{s.meta}</div>
                    </div>
                    <div style={{ flex: 1 }} />
                    <div style={{ fontFamily: theme.fonts.body, fontSize: 17, fontWeight: 600, padding: "6px 12px", borderRadius: 10,
                      color: si === 0 ? c.amber : c.inkDim, background: si === 0 ? c.amberFill : "#EEF2EB" }}>{s.badge}</div>
                  </div>
                  {s.rows.map(([label, detail, mono], ri) => (
                    <Rise key={label} delay={28 + (si * 3 + ri) * 5} x={140} y={0} config="snappy">
                      <Leftover label={label} detail={detail} mono={mono} width={632} />
                    </Rise>
                  ))}
                </div>
              ))}
            </div>
          </div>
        </Rise>
      </AbsoluteFill>
      <Grade />
    </AbsoluteFill>
  );
};
