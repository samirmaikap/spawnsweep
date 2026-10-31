// 1 · Hook: the clay moon on night, then "Your agents finished. Their servers didn't."
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { BgNight, BlurWords, Grade, Moon, useBreathe } from "../components/kit";
import { theme } from "../theme";

export const HOOK_MOON = { x: 960, y: 372, size: 200 };

export const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f, fps, config: theme.spring.bouncy });
  const breathe = useBreathe();
  return (
    <AbsoluteFill>
      <BgNight />
      <AbsoluteFill style={{ alignItems: "center" }}>
        <div style={{ position: "absolute", top: HOOK_MOON.y - HOOK_MOON.size / 2, opacity: p,
          transform: `${breathe} scale(${interpolate(p, [0, 1], [0.55, 1])}) rotate(${interpolate(p, [0, 1], [-25, 0])}deg)` }}>
          <Moon size={HOOK_MOON.size} />
        </div>
        <div style={{ position: "absolute", top: 560, width: 1600, display: "flex", flexDirection: "column", gap: 18 }}>
          <BlurWords text="Your agents finished." delay={12} size={104} color={theme.colors.text} />
          <BlurWords text="Their servers didn't." delay={32} size={104} color={theme.colors.textDim} hero={["didn't."]} />
        </div>
      </AbsoluteFill>
      <Grade dark />
    </AbsoluteFill>
  );
};
