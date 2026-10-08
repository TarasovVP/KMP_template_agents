#!/usr/bin/env bash
# Build shared artifacts, push them to the consumers and record the contract fingerprint.
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/KMP_template_shared"
IOS_PKG="$ROOT/KMP_template_ios/Packages/KMPTemplate"
XCF_SRC="$SHARED/shared/build/XCFrameworks/release/shared.xcframework"
JS_DIST="$SHARED/shared/build/dist/js/productionLibrary"
CONTRACT="$ROOT/logs/contract.txt"

mkdir -p "$ROOT/logs"

echo "==> shared: publish + XCFramework + JS library"
(cd "$SHARED" && ./gradlew --console=plain \
    :shared:publishToMavenLocal \
    :shared:assembleSharedReleaseXCFramework \
    :shared:jsBrowserProductionLibraryDistribution) || { echo "shared build failed" >&2; exit 1; }

echo "==> web: check JS dependencies declared by the shared distribution"
node -e '
const fs = require("fs");
const dist = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).dependencies || {};
const web = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).dependencies || {};
const problems = [];
for (const [name, ver] of Object.entries(dist)) {
  if (!(name in web)) problems.push(`  ${name}: missing in KMP_template_web/package.json, needs "${ver}"`);
  else if (web[name] !== ver) problems.push(`  ${name}: web has "${web[name]}", shared distribution needs "${ver}"`);
}
if (problems.length) {
  console.error("JS dependency mismatch between shared distribution and KMP_template_web:");
  console.error(problems.join("\n"));
  console.error("Fix KMP_template_web/package.json (then npm install) and re-run.");
  process.exit(1);
}
console.log("ok: " + Object.keys(dist).length + " JS dependencies match");
' "$JS_DIST/package.json" "$ROOT/KMP_template_web/package.json" || exit 1

echo "==> ios: replace shared.xcframework"
[ -d "$XCF_SRC" ] || { echo "missing $XCF_SRC" >&2; exit 1; }
rm -rf "$IOS_PKG/shared.xcframework"
cp -R "$XCF_SRC" "$IOS_PKG/shared.xcframework" || exit 1

echo "==> web: nothing to do (node_modules/KMP_template_shared-shared is a symlink)"

echo "==> contract fingerprint"
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
dirty=""
if [ -n "$(cd "$SHARED" && git status --porcelain | grep -v '^?? \.kotlin/')" ]; then dirty=" (dirty)"; fi
{
  echo "generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "shared HEAD: $(cd "$SHARED" && git rev-parse --short HEAD)$dirty"
  for slice in ios-arm64 ios-arm64_x86_64-simulator; do
    echo "shared.h $slice: $(sha "$IOS_PKG/shared.xcframework/$slice/shared.framework/Headers/shared.h")"
  done
  d_ts="$(ls "$JS_DIST"/*.d.ts 2>/dev/null | head -n1)"
  echo "$(basename "${d_ts:-missing.d.ts}"): $( [ -n "$d_ts" ] && sha "$d_ts" || echo MISSING )"
} > "$CONTRACT"
cat "$CONTRACT"
