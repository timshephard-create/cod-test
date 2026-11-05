# Range Day

A tiny first-person gunplay-feel study in Godot 4.7.2: one rifle, one pistol, one
timed course from a shooting range into an urban alley. Original throughout; all
audio is procedurally generated.

![hip](screenshots/hip.png)
![ads](screenshots/ads.png)
![reload](screenshots/reload.png)

## Play

- Web build: `docs/` (deployed by `.github/workflows/pages.yml` to GitHub Pages on
  pushes to `main`; enable Pages with source "GitHub Actions" in the repo settings).
- Add `?low` to the URL to disable shadows and MSAA on weak GPUs.
- Controls: WASD move, Shift sprint, Shift again (or double-tap) tactical sprint,
  C while sprinting to slide (Space cancels into a jump), RMB aim, LMB fire,
  R reload, 1/2/Q or wheel to swap, C crouch, Space jump, E start the course on
  the white pad, Enter restart, Esc release the mouse.

## Build

```bash
python3 tools/gen_sfx.py                              # regenerate assets/sfx/*.wav
godot --headless --path . --import
godot --headless --path . --export-release "Web" docs/index.html
```

## Test

```bash
godot --headless --path . -- --autotest                # 126 gameplay/timing/animation checks
python3 -m http.server 8765 --directory docs &          # then:
SHOTS=/tmp/shots node tests/verify_web.js               # headless Chromium (Playwright): input, FX, size cap, fps floor
```

Tuning lives in three tables: `scripts/weapons.gd` (per-weapon gunplay, rig anchors,
audio/shake), `scripts/movement.gd` (speeds, tactical sprint, slide, FOV kicks) and
`scripts/anims.gd` (clip shapes; lengths come from the weapon tables).

See `NOTES.md` for what is closest to the reference feel, what each pass changed, and
the next three changes that would close the gap most.
