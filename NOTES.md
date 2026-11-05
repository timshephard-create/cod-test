# Range Day — notes

A small Godot 4.7.2 study of modern Call of Duty-style gunplay feel. One rifle, one
pistol, one course that starts on a shooting range and ends at the back of an urban
alley. Everything is original: geometry is built from primitives in code, every sound
is synthesised by `tools/gen_sfx.py`. No third-party names, maps, logos or assets.

Play: `docs/index.html` (web export, no-threads build, works on GitHub Pages without
cross-origin isolation headers). Add `?low` to the URL for weak GPUs.

## What is closest to CoD

- **ADS.** Timed zoom (rifle 240 ms, pistol 170 ms) with smoothstep easing, FOV
  80 -> 57.6 / 68.8, sensitivity scaled by the FOV ratio, iron sights that genuinely
  line up on the camera axis, sway and bob damped by ~80% while aimed, and a slow
  breathing drift on the aim itself (not just the view model) once fully aimed.
- **Recoil with recovery.** Per-weapon pattern tables (pitch/yaw per shot), small
  randomisation, an index that resets after a 300 ms pause, and camera recoil that
  springs to the pattern then recovers to centre once you stop firing. The visual
  kick (back, up, roll) is a separate sub-stepped spring on the view model so it
  reads as a snap, not a slide. Hip-fire bloom grows per shot and decays.
- **Hitmarkers.** The double-tick on every hit, a higher ring plus orange marker and
  a "HEADSHOT +25" pop on head hits, and a red thicker marker plus a thud on the
  killing hit. Targets flash and fall on a tweened hinge.
- **Weapon handling timing.** Sprint-to-fire delay (280 ms rifle / 160 ms pistol)
  with the gun lowered to a sprint pose; reload phases with mag-out, mag-in (ammo
  refills at 1.35 s, before the animation ends at 2.05 s, like CoD's reload-cancel
  window) and an extra bolt cycle on an empty reload; weapon swap lower/raise times;
  dry-fire click that auto-reloads; semi vs full-auto trigger logic with an RPM cap.
- **Course loop.** Practice range with respawning targets, E on the pad to start, a
  3-2-1 countdown, pop-ups triggered by zones as you move through the alley, a
  finish pad, and a results card with time bonus, accuracy bonus and a saved best.

## What is missing

- **Animation.** The view model is posed procedurally (offsets, tilts, springs).
  There are no hand-authored reload, sprint, inspect or raise animations, no hands,
  and no slide/bolt motion on the gun. This is the single biggest gap in "feel".
- **Movement set.** No slide, tactical sprint, mantle, lean, or dive. Crouch is a
  toggle with a camera lerp only.
- **Audio depth.** Shots are one synthesised layer plus a short tail; there is no
  distance-based tail, indoor/outdoor reverb, bullet whiz, or shell drops. The
  hitmarker tick is close; the gunshots are the furthest from reference.
- **Enemy feedback.** Targets are static silhouettes. No damage numbers, no
  staggers, no blood or dust puffs, no kill feed.
- **Camera.** No screen shake on fire, no ADS blur on the near gun, no FOV kick
  from sprint-start or landing, no weapon blockage against walls.
- **Attachments and tuning UI.** One fixed tuning per gun, no sensitivity menu.

## Three changes that close the gap most

1. **Authored first-person animation with hands.** Import a rigged arms+gun set
   (Blender, original), with reload, draw, sprint-in/out and fire clips, blended
   with the existing procedural sway/kick layer. Reload-cancel timing is already
   decoupled from the animation, so the clips just need to match the
   `mag_in_t` / `reload_time` numbers. This alone moves it from "study" to "game".
2. **Layered gunshot audio and impact FX.** Replace the single shot sample with a
   three-layer shot (transient, body, distance tail), add a per-surface impact
   sound and a small dust/spark particle, and add a 40 ms camera shake on fire.
   Reference-level feel is mostly sound; this is the cheapest large win.
3. **Movement feel: slide and tactical sprint, plus a sprint-out FOV kick.** Two
   movement states and a tiny camera FOV ramp when sprint starts (CoD's "lean into
   it"). Together with step-based footstep audio already in place, this fixes the
   traversal half of the alley section, which currently feels flat.

## Verification

- `godot --headless --path . -- --autotest` runs `tests/autotest.gd` through the
  real input pipeline at 120 fps and checks 40 behaviours: ADS half/full timing and
  FOV, spread, head vs body hit resolution, hitmarker kind, recoil kick and
  recovery, ~760 RPM burst count, reload refill at 1.35 s and completion at 2.05 s,
  sprint-to-fire block then fire, swap timing, semi-auto trigger, course countdown,
  scoring, zone pop-ups, finish, best score and restart. Result: 40/40.
- `tests/verify_web.js` drives the exported build in headless Chromium (Playwright,
  SwiftShader) with pointer lock, DOM `pointermove` deltas, mouse buttons and keys,
  and reads `window.__rangeday` (published every frame on web). It confirmed boot,
  WebGL2 compatibility renderer, pointer lock, look, ADS FOV, hits and kills with
  score, reload, sprint-to-fire, pistol semi-auto, Escape pause and click resume,
  with zero console errors. Software rendering runs at about 7 fps at 640x360 with
  `?low`, which is why physics is 60 Hz with a 16-step cap: game time stays wall
  time down to roughly 4 fps.

## Numbers (for tuning)

| | Rifle | Pistol |
|---|---|---|
| RPM | 760 auto | 430 semi |
| Damage body / head | 28 / 42 | 36 / 57.6 |
| ADS time / FOV scale | 0.24 s / 0.72 | 0.17 s / 0.86 |
| Hip / ADS spread (deg) | 2.4 / 0.12 | 1.8 / 0.10 |
| First-shot recoil (pitch, deg) | 1.05 | 2.1 |
| Recovery rate (1/s) | 5.5 | 11 |
| Reload mag-in / done / empty extra | 1.35 / 2.05 / +0.45 s | 0.95 / 1.55 / +0.30 s |
| Sprint-to-fire | 0.28 s | 0.16 s |
