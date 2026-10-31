// 5 · End card: the moon, the name, the promise, and where to get it.
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { BgNight, BlurWords, Grade, Moon, Rise, useBreathe } from "../components/kit";
import { theme } from "../theme";

const c = theme.colors;

export const End: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - 4, fps, config: theme.spring.bouncy });
  const breathe = useBreathe();
  return (
    <AbsoluteFill>
      <BgNight />
      <AbsoluteFill style={{ alignItems: "center" }}>
        <div style={{ position: "absolute", top: 150, opacity: p, transform: `${breathe} scale(${interpolate(p, [0, 1], [0.6, 1])})` }}>
          <Moon size={170} />
        </div>
        <Rise delay={12} style={{ position: "absolute", top: 360 }}>
          <div style={{ fontFamily: theme.fonts.display, fontSize: 46, fontWeight: 600, color: c.textDim, letterSpacing: "0.01em" }}>SpawnSweep</div>
        </Rise>
        <div style={{ position: "absolute", top: 450, width: 1600, display: "flex", flexDirection: "column", gap: 8 }}>
          <BlurWords text="Lights out for what" delay={22} size={92} color={c.text} hero={["Lights", "out"]} />
          <BlurWords text="your agents left running." delay={34} size={92} color={c.text} />
        </div>
        <Rise delay={62} style={{ position: "absolute", top: 760, display: "flex", alignItems: "center", gap: 22 }}>
          <div style={{ fontFamily: theme.fonts.body, fontSize: 26, fontWeight: 600, color: c.text, padding: "12px 22px", borderRadius: 14,
            background: c.nightAlt, boxShadow: "inset 1px 2px 3px rgba(255,255,255,0.08), 0 8px 20px rgba(0,0,0,0.35)" }}>Free for macOS</div>
          <div style={{ fontFamily: theme.fonts.mono, fontSize: 28, fontWeight: 500, color: c.textDim }}>github.com/samirmaikap/spawnsweep</div>
        </Rise>
      </AbsoluteFill>
      <Grade dark />
    </AbsoluteFill>
  );
};
