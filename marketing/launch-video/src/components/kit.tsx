// Reusable pieces: backgrounds, grade/grain/vignette, the clay moon, text reveals, chips, counters, wipes.
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { clamp, theme } from "../theme";

const c = theme.colors;

// MARK: Backgrounds (never flat)

export const BgNight: React.FC = () => {
  const f = useCurrentFrame();
  const d1 = Math.sin(f / 55) * 50;
  const d2 = Math.cos(f / 70) * 40;
  return (
    <AbsoluteFill style={{ background: c.night }}>
      <div style={{ position: "absolute", width: 1300, height: 1300, borderRadius: "50%", top: -560, left: -260 + d1,
        filter: "blur(60px)", background: `radial-gradient(circle, ${c.accent}55, transparent 62%)` }} />
      <div style={{ position: "absolute", width: 1000, height: 1000, borderRadius: "50%", bottom: -520, right: -200 - d2,
        filter: "blur(80px)", background: `radial-gradient(circle, ${c.nightAlt}, transparent 65%)` }} />
    </AbsoluteFill>
  );
};

/** The light sage canvas with a faint grid, like a design board. */
export const BgCanvas: React.FC = () => {
  const f = useCurrentFrame();
  const d1 = Math.sin(f / 60) * 40;
  return (
    <AbsoluteFill style={{ background: c.canvas }}>
      <AbsoluteFill style={{
        backgroundImage: `linear-gradient(${c.grid} 1px, transparent 1px), linear-gradient(90deg, ${c.grid} 1px, transparent 1px)`,
        backgroundSize: "64px 64px", backgroundPosition: `${(f * 0.3) % 64}px 0px`,
      }} />
      <div style={{ position: "absolute", width: 1200, height: 1200, borderRadius: "50%", top: -600, right: -200 + d1,
        filter: "blur(70px)", background: `radial-gradient(circle, ${c.canvasAlt}, transparent 65%)` }} />
      <div style={{ position: "absolute", width: 900, height: 900, borderRadius: "50%", bottom: -500, left: -200,
        filter: "blur(70px)", background: `radial-gradient(circle, #FFFFFFAA, transparent 65%)` }} />
    </AbsoluteFill>
  );
};

// MARK: Finish layers (grade above content, grain and vignette on top)

export const Grade: React.FC<{ dark?: boolean }> = ({ dark = false }) => (
  <AbsoluteFill style={{ pointerEvents: "none" }}>
    <AbsoluteFill style={{ backgroundColor: c.accent, mixBlendMode: "soft-light", opacity: dark ? 0.2 : 0.1 }} />
    <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(0,0,0,0.08), transparent 28%, transparent 72%, rgba(0,0,0,0.14))" }} />
  </AbsoluteFill>
);

export const Grain: React.FC<{ dark?: boolean }> = ({ dark = false }) => {
  const f = useCurrentFrame();
  const noise = `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='220' height='220'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='220' height='220' filter='url(%23n)' opacity='0.5'/%3E%3C/svg%3E")`;
  return <AbsoluteFill style={{ pointerEvents: "none", backgroundImage: noise, backgroundSize: "220px",
    backgroundPosition: `${(f * 7) % 220}px ${(f * 13) % 220}px`, opacity: dark ? 0.07 : 0.05,
    mixBlendMode: dark ? "overlay" : "multiply" }} />;
};

export const Vignette: React.FC<{ dark?: boolean }> = ({ dark = false }) => (
  <AbsoluteFill style={{ pointerEvents: "none",
    background: `radial-gradient(ellipse at center, transparent 56%, rgba(0,0,0,${dark ? 0.32 : 0.12}) 100%)` }} />
);

// MARK: The clay moon (the app's mark)

export const Moon: React.FC<{ size: number; glow?: number }> = ({ size, glow = 0 }) => (
  <div style={{ position: "relative", width: size, height: size }}>
    <div style={{ position: "absolute", inset: 0, borderRadius: "50%",
      background: `radial-gradient(circle at 28% 22%, ${c.moon[0]}, ${c.moon[1]} 30%, ${c.moon[2]} 62%, ${c.moon[3]})`,
      boxShadow: `${size * 0.03}px ${size * 0.07}px ${size * 0.16}px rgba(20, 40, 28, 0.35)` +
        (glow > 0 ? `, 0 0 ${size * 0.5 * glow}px ${c.glow}, 0 0 ${size * glow}px ${c.glow}` : "") }} />
    <div style={{ position: "absolute", width: size * 0.62, height: size * 0.62, left: size * 0.25, top: size * 0.09,
      borderRadius: "50%", background: `linear-gradient(135deg, ${c.crater[0]}, ${c.crater[1]})`,
      boxShadow: `inset ${size * 0.015}px ${size * 0.025}px ${size * 0.045}px rgba(88, 122, 92, 0.35)` }} />
    <div style={{ position: "absolute", inset: 0, borderRadius: "50%",
      boxShadow: `inset ${size * 0.012}px ${size * 0.016}px 0 rgba(255,255,255,0.6)` }} />
  </div>
);

// MARK: Motion helpers

/** Fade + rise + scale on a spring. The workhorse entrance. */
export const Rise: React.FC<{ delay?: number; y?: number; x?: number; config?: keyof typeof theme.spring;
  style?: React.CSSProperties; children: React.ReactNode }> =
  ({ delay = 0, y = 36, x = 0, config = "smooth", style, children }) => {
    const f = useCurrentFrame();
    const { fps } = useVideoConfig();
    const p = spring({ frame: f - delay, fps, config: theme.spring[config] });
    return (
      <div style={{ ...style, opacity: p,
        transform: `translate(${interpolate(p, [0, 1], [x, 0])}px, ${interpolate(p, [0, 1], [y, 0])}px) scale(${interpolate(p, [0, 1], [0.94, 1])})` }}>
        {children}
      </div>
    );
  };

/** Words arrive one by one out of a soft blur, like the reference. `hero` words take the highlight color. */
export const BlurWords: React.FC<{ text: string; delay?: number; per?: number; size: number; color: string;
  hero?: string[]; heroColor?: string; weight?: number; style?: React.CSSProperties }> =
  ({ text, delay = 0, per = 3, size, color, hero = [], heroColor = c.hero, weight = 600, style }) => {
    const f = useCurrentFrame();
    const { fps } = useVideoConfig();
    return (
      <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", columnGap: Math.round(size * 0.26),
        fontFamily: theme.fonts.display, fontSize: size, fontWeight: weight, letterSpacing: "-0.03em", lineHeight: 1.08,
        color, ...style }}>
        {text.split(" ").map((w, i) => {
          const p = spring({ frame: f - delay - i * per, fps, config: theme.spring.smooth });
          return (
            <span key={i} style={{ display: "inline-block", opacity: p, filter: `blur(${interpolate(p, [0, 1], [14, 0])}px)`,
              transform: `translateY(${interpolate(p, [0, 1], [size * 0.28, 0])}px)`,
              color: hero.includes(w) ? heroColor : undefined }}>{w}</span>
          );
        })}
      </div>
    );
  };

/** Leaves faster than it came: up, out of focus, gone in about 10 frames. */
export const useExit = (at: number, length = 10) => {
  const f = useCurrentFrame();
  const t = interpolate(f, [at, at + length], [0, 1], { ...clamp, easing: theme.ease.in });
  return { opacity: 1 - t, transform: `translateY(${-36 * t}px)`, filter: `blur(${8 * t}px)` } as React.CSSProperties;
};

/** Gentle idle float for anything that sits on screen. */
export const useBreathe = (seed = 0) => {
  const f = useCurrentFrame();
  return `translateY(${Math.sin((f + seed * 17) / 26) * 3}px)`;
};

/** Counts up on a soft spring, with tabular digits so nothing jitters. */
export const Counter: React.FC<{ to: number; delay: number; decimals?: number; suffix?: string; style?: React.CSSProperties;
  config?: "count" | "fastCount" }> =
  ({ to, delay, decimals = 0, suffix = "", style, config = "count" }) => {
    const f = useCurrentFrame();
    const { fps } = useVideoConfig();
    const v = interpolate(spring({ frame: f - delay, fps, config: theme.spring[config] }), [0, 1], [0, to]);
    return <span style={{ fontVariantNumeric: "tabular-nums", ...style }}>{v.toFixed(decimals)}{suffix}</span>;
  };

/** A circle of the next scene's background grows from a point and covers the frame. */
export const Wipe: React.FC<{ color: string; x: number; y: number; length?: number }> = ({ color, x, y, length = 14 }) => {
  const f = useCurrentFrame();
  const r = interpolate(f, [0, length], [0, 2400], { ...clamp, easing: theme.ease.inOut });
  return <AbsoluteFill style={{ pointerEvents: "none" }}>
    <div style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", background: color }} />
  </AbsoluteFill>;
};

// MARK: Pieces of the app

export type AgentName = "Claude Code" | "Codex" | "Cursor";

/** Small drawn glyphs for each agent, in theme colors (no emoji). */
export const AgentGlyph: React.FC<{ agent: AgentName; size?: number }> = ({ agent, size = 30 }) => {
  const s = size;
  const stroke = { stroke: c.accent, strokeWidth: 2.4, strokeLinecap: "round" as const, fill: "none" };
  return (
    <div style={{ width: s + 18, height: s + 18, borderRadius: 14, display: "flex", alignItems: "center", justifyContent: "center",
      background: "#DCE9D5", boxShadow: "inset 1px 2px 3px rgba(255,255,255,0.9), inset -1px -2px 4px rgba(92,122,98,0.14)" }}>
      <svg width={s} height={s} viewBox="0 0 30 30">
        {agent === "Claude Code" && [0, 45, 90, 135].map((a) => (
          <line key={a} x1={15} y1={5} x2={15} y2={25} transform={`rotate(${a} 15 15)`} {...stroke} />
        ))}
        {agent === "Codex" && <>
          <rect x={4} y={6} width={22} height={18} rx={4} {...stroke} />
          <polyline points="9,12 12.5,15 9,18" {...stroke} />
          <line x1={15} y1={18} x2={20} y2={18} {...stroke} />
        </>}
        {agent === "Cursor" && <polygon points="8,5 23,15 15.5,16.5 12,24" {...stroke} strokeLinejoin="round" />}
      </svg>
    </div>
  );
};

/** A clay card, as in the app. */
export const card = (radius = 22): React.CSSProperties => ({
  background: c.card, borderRadius: radius, border: `1px solid ${c.border}`,
  boxShadow: "0 18px 40px -18px rgba(60, 90, 70, 0.35), inset 1px 2px 3px rgba(255,255,255,0.9)",
});

/** A running leftover: a port, a simulator, a stack, build data. The amber dot pulses while it runs. */
export const Leftover: React.FC<{ label: string; detail: string; mono?: boolean; running?: boolean; width?: number }> =
  ({ label, detail, mono = false, running = true, width = 400 }) => {
    const f = useCurrentFrame();
    const pulse = 0.55 + 0.45 * Math.abs(Math.sin(f / 12));
    return (
      <div style={{ ...card(16), width, padding: "16px 20px", display: "flex", alignItems: "center", gap: 14 }}>
        <div style={{ width: 11, height: 11, borderRadius: 6, background: running ? c.amber : c.accentLight, opacity: running ? pulse : 1,
          boxShadow: running ? `0 0 10px ${c.amber}88` : "none" }} />
        <div style={{ fontFamily: mono ? theme.fonts.mono : theme.fonts.body, fontSize: 24, fontWeight: 500, color: c.ink }}>{label}</div>
        <div style={{ flex: 1 }} />
        <div style={{ fontFamily: theme.fonts.body, fontSize: 20, color: c.inkDim, fontVariantNumeric: "tabular-nums" }}>{detail}</div>
      </div>
    );
  };
