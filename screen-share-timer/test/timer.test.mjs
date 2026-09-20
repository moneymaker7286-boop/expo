// Real-browser verification: drives the timer in Chromium against a stubbed
// getDisplayMedia (a canvas capture stream), because headless Chromium has no
// desktop to share. Run with: node test/timer.test.mjs
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

// Playwright may be installed locally or globally; resolve either.
const require_ = createRequire(import.meta.url);
function loadPlaywright() {
  try {
    return require_('playwright');
  } catch {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8' }).trim();
    return require_(join(globalRoot, 'playwright'));
  }
}
const { chromium } = loadPlaywright();

const here = dirname(fileURLToPath(import.meta.url));
const core = readFileSync(join(here, '..', 'screen-share-timer.js'), 'utf8');

// 127.0.0.1 is a secure context in Chromium, which getDisplayMedia requires.
const server = createServer((_req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<!doctype html><html><body></body></html>');
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/`;

const results = [];
function check(name, passed, detail) {
  results.push({ name, passed, detail });
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
}

const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', (msg) => {
  if (msg.type() === 'error') console.log(`  [page error] ${msg.text()}`);
});
await page.goto(url);

// Replace getDisplayMedia with a canvas stream before installing, so install()
// wraps the stub instead of the real (unusable) implementation.
await page.addInitScript(() => {
  window.__stubDisplayMedia = () => {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 64;
    canvas.getContext('2d').fillRect(0, 0, 64, 64);
    MediaDevices.prototype.getDisplayMedia = async () => canvas.captureStream(5);
  };
});
await page.reload();
await page.addScriptTag({ content: core });
await page.evaluate(() => window.__stubDisplayMedia());

// 1. The share ends on its own when the clock runs out.
const autoStop = await page.evaluate(async () => {
  const warnings = [];
  const ends = [];
  ScreenShareTimer.install({
    limitMinutes: 1.2 / 60, // 1.2s
    warnSeconds: 0.6,
    onWarn: (_s, left) => warnings.push(left),
    onEnd: (_s, reason) => ends.push(reason),
  });
  const stream = await navigator.mediaDevices.getDisplayMedia({ video: true });
  const stateWhileSharing = stream.getVideoTracks()[0].readyState;
  await new Promise((r) => setTimeout(r, 2000));
  return {
    stateWhileSharing,
    stateAfterDeadline: stream.getVideoTracks()[0].readyState,
    warnings,
    ends,
    active: ScreenShareTimer.active,
  };
});
check(
  'share is live while the timer runs',
  autoStop.stateWhileSharing === 'live',
  autoStop.stateWhileSharing
);
check(
  'share is stopped once the time is up',
  autoStop.stateAfterDeadline === 'ended',
  `readyState=${autoStop.stateAfterDeadline}`
);
check(
  'onWarn fired once before the end',
  autoStop.warnings.length === 1,
  JSON.stringify(autoStop.warnings)
);
check(
  'onEnd reported a timeout',
  autoStop.ends.length === 1 && autoStop.ends[0] === 'timeout',
  JSON.stringify(autoStop.ends)
);
check('no session is left behind', autoStop.active === 0, `active=${autoStop.active}`);

// 2. A user stopping the share from the browser's own bar clears the timer.
const manualStop = await page.evaluate(async () => {
  ScreenShareTimer.install({ limitMinutes: 5, warnSeconds: 0 });
  const stream = await navigator.mediaDevices.getDisplayMedia({ video: true });
  const activeBefore = ScreenShareTimer.active;
  const track = stream.getVideoTracks()[0];
  track.stop();
  track.dispatchEvent(new Event('ended')); // what the browser's Stop button does
  await new Promise((r) => setTimeout(r, 50));
  return {
    activeBefore,
    activeAfter: ScreenShareTimer.active,
    remaining: ScreenShareTimer.remaining(),
  };
});
check(
  'timer is armed for a new share',
  manualStop.activeBefore === 1,
  `active=${manualStop.activeBefore}`
);
check(
  'timer is dropped when the user stops the share',
  manualStop.activeAfter === 0 && manualStop.remaining === null,
  `active=${manualStop.activeAfter} remaining=${manualStop.remaining}`
);

// 3. extend() pushes the deadline out instead of letting the share die.
const extended = await page.evaluate(async () => {
  ScreenShareTimer.install({ limitMinutes: 1 / 60, warnSeconds: 0 }); // 1s
  const stream = await navigator.mediaDevices.getDisplayMedia({ video: true });
  ScreenShareTimer.extend(5);
  await new Promise((r) => setTimeout(r, 1500)); // past the original deadline
  const state = stream.getVideoTracks()[0].readyState;
  const remaining = ScreenShareTimer.remaining();
  ScreenShareTimer.stopAll();
  return { state, remaining };
});
check(
  'extend() keeps the share alive past the original deadline',
  extended.state === 'live' && extended.remaining > 4 * 60 * 1000,
  `readyState=${extended.state} remainingMs=${extended.remaining}`
);

// 4. The countdown overlay is present and counting while a share runs.
const overlay = await page.evaluate(async () => {
  ScreenShareTimer.install({ limitMinutes: 5, warnSeconds: 0, showOverlay: true });
  await navigator.mediaDevices.getDisplayMedia({ video: true });
  await new Promise((r) => setTimeout(r, 400));
  const host = document.querySelector('[data-screen-share-timer]');
  const mounted = !!host;
  ScreenShareTimer.stopAll();
  await new Promise((r) => setTimeout(r, 400));
  return { mounted, removedAfterStop: !document.querySelector('[data-screen-share-timer]') };
});
check('countdown overlay mounts during a share', overlay.mounted);
check('overlay is removed once the share ends', overlay.removedAfterStop);

await browser.close();
server.close();

const failed = results.filter((r) => !r.passed);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
