/**
 * screen-share-timer — auto-stop a browser screen share after a set time.
 *
 * A browser screen share is owned by the page that called `getDisplayMedia()`.
 * Stopping every track of that stream ends the capture for real: the browser's
 * "you are sharing your screen" bar disappears, and apps that listen for the
 * track's `ended` event (Meet, Discord, Slack, Whereby, ...) tear the share
 * down on their side too.
 *
 * Classic script on purpose — it has to load as a `<script src>`, as a
 * userscript, and as a bookmarklet. It defines `globalThis.ScreenShareTimer`.
 */
(function () {
  'use strict';

  var DEFAULTS = {
    limitMinutes: 15,
    warnSeconds: 60,
    showOverlay: true,
    onWarn: null,
    onEnd: null,
  };

  // stream -> { deadline, warnAt, warned, timeoutId, opts }
  var sessions = new Map();
  var tickId = null;
  var overlay = null; // { host, pill, label, extendBtn, stopBtn }
  var uninstallPatch = null;

  function now() {
    return Date.now();
  }

  function clamp(n, min) {
    return typeof n === 'number' && isFinite(n) && n > min ? n : min;
  }

  /** Stop every track of `stream` and forget its timer. `stop()` does not fire
   *  `ended` per spec, so cleanup happens here rather than in a listener. */
  function endShare(stream, reason) {
    var session = sessions.get(stream);
    forget(stream);
    stream.getTracks().forEach(function (track) {
      try {
        track.stop();
      } catch (err) {
        /* already gone */
      }
    });
    if (session && typeof session.opts.onEnd === 'function') {
      try {
        session.opts.onEnd(stream, reason);
      } catch (err) {
        console.error('[screen-share-timer] onEnd threw', err);
      }
    }
  }

  function forget(stream) {
    var session = sessions.get(stream);
    if (session && session.timeoutId != null) clearTimeout(session.timeoutId);
    sessions.delete(stream);
    if (sessions.size === 0) stopTicking();
    render();
  }

  /** Background tabs get their timers throttled, so the deadline is the source
   *  of truth and every wake-up re-checks it instead of trusting setTimeout. */
  function sweep() {
    var t = now();
    sessions.forEach(function (session, stream) {
      if (t >= session.deadline) {
        endShare(stream, 'timeout');
        return;
      }
      if (!session.warned && t >= session.warnAt) {
        session.warned = true;
        if (typeof session.opts.onWarn === 'function') {
          var secondsLeft = Math.round((session.deadline - t) / 1000);
          try {
            session.opts.onWarn(stream, secondsLeft);
          } catch (err) {
            console.error('[screen-share-timer] onWarn threw', err);
          }
        }
      }
    });
    render();
  }

  function startTicking() {
    if (tickId == null) tickId = setInterval(sweep, 250);
  }

  function stopTicking() {
    if (tickId != null) clearInterval(tickId);
    tickId = null;
  }

  function armTimeout(session, stream) {
    if (session.timeoutId != null) clearTimeout(session.timeoutId);
    session.timeoutId = setTimeout(
      function () {
        if (sessions.get(stream) === session) endShare(stream, 'timeout');
      },
      Math.max(0, session.deadline - now())
    );
  }

  /** Put a countdown on an existing display stream. Returns the stream. */
  function attach(stream, options) {
    if (!stream || typeof stream.getTracks !== 'function') {
      throw new TypeError('attach() needs a MediaStream');
    }
    var opts = Object.assign({}, DEFAULTS, options || {});
    var limitMs = clamp(opts.limitMinutes, 0) * 60 * 1000;
    if (limitMs <= 0) throw new RangeError('limitMinutes must be > 0');

    var warnMs = Math.min(clamp(opts.warnSeconds, 0) * 1000, limitMs);
    var deadline = now() + limitMs;
    var session = {
      deadline: deadline,
      warnAt: deadline - warnMs,
      warned: false,
      timeoutId: null,
      opts: opts,
    };
    sessions.set(stream, session);
    armTimeout(session, stream);

    // The user clicking the browser's own "Stop sharing" ends the tracks; drop
    // the timer so it cannot fire against a dead stream.
    stream.getTracks().forEach(function (track) {
      track.addEventListener('ended', function () {
        var live = stream.getTracks().some(function (t) {
          return t.readyState === 'live';
        });
        if (!live) forget(stream);
      });
    });

    startTicking();
    if (opts.showOverlay) ensureOverlay();
    render();
    return stream;
  }

  /** Wrap `getDisplayMedia` so every future share is timed. Returns uninstall. */
  function install(options) {
    var MD = globalThis.MediaDevices;
    var proto = MD && MD.prototype;
    if (!proto || typeof proto.getDisplayMedia !== 'function') {
      console.warn(
        '[screen-share-timer] getDisplayMedia is unavailable here ' +
          '(needs https or localhost, and a browser that supports screen capture).'
      );
      return function () {};
    }
    if (uninstallPatch) uninstallPatch();

    var original = proto.getDisplayMedia;
    proto.getDisplayMedia = function () {
      var args = arguments;
      var self = this;
      return Promise.resolve(original.apply(self, args)).then(function (stream) {
        try {
          attach(stream, options);
        } catch (err) {
          console.error('[screen-share-timer] could not start the timer', err);
        }
        return stream;
      });
    };

    uninstallPatch = function () {
      proto.getDisplayMedia = original;
      uninstallPatch = null;
    };
    document.addEventListener('visibilitychange', sweep);
    return function () {
      document.removeEventListener('visibilitychange', sweep);
      if (uninstallPatch) uninstallPatch();
    };
  }

  /** Push every running share's deadline back by `minutes`. */
  function extend(minutes) {
    var ms = clamp(minutes, 0) * 60 * 1000;
    if (ms <= 0) return;
    sessions.forEach(function (session, stream) {
      session.deadline += ms;
      session.warnAt += ms;
      session.warned = false;
      armTimeout(session, stream);
    });
    render();
  }

  function stopAll(reason) {
    Array.from(sessions.keys()).forEach(function (stream) {
      endShare(stream, reason || 'manual');
    });
  }

  function remaining() {
    var soonest = Infinity;
    sessions.forEach(function (session) {
      soonest = Math.min(soonest, session.deadline);
    });
    return soonest === Infinity ? null : Math.max(0, soonest - now());
  }

  // ---------------------------------------------------------------- overlay
  // Shadow DOM so the host page's CSS cannot restyle or hide the countdown.
  // Heads up: if you are sharing your whole screen or this tab, the overlay is
  // part of what viewers see. Pass `showOverlay: false` when that matters.

  function ensureOverlay() {
    if (overlay || typeof document === 'undefined' || !document.body) return;
    var host = document.createElement('div');
    host.setAttribute('data-screen-share-timer', '');
    host.style.cssText = 'all:initial;position:fixed;z-index:2147483647;';
    var root = host.attachShadow({ mode: 'closed' });
    root.innerHTML =
      '<style>' +
      '.pill{position:fixed;right:16px;bottom:16px;display:flex;gap:8px;align-items:center;' +
      'font:600 13px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#f4f4f5;' +
      'background:#18181bE6;border:1px solid #3f3f46;border-radius:999px;padding:8px 10px 8px 14px;' +
      'box-shadow:0 4px 16px #0006;-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px)}' +
      '.pill[data-warn="1"]{background:#7f1d1dF2;border-color:#ef4444;color:#fff}' +
      'button{font:600 12px/1 inherit;color:inherit;background:#ffffff1f;border:0;border-radius:999px;' +
      'padding:6px 9px;cursor:pointer}' +
      'button:hover{background:#ffffff33}' +
      '</style>' +
      '<div class="pill"><span part="label"></span>' +
      '<button data-act="extend">+5m</button><button data-act="stop">Stop</button></div>';
    var pill = root.querySelector('.pill');
    root.querySelector('[data-act="extend"]').addEventListener('click', function () {
      extend(5);
    });
    root.querySelector('[data-act="stop"]').addEventListener('click', function () {
      stopAll('manual');
    });
    document.body.appendChild(host);
    overlay = { host: host, pill: pill, label: root.querySelector('span') };
  }

  function format(ms) {
    var total = Math.ceil(ms / 1000);
    var m = Math.floor(total / 60);
    var s = total % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  function render() {
    if (!overlay) return;
    var left = remaining();
    if (left == null) {
      overlay.host.remove();
      overlay = null;
      return;
    }
    var warned = false;
    sessions.forEach(function (session) {
      if (session.warned) warned = true;
    });
    overlay.label.textContent = 'Screen share ends in ' + format(left);
    overlay.pill.setAttribute('data-warn', warned ? '1' : '0');
  }

  globalThis.ScreenShareTimer = {
    install: install,
    attach: attach,
    extend: extend,
    stopAll: stopAll,
    remaining: remaining,
    get active() {
      return sessions.size;
    },
  };
})();
