const { chromium } = require('playwright');
const SHOTS = process.env.SHOTS || '.';
const W = parseInt(process.env.W || '640'), H = parseInt(process.env.H || '360');
const LOW = process.env.LOW === '0' ? '' : '?low';
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
  await page.goto('http://127.0.0.1:8765/index.html' + LOW, { waitUntil: 'load' });
  const state = () => page.evaluate(() => window.__rangeday || null);
  const look = async (dx, dy, n) => {
    for (let i = 0; i < n; i++) {
      await page.evaluate(([mx, my]) => {
        const c = document.getElementById('canvas') || document.querySelector('canvas');
        c.dispatchEvent(new PointerEvent('pointermove', { movementX: mx, movementY: my, clientX: 320, clientY: 180, bubbles: true, pointerType: 'mouse', pressure: 0 }));
      }, [dx, dy]);
      await page.waitForTimeout(40);
    }
    await page.waitForTimeout(300);
  };
  let s = null;
  for (let i = 0; i < 120 && !s; i++) { await page.waitForTimeout(500); s = await state(); }
  console.log('boot:', JSON.stringify({ state: s && s.state, targets_up: s && s.targets_up, weapon: s && s.weapon, mag: s && s.mag }));
  if (!s) { console.log(logs.join('\n')); await browser.close(); process.exit(1); }
  await page.screenshot({ path: `${SHOTS}/01_boot.png` });
  await page.mouse.click(W / 2, H / 2);
  await page.waitForTimeout(800);
  s = await state();
  console.log('after click:', JSON.stringify({ look: s.look, captured: s.captured, paused: s.paused, fps: s.fps }));
  await page.keyboard.press('KeyE');
  await page.waitForTimeout(400);
  s = await state();
  console.log('course after E:', JSON.stringify({ state: s.state }));
  // Mouse look: 20 x 6px right -> yaw -= 120 * 0.0021 = -0.252 rad.
  await look(6, 0, 20);
  s = await state();
  console.log('after look right:', JSON.stringify({ yaw: s.yaw, pitch: s.pitch }));
  await look(-6, 0, 20);
  await look(0, 3, 15);  // pitch down ~45px -> ~ -0.095 rad: body of the near centre target.
  s = await state();
  console.log('aimed at near target:', JSON.stringify({ yaw: s.yaw, pitch: s.pitch, state: s.state }));
  await page.screenshot({ path: `${SHOTS}/02_hip.png` });
  await page.mouse.down({ button: 'right' });
  await page.waitForTimeout(600);
  s = await state();
  console.log('ADS:', JSON.stringify({ ads: s.ads, fov: s.fov, spread: s.spread }));
  await page.screenshot({ path: `${SHOTS}/03_ads.png` });
  await page.mouse.down({ button: 'left' });
  await page.waitForTimeout(350);
  await page.screenshot({ path: `${SHOTS}/04_burst.png` });
  s = await state();
  console.log('mid burst:', JSON.stringify({ shots: s.shots, hits: s.hits, mag: s.mag, recoil: s.recoil }));
  await page.mouse.up({ button: 'left' });
  await page.waitForTimeout(1000);
  s = await state();
  console.log('after burst:', JSON.stringify({ shots: s.shots, hits: s.hits, headshots: s.headshots, kills: s.kills, score: s.score, mag: s.mag, recoil: s.recoil, targets_up: s.targets_up }));
  await page.mouse.up({ button: 'right' });
  await page.waitForTimeout(400);
  await page.keyboard.press('KeyR');
  await page.waitForTimeout(700);
  s = await state();
  console.log('reloading (0.7s):', JSON.stringify({ reloading: s.reloading, mag: s.mag }));
  await page.waitForTimeout(1900);
  s = await state();
  console.log('reloaded (2.6s):', JSON.stringify({ reloading: s.reloading, mag: s.mag, reserve: s.reserve }));
  await page.keyboard.down('ShiftLeft'); await page.keyboard.down('KeyW');
  await page.waitForTimeout(700);
  s = await state();
  console.log('sprinting:', JSON.stringify({ sprinting: s.sprinting, pos: s.pos, fov: s.fov }));
  await page.screenshot({ path: `${SHOTS}/05_sprint.png` });
  const before = s.shots;
  await page.mouse.down({ button: 'left' });
  await page.waitForTimeout(120);
  s = await state();
  console.log('120ms after trigger from sprint:', JSON.stringify({ shots: s.shots - before, sprint_out: s.sprint_out, sprinting: s.sprinting }));
  await page.waitForTimeout(600);
  s = await state();
  console.log('720ms after trigger:', JSON.stringify({ shots: s.shots - before }));
  await page.mouse.up({ button: 'left' });
  await page.keyboard.up('KeyW'); await page.keyboard.up('ShiftLeft');
  await page.keyboard.press('Digit2');
  await page.waitForTimeout(900);
  s = await state();
  const pb = s.shots;
  await page.mouse.down({ button: 'left' });
  await page.waitForTimeout(500);
  await page.mouse.up({ button: 'left' });
  s = await state();
  console.log('pistol hold:', JSON.stringify({ weapon: s.weapon, shots_fired: s.shots - pb, mag: s.mag }));
  for (let i = 0; i < 4; i++) { await page.mouse.down({ button: 'left' }); await page.waitForTimeout(60); await page.mouse.up({ button: 'left' }); await page.waitForTimeout(200); }
  await page.waitForTimeout(300);
  s = await state();
  console.log('pistol taps:', JSON.stringify({ shots_fired: s.shots - pb, mag: s.mag, time: s.time, state: s.state, score: s.score }));
  await page.screenshot({ path: `${SHOTS}/06_pistol.png` });
  // Escape releases pointer lock -> game pauses; click resumes.
  await page.keyboard.press('Escape');
  await page.waitForTimeout(600);
  s = await state();
  console.log('after Escape:', JSON.stringify({ captured: s.captured, paused: s.paused }));
  await page.screenshot({ path: `${SHOTS}/07_paused.png` });
  await page.mouse.click(W / 2, H / 2);
  await page.waitForTimeout(600);
  s = await state();
  console.log('after resume click:', JSON.stringify({ captured: s.captured, paused: s.paused, state: s.state }));
  const errs = logs.filter(l => !l.startsWith('[log]'));
  console.log('console non-log lines:', errs.length, errs.slice(0, 10).join(' | '));
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
