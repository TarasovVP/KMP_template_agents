// Behavioural smoke for web: load the shared package the way app.js does and call it.
// Usage: node --preserve-symlinks scripts/smoke/web-smoke.mjs <web-dir>
// The package is a symlink into KMP_template_shared; --preserve-symlinks makes its dependencies
// (@js-joda/core, ...) resolve from the web project's node_modules (like preserveSymlinks in vite.config.js).
//
// Known defect in shared (jsMain): SystemInfo() -> JsPlatformHelper reads navigator.userAgent unconditionally, so under
// Node < 21 even getDeviceModel() throws ReferenceError, and on Node >= 21 (navigator exists) it returns "Browser", never
// "Node". To exercise the code we provide a minimal browser-like navigator, as the page has, and expect "Browser".
// When shared is fixed to work without navigator, drop the stub and expect "Node".
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const webDir = process.argv[2];
if (!webDir) { console.error('usage: web-smoke.mjs <web-dir>'); process.exit(2); }

const fail = (msg) => { console.error(`SMOKE FAIL (web): behaviour is broken, not the build: ${msg}`); process.exit(1); };

if (typeof globalThis.navigator === 'undefined') {
  Object.defineProperty(globalThis, 'navigator', { value: { userAgent: 'web-smoke' }, configurable: true });
}

let shared;
try {
  const entry = createRequire(join(webDir, 'package.json')).resolve('KMP_template_shared-shared');
  shared = await import(pathToFileURL(entry).href);
} catch (e) {
  fail(`cannot load KMP_template_shared-shared: ${e && e.message}`);
}

const { getInfo, getDeviceModel } = shared;
if (typeof getInfo !== 'function' || typeof getDeviceModel !== 'function') {
  fail('getInfo/getDeviceModel are not exported by the package');
}
let info, model;
try { info = getInfo(); model = getDeviceModel(); } catch (e) { fail(`call threw: ${e && e.message}`); }
console.log(`getInfo() = ${info}`);
console.log(`getDeviceModel() = ${model}`);
if (typeof info !== 'string' || !info.includes('Hello from KMP module')) fail(`getInfo() returned ${JSON.stringify(info)}`);
if (model !== 'Browser') fail(`getDeviceModel() returned ${JSON.stringify(model)}, expected "Browser" (navigator is defined)`);
