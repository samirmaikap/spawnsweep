// theme.ts: the single source of truth for the SpawnSweep launch video.
// Colors come from the app's own Theme.swift. Never inline a color, easing or spring in a scene.
import { Easing } from "remotion";
import { loadFont as loadDisplay } from "@remotion/google-fonts/InterTight";
import { loadFont as loadBody } from "@remotion/google-fonts/Inter";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";

const display = loadDisplay("normal", { weights: ["500", "600", "700"], subsets: ["latin"] });
const body = loadBody("normal", { weights: ["400", "500", "600"], subsets: ["latin"] });
const mono = loadMono("normal", { weights: ["500"], subsets: ["latin"] });

export const FPS = 30;
export const BPM = 100;
/** Frames per beat. Scene cuts land on multiples of it. */
export const BEAT = (FPS * 60) / BPM; // 18

/** Scene starts and lengths, in frames, all on the beat. */
export const SCENES = {
  hook: { from: 0, len: BEAT * 5 }, // 0–90
  problem: { from: BEAT * 5, len: BEAT * 9 }, // 90–252
  turn: { from: BEAT * 14, len: BEAT * 6 }, // 252–360
  clean: { from: BEAT * 20, len: BEAT * 7 }, // 360–486
  end: { from: BEAT * 27, len: BEAT * 6 }, // 486–594
} as const;
export const TOTAL = BEAT * 33; // 594 frames, 19.8s

export const theme = {
  colors: {
    night: "#16211B",
    nightAlt: "#22332A",
    canvas: "#EEF3EA",
    canvasAlt: "#E2EBDC",
    ink: "#22352A",
    inkDim: "#6E7D72",
    text: "#E8F0EA",
    textDim: "#9FB2A5",
    hero: "#A8D3B4", // the one highlighted word or glow per frame
    accent: "#527D61",
    accentLight: "#6A9A79",
    card: "#FFFFFF",
    border: "#DCE4D7",
    amber: "#C47F2E",
    amberFill: "#F6E8D9",
    grid: "rgba(34, 53, 42, 0.05)",
    glow: "rgba(168, 211, 180, 0.45)",
    moon: ["#F7FAEC", "#D3E2BE", "#9DBB88", "#5F8A66"],
    crater: ["#E3EBD9", "#C4D5BA"],
  },
  fonts: {
    display: display.fontFamily,
    body: body.fontFamily,
    mono: mono.fontFamily,
  },
  ease: {
    out: Easing.bezier(0.16, 1, 0.3, 1),
    inOut: Easing.bezier(0.83, 0, 0.17, 1),
    in: Easing.bezier(0.7, 0, 0.84, 0),
  },
  spring: {
    snappy: { damping: 14, stiffness: 160, mass: 0.6 },
    smooth: { damping: 20, stiffness: 90, mass: 1 },
    bouncy: { damping: 11, stiffness: 170, mass: 0.7 },
    count: { damping: 30, stiffness: 60, mass: 1 },
    fastCount: { damping: 26, stiffness: 120, mass: 1 },
  },
} as const;

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
