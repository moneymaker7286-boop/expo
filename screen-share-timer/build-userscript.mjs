// Generates dist/screen-share-timer.user.js and dist/bookmarklet.txt from the
// single source of truth (screen-share-timer.js), so there is no hand-kept copy.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const core = readFileSync(join(here, 'screen-share-timer.js'), 'utf8');

// Edit these to change the shipped defaults of the userscript/bookmarklet.
const LIMIT_MINUTES = 15;
const WARN_SECONDS = 60;
const config = `{ limitMinutes: ${LIMIT_MINUTES}, warnSeconds: ${WARN_SECONDS}, showOverlay: true }`;

const header = `// ==UserScript==
// @name         Screen share timer
// @namespace    screen-share-timer
// @version      1.0.0
// @description  Automatically stop a browser screen share after a set time.
// @match        *://*/*
// @run-at       document-start
// @grant        none
// ==/UserScript==
`;

mkdirSync(join(here, 'dist'), { recursive: true });

writeFileSync(
  join(here, 'dist', 'screen-share-timer.user.js'),
  `${header}\n${core}\nScreenShareTimer.install(${config});\n`
);

// Bookmarklet: same code, URL-encoded, wrapped so it evaluates to undefined and
// does not navigate the page away.
const bookmarklet = `javascript:${encodeURIComponent(
  `(function(){${core}\nScreenShareTimer.install(${config});\n})();void 0;`
)}`;
writeFileSync(join(here, 'dist', 'bookmarklet.txt'), `${bookmarklet}\n`);

console.log(
  `built dist/screen-share-timer.user.js and dist/bookmarklet.txt ` +
    `(${LIMIT_MINUTES} min limit, ${WARN_SECONDS}s warning, bookmarklet ${bookmarklet.length} chars)`
);
