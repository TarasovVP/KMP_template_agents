// Behavioural smoke for web: load the shared package the way app.js does and call it.
// Usage (via scripts/smoke/web-smoke.sh): node --preserve-symlinks scripts/smoke/web-smoke.mjs <web-dir> <browser|node>
// The package is a symlink into KMP_template_shared; --preserve-symlinks makes its dependencies
// (@js-joda/core, ...) resolve from the web project's node_modules (like preserveSymlinks in vite.config.js).
//
//   browser: a minimal navigator is stubbed, as in a page; getDeviceModel() must be "Browser".
//   node:    plain Node, no stub; getDeviceModel() must be "Node".
//
// (Before shared commit 1085402 the node variant failed: JsPlatformHelper read navigator.userAgent unconditionally.)
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [webDir, mode] = process.argv.slice(2);
if (!webDir || !['browser', 'node'].includes(mode)) { console.error('usage: web-smoke.mjs <web-dir> <browser|node>'); process.exit(2); }
const expected = mode === 'browser' ? 'Browser' : 'Node';

const firstLine = (e) => String(e && e.stack ? e.name + ': ' + e.message : e).split('\n')[0];
const fail = (msg) => { console.error(`SMOKE FAIL (web/${mode}): behaviour is broken, not the build: ${msg}`); process.exit(1); };

if (mode === 'browser' && typeof globalThis.navigator === 'undefined') {
  Object.defineProperty(globalThis, 'navigator', { value: { userAgent: 'web-smoke' }, configurable: true });
}

let shared;
try {
  const entry = createRequire(join(webDir, 'package.json')).resolve('KMP_template_shared-shared');
  shared = await import(pathToFileURL(entry).href);
} catch (e) {
  fail(`cannot load KMP_template_shared-shared: ${firstLine(e)}`);
}

const { getInfo, getDeviceModel } = shared;
if (typeof getInfo !== 'function' || typeof getDeviceModel !== 'function') {
  fail('getInfo/getDeviceModel are not exported by the package');
}
let info, model;
try { info = getInfo(); model = getDeviceModel(); } catch (e) { fail(firstLine(e)); }
console.log(`getInfo() = ${info}`);
console.log(`getDeviceModel() = ${model}`);
if (typeof info !== 'string' || !info.includes('Hello from KMP module')) fail(`getInfo() returned ${JSON.stringify(info)}`);
if (model !== expected) fail(`getDeviceModel() returned ${JSON.stringify(model)}, expected "${expected}"`);
console.log(`SMOKE OK (web/${mode})`);
