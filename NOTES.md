# Range Day — notes

A small Godot 4.7.2 study of modern Call of Duty-style gunplay feel. One rifle, one
pistol, one course that starts on a shooting range and ends at the back of an urban
alley. Everything is original: geometry is built from primitives in code, every sound
is synthesised by `tools/gen_sfx.py`. No third-party names, maps, logos or assets.

Play: `docs/index.html` (web export, no-threads build, works on GitHub Pages without
cross-origin isolation headers). Add `?low` to the URL for weak GPUs.

Pass 1 built the core feel (below). Pass 2 implemented the three changes pass 1 ranked
highest: movement (tactical sprint, slide, FOV kicks), layered audio with pooled impact
FX and fire shake, and authored first-person clips with IK hands. See "Pass 2".

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
- **Movement (pass 2).** Tactical sprint with the gun held high and a longer
  sprint-to-fire, slide with a fire lockout then fire-from-slide, and damped FOV
  kicks per state that the ADS FOV always wins over.
- **Audio and FX (pass 2).** Three-layer shots with cycled variants, surface-keyed
  impacts and particle bursts, decals, tracers, flash flicker, shell ticks, and a
  per-weapon fire shake separate from recoil.
- **Hands and clips (pass 2).** IK arms on every pose, and reload / swap / fire /
  ADS clips whose lengths are the gameplay timers.

## Pass 2

### Step 1 - tactical sprint, slide, FOV kick (`scripts/movement.gd`)

- Tactical sprint: Shift again while sprinting, or a second tap inside 0.28 s.
  8.6 m/s (sprint 7.4, walk 5.0), gun raised to `tac_pos` / `tac_rot`, +8 deg FOV,
  6 s duration then 1.5 s re-arm. Ends on fire, ADS or reload. Sprint-to-fire from
  tac is 0.42 s rifle / 0.26 s pistol (regular 0.28 / 0.16).
- Slide: Crouch while sprinting (needs 0.15 s of sprint). 0.8 s committed burst from
  9.2 m/s down to 2.4 m/s on a smoothstep friction curve, camera dips 0.14 m and
  rolls 0.065 rad on a sine, +3 deg FOV that fades over the slide, 150 ms fire
  lockout then fire from slide with +1.6 deg spread, 1.0 s cooldown, Space cancels
  into a jump, ends crouched.
- FOV kick: +4 sprint, +8 tac, +3 slide, damped at 9/s, and the camera FOV is
  `lerp(base + kick, base * ads_fov, ads)` so ADS always overrides it.
- Found while testing: holding fire while still holding Shift used to re-engage
  sprint every tick and reset the sprint-to-fire timer; sprint is now suppressed
  whenever the trigger is held.

### Step 2 - layered gunshots, pooled FX, fire shake (`tools/gen_sfx.py`, `scripts/fx.gd`)

- Shots: crack (4 variants) + body (4) + tail (3) per weapon, cycled so every variant
  plays before a repeat and never twice running. The sidearm tail is a short, dark
  "suppressed" thup with no flutter. Shell-casing tick 0.22 s (rifle) / 0.16 s
  (pistol) after each shot from a fixed ring buffer. Per-surface impacts: concrete,
  metal (targets, dumpsters, dividers, AC units), wood (benches, crates), 3 variants.
- FX pools, all allocated once: 64 decal quads with a generated 32x32 splotch
  texture (alpha scissor, oldest overwritten), 6 GPUParticles3D bursts per surface
  (sparks / dust / chips), 4 tracer meshes (every 3rd shot, 70 ms), a muzzle flash
  quad with a generated 64x64 star texture (additive, random size and roll) and an
  omni light that starts at 2.2-3.8 and decays at 55/s. The ray query object is
  reused; nothing in the firing path allocates.
- Fire shake: rifle 0.22 deg per shot decaying at 14/s at 38 Hz, pistol 0.35 deg at
  18/s and 42 Hz, capped at 3x amplitude + 0.5; a 0.25 deg kick when a target drops.
  Applied on the recoil pivot alongside, not inside, the recoil pattern.
- Web budget: cap 44,040,192 bytes (42 MiB) for `docs/`, checked by
  `tests/verify_web.js`. Pass-1 export 40,231,939 bytes; pass-2 export
  40,391,991 bytes (+160 KB for 48 WAVs at 1.2 MB on disk, packed smaller).
- Frame time at 640x360 `?low` under SwiftShader in headless Chromium (noisy, +-20%
  run to run, no GPU): pass-1 baseline idle 4.9 / firing 3.7 fps; pass-2 idle 3.4-4.2 /
  firing 3.3-4.0 fps. The gate is 2.8 fps while firing (75% of baseline).

### Step 3 - authored clips and IK hands (`scripts/anims.gd`, `scripts/hands.gd`)

- Rig: per side a capsule upper arm (0.46 m), capsule forearm (0.46 m) and a box
  hand, under the sway pivot, solved each frame with analytic two-bone IK to
  `GripR` / `GripL` nodes inside the current weapon model. Shoulders at
  (+-0.20, -0.27, 0.16) in camera space with poles down and out.
- Node layering: Kick (sub-stepped spring) -> Loco_<id> (loco player) ->
  AnimPose_<id> (action player) -> Model_<id>. Loco clips write Loco and the
  `Grip*Base` nodes; action clips write AnimPose, Mag, Bolt and the inner grips, so
  they add and never replace the spring.
- Clips built from the tables: `reload` (length = reload_time, mag out from
  mag_out_t, in at mag_in_t), `reload_empty` (+ empty_extra, bolt or slide racked at
  reload_time + 0.22), `lower` / `raise` (= lower_time / raise_time, with rest keys so
  a cancelled reload snaps clean), `fire` (0.12 s off-hand kick), `ads_in` /
  `ads_out` (= ads_time, hands settle on the grip), and loops `idle` (4 s), `walk`
  (1/1.9 s), `sprint` (1/2.8 s), `tac` (1/3.3 s), `slide` (0.8 s) with hand offsets
  that lag the gun a quarter cycle. No gameplay timer changed.
- The pass-1 procedural reload tilt and swap lower are gone; the autotest shows the
  clip position tracking `reload_t` within 40 ms and the view model on screen in
  every state for both weapons.

### Verification

- `godot --headless --path . -- --autotest`: 126/126 (pass 1: 40). Adds sprint and
  tac speeds, double-tap window in and out, tac sprint-to-fire, slide start / lockout
  / spread / duration / cooldown / jump cancel, FOV per state and restore, variant
  cycling, shake decay, FX and scene node counts unchanged over 500 shots, decal cap,
  tracer cadence, clip lengths and key times per weapon and phase, reload clip sync,
  bolt travel, lower / raise timing, loop selection, on-screen projection per state.
- `tests/verify_web.js`: boot, pointer lock, look, ADS, hits and score, reload,
  sprint-to-fire, semi-auto, pause and resume, zero console errors, size cap, fps
  floor. Result: WEB CHECK PASS on the final export, 0 console errors (so
  GPUParticles3D and the generated textures run on the WebGL2 compatibility renderer).

## Next three highest-value changes

1. **Target reactions and a kill feed.** Targets that stagger on body hits, snap back
   on headshots, and show floating damage numbers, plus a short kill feed and a
   per-target "time to down" readout. Everything the hitmarker started, finished.
2. **Weapon blockage, ADS depth of field and landing shake.** Lower the gun when the
   muzzle is inside a wall (a short forward ray), blur the near view model while
   aimed (a cheap two-plane fade works on compatibility), and add a landing camera
   dip and FOV bump after jumps and slide-jumps. These are the camera-side cues
   still missing between this and the reference.
3. **Settings and a second course.** Sensitivity, ADS sensitivity multiplier and FOV
   in a small menu saved to user://, and a second course that mixes a window
   sequence with a longer alley, so the movement set from pass 2 has somewhere to
   matter. Attachments can wait until the base loop has a reason to replay.

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
| Sprint-to-fire / from tac sprint | 0.28 / 0.42 s | 0.16 / 0.26 s |
| Fire shake amp / decay / freq | 0.22 deg / 14 / 38 Hz | 0.35 deg / 18 / 42 Hz |
| Shell tick delay | 0.22 s | 0.16 s |

| Movement | |
|---|---|
| Walk / sprint / tac sprint | 5.0 / 7.4 / 8.6 m/s |
| Double-tap window, tac duration, re-arm | 0.28 s, 6 s, 1.5 s |
| Slide speed start / end, duration, cooldown | 9.2 / 2.4 m/s, 0.8 s, 1.0 s |
| Slide fire lock / extra spread | 0.15 s / +1.6 deg |
| FOV kick sprint / tac / slide, damping | +4 / +8 / +3 deg, 9/s |
