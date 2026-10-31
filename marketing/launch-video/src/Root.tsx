import React from "react";
import { AbsoluteFill, Audio, Composition, Sequence, staticFile } from "remotion";
import { Grain, Vignette, Wipe } from "./components/kit";
import { Clean, CLEAN_MOON } from "./scenes/Clean";
import { End } from "./scenes/End";
import { Hook, HOOK_MOON } from "./scenes/Hook";
import { Problem } from "./scenes/Problem";
import { Turn } from "./scenes/Turn";
import { FPS, SCENES, TOTAL, theme } from "./theme";

const S = SCENES;

/** Every hit lands 2–3 frames before its visual, which reads as in sync. */
const hits: [number, string, number][] = [
  [0, "pop", 0.45], [10, "whoosh", 0.25], [30, "whoosh", 0.25],
  [S.problem.from - 16, "whoosh", 0.45], [S.problem.from, "thump", 0.6],
  ...[0, 1, 2, 3, 4, 5].map((i): [number, string, number] => [S.problem.from + 24 + i * 9 + 10, "tick", 0.3]),
  [S.problem.from + 96, "pop", 0.35],
  [S.turn.from - 4, "whoosh", 0.35],
  ...[0, 1, 2, 3, 4, 5].map((i): [number, string, number] => [S.turn.from + 26 + i * 5, "tick", 0.25]),
  [S.clean.from - 4, "whoosh", 0.35], [S.clean.from + 41, "click", 0.5],
  ...[0, 1, 2, 3, 4, 5].map((i): [number, string, number] => [S.clean.from + 48 + i * 5 + 14, "pop", 0.3]),
  [S.clean.from + 64, "tick", 0.3], [S.clean.from + 69, "tick", 0.3], [S.clean.from + 74, "tick", 0.3],
  [S.end.from - 16, "whoosh", 0.45], [S.end.from, "thump", 0.6], [S.end.from + 20, "shimmer", 0.35],
];

/** `grain: false` is for the README GIF: grain changes every pixel every frame, which GIF compression can't handle. */
export const Launch: React.FC<{ grain?: boolean }> = ({ grain = true }) => (
  <AbsoluteFill style={{ background: theme.colors.night }}>
    <Sequence from={S.hook.from} durationInFrames={S.hook.len}><Hook /></Sequence>
    <Sequence from={S.problem.from} durationInFrames={S.problem.len}><Problem /></Sequence>
    <Sequence from={S.turn.from} durationInFrames={S.turn.len}><Turn /></Sequence>
    <Sequence from={S.clean.from} durationInFrames={S.clean.len}><Clean /></Sequence>
    <Sequence from={S.end.from} durationInFrames={S.end.len}><End /></Sequence>

    {/* Night to canvas out of the hook's moon; canvas back to night out of the clean-up moon. */}
    <Sequence from={S.problem.from - 12} durationInFrames={14}>
      <Wipe color={theme.colors.canvas} x={HOOK_MOON.x} y={HOOK_MOON.y} />
    </Sequence>
    <Sequence from={S.end.from - 12} durationInFrames={14}>
      <Wipe color={theme.colors.night} x={CLEAN_MOON.x} y={CLEAN_MOON.y} />
    </Sequence>

    {grain && <Grain />}
    <Vignette />

    <Audio src={staticFile("sfx/music.wav")} volume={0.5} />
    {hits.map(([at, name, volume], i) => (
      <Sequence key={i} from={Math.max(0, at)} durationInFrames={FPS * 3}>
        <Audio src={staticFile(`sfx/${name}.wav`)} volume={Math.min(1, volume * 1.4)} />
      </Sequence>
    ))}
  </AbsoluteFill>
);

export const RemotionRoot: React.FC = () => (
  <Composition id="Launch" component={Launch} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} defaultProps={{ grain: true }} />
);
