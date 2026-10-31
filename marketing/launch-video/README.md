# SpawnSweep launch video

A 20-second launch film made in code with [Remotion](https://www.remotion.dev). The colors and moon come from the app's own theme.

```bash
npm install
npm run studio   # preview and scrub in the browser
npm run render   # out/spawnsweep-launch.mp4, 1920×1080 with sound
```

The soundtrack is synthesized by `scripts/sfx.mjs` (no downloads, nothing to license); both commands above make it first.
Scene timing is in `src/theme.ts` (`SCENES`, on a 100 BPM beat), the scenes are in `src/scenes`, and the shared pieces are in `src/components/kit.tsx`.

The README GIF is a half-size render without film grain, which GIFs can't compress:

```bash
npx remotion render src/index.ts Launch out/nograin.mp4 --scale 0.5 --muted --props='{"grain":false}'
ffmpeg -i out/nograin.mp4 -vf "fps=15,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" out/spawnsweep-launch.gif
```
