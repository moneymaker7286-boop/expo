# screen-share-timer

Automatically stops a browser screen share after a set time.

A browser screen share belongs to the page that called `getDisplayMedia()`. Stopping every track of
that stream really does end the capture: the browser's "you are sharing your screen" bar goes away,
and apps that listen for the track's `ended` event (Meet, Discord, Slack, Whereby, and so on) tear
the share down on their side too.

## Pick the way you need it

### 1. Your own page

```html
<script src="./screen-share-timer.js"></script>
<script>
  ScreenShareTimer.install({
    limitMinutes: 15,
    warnSeconds: 60,
    onWarn: (stream, secondsLeft) => console.log(`${secondsLeft}s left`),
    onEnd: (stream, reason) => console.log(`stopped: ${reason}`), // 'timeout' | 'manual'
  });

  // Every getDisplayMedia() call from now on is timed.
  const stream = await navigator.mediaDevices.getDisplayMedia({ video: true });
</script>
```

Open `demo.html` over `https://` or `http://localhost` to try it — enter a limit, start a share, and
watch it cut off. (`getDisplayMedia` is blocked on plain `http://` on any other host.)

### 2. Someone else's page (Meet, Discord, Slack, Zoom web)

You don't need their source. Both of these patch `getDisplayMedia` in the page before you start
sharing:

- **Userscript** — install `dist/screen-share-timer.user.js` in Tampermonkey or Violentmonkey. It
  runs at `document-start` on every site, so the patch is in place before the page asks for your
  screen.
- **Bookmarklet** — make a new bookmark and paste the contents of `dist/bookmarklet.txt` as its URL.
  Click it on the meeting page **before** you press that site's share button.

Change the shipped limit at the top of `build-userscript.mjs` and run `node build-userscript.mjs` to
regenerate both.

## API

| Call                      | Does                                                                 |
| ------------------------- | -------------------------------------------------------------------- |
| `install(options)`        | Times every future `getDisplayMedia()` call. Returns an uninstaller. |
| `attach(stream, options)` | Times a share you already started.                                   |
| `extend(minutes)`         | Pushes every running deadline back.                                  |
| `stopAll()`               | Ends every timed share now.                                          |
| `remaining()`             | Milliseconds until the soonest stop, or `null`.                      |
| `active`                  | How many shares are being timed.                                     |

Options: `limitMinutes` (default `15`), `warnSeconds` (default `60`), `showOverlay` (default
`true`), `onWarn`, `onEnd`.

## Things worth knowing

- **The countdown overlay is part of your share.** If you are sharing your whole screen or the tab
  it lives in, viewers see it. Pass `showOverlay: false` if that is a problem.
- **Background tabs throttle timers.** The deadline is a timestamp, not a countdown, and it is
  re-checked on every tick and on `visibilitychange`, so a backgrounded tab still stops on time
  rather than drifting.
- **Only shares started after `install()` are timed.** The bookmarklet has to be clicked before you
  press share; the userscript avoids this by running at `document-start`.
- **You can always stop early.** The browser's own "Stop sharing" button clears the timer, and so
  does the overlay's Stop button.

## Tests

```
node test/timer.test.mjs
```

Drives the timer in real Chromium via Playwright against a stubbed `getDisplayMedia` (headless
Chromium has no desktop to share), checking that the share is stopped at the deadline, that the
timer is dropped when you stop early, that `extend()` works, and that the overlay mounts and
unmounts. Needs `playwright` installed locally or globally.
