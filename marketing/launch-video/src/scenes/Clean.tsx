// 4 · Clean up: a preview, one press, and each leftover drifts into the moon while the freed numbers count up.
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { BgCanvas, BlurWords, Counter, Grade, Moon, Rise, card, useBreathe } from "../components/kit";
import { clamp, theme } from "../theme";

const c = theme.colors;
export const CLEAN_MOON = { x: 1440, y: 500, size: 280 };
const CARD = { x: 180, y: 250, w: 820 };
const ROW_H = 74, ROWS_TOP = 132;
const rows: [string, string][] = [
  [":3000 Next.js", "412 MB"], [":5173 Vite", "96 MB"], [":8080 API watcher", "38 MB"],
  ["node_modules", "2.1 GB"], ["iPhone 16 Pro simulator", "1.4 GB"], ["supabase stack", "3 containers"],
];
const PRESS = 42;
const flyStart = (i: number) => 48 + i * 5;
const FLY = 16;

export const Clean: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const press = spring({ frame: f - PRESS, fps, config: theme.spring.snappy });
  const pressScale = f < PRESS ? 1 : interpolate(Math.sin(Math.min(1, press) * Math.PI), [0, 1], [1, 0.94]);
  const landed = rows.filter((_, i) => f >= flyStart(i) + FLY).length;
  const glow = interpolate(landed, [0, rows.length], [0, 0.7], clamp);
  const breathe = useBreathe(2);

  return (
    <AbsoluteFill>
      <BgCanvas />
      <div style={{ position: "absolute", top: 96, width: "100%" }}>
        <BlurWords text="Put it away. Keep every line of work." delay={2} size={68} color={c.ink} />
      </div>

      <Rise delay={6} y={50} style={{ position: "absolute", left: CARD.x, top: CARD.y }}>
        <div style={{ ...card(28), width: CARD.w, height: ROWS_TOP + rows.length * ROW_H + 120, padding: 30, boxSizing: "border-box", position: "relative" }}>
          <div style={{ fontFamily: theme.fonts.display, fontSize: 32, fontWeight: 600, color: c.ink, letterSpacing: "-0.02em" }}>Clean up 6 items?</div>
          <div style={{ fontFamily: theme.fonts.body, fontSize: 20, color: c.inkDim, marginTop: 6 }}>Servers stop and build data goes. Your code and history stay.</div>
          {/* Once every row has gone into the moon, the card says so. */}
          <Rise delay={flyStart(rows.length - 1) + FLY + 2} config="bouncy"
            style={{ position: "absolute", left: 0, right: 0, top: ROWS_TOP + 90, display: "flex", flexDirection: "column", alignItems: "center", gap: 18 }}>
            <div style={{ transform: "scale(2.2)" }}><Check /></div>
            <div style={{ fontFamily: theme.fonts.display, fontSize: 34, fontWeight: 600, color: c.ink, letterSpacing: "-0.02em", marginTop: 14 }}>All put away.</div>
            <div style={{ fontFamily: theme.fonts.body, fontSize: 22, color: c.inkDim }}>Every commit and branch is right where you left it.</div>
          </Rise>
          <div style={{ position: "absolute", left: 30, right: 30, bottom: 28, display: "flex", justifyContent: "flex-end" }}>
            <div style={{ transform: `scale(${pressScale})`, fontFamily: theme.fonts.body, fontSize: 22, fontWeight: 600, color: "#fff",
              padding: "14px 28px", borderRadius: 14, background: `linear-gradient(${c.accentLight}, ${c.accent})`,
              boxShadow: `0 10px 24px -8px ${c.accent}AA, inset 1px 2px 3px rgba(255,255,255,0.35)` }}>Clean up</div>
          </div>
        </div>
      </Rise>

      {rows.map(([label, detail], i) => {
        const left = CARD.x + 30, top = CARD.y + ROWS_TOP + i * ROW_H, w = CARD.w - 60;
        const t = interpolate(f, [flyStart(i), flyStart(i) + FLY], [0, 1], { ...clamp, easing: theme.ease.inOut });
        const dx = CLEAN_MOON.x - (left + w / 2), dy = CLEAN_MOON.y - (top + 28);
        return (
          <Rise key={label} delay={12 + i * 4} x={40} y={0} config="snappy" style={{ position: "absolute", left, top }}>
            <div style={{ width: w, height: 58, display: "flex", alignItems: "center", gap: 16, padding: "0 18px", boxSizing: "border-box",
              borderRadius: 14, background: "#F3F7F0", border: `1px solid ${c.border}`, opacity: 1 - t,
              transform: `translate(${dx * t}px, ${dy * t}px) scale(${1 - 0.8 * t})`, filter: `blur(${4 * t}px)` }}>
              <Check />
              <div style={{ fontFamily: theme.fonts.body, fontSize: 22, fontWeight: 500, color: c.ink }}>{label}</div>
              <div style={{ flex: 1 }} />
              <div style={{ fontFamily: theme.fonts.body, fontSize: 20, color: c.inkDim, fontVariantNumeric: "tabular-nums" }}>{detail}</div>
            </div>
          </Rise>
        );
      })}

      <Rise delay={4} config="bouncy" style={{ position: "absolute", left: CLEAN_MOON.x - CLEAN_MOON.size / 2, top: CLEAN_MOON.y - CLEAN_MOON.size / 2 }}>
        <div style={{ transform: `${breathe} scale(${1 + glow * 0.06})` }}><Moon size={CLEAN_MOON.size} glow={glow} /></div>
      </Rise>

      <div style={{ position: "absolute", left: CLEAN_MOON.x - 380, top: 760, width: 760, display: "flex", gap: 18 }}>
        <Stat delay={64} to={3} label="ports freed" />
        <Stat delay={69} to={2.4} decimals={1} suffix=" GB" label="memory back" />
        <Stat delay={74} to={150} suffix=" GB" label="disk cleared" />
      </div>
      <Grade />
    </AbsoluteFill>
  );
};

const Check: React.FC = () => (
  <div style={{ width: 26, height: 26, borderRadius: 8, background: c.accentLight, display: "flex", alignItems: "center", justifyContent: "center" }}>
    <svg width={16} height={16} viewBox="0 0 16 16"><polyline points="3,8.5 6.5,12 13,4.5" stroke="#fff" strokeWidth={2.4} fill="none" strokeLinecap="round" strokeLinejoin="round" /></svg>
  </div>
);

const Stat: React.FC<{ delay: number; to: number; decimals?: number; suffix?: string; label: string }> = ({ delay, to, decimals = 0, suffix = "", label }) => (
  <Rise delay={delay} style={{ flex: 1 }}>
    <div style={{ ...card(20), padding: "18px 20px" }}>
      <div style={{ fontFamily: theme.fonts.display, fontSize: 44, fontWeight: 600, color: c.ink, letterSpacing: "-0.02em" }}>
        <Counter to={to} delay={delay + 2} decimals={decimals} suffix={suffix} config="fastCount" />
      </div>
      <div style={{ fontFamily: theme.fonts.body, fontSize: 19, color: c.inkDim, marginTop: 2 }}>{label}</div>
    </div>
  </Rise>
);
