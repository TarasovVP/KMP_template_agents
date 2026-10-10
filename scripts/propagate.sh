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

echo "==> ios: shared.xcframework (keyed by revision of shared inputs)"
# Revision of everything that determines the XCFramework, by content only (independent of git state):
# sorted list of input files (tracked + untracked, not ignored), each as "<path> <git hash-object of the working file>", sha256 of the list.
# The same content gives the same revision before and after a commit.
REV_PATHS="shared/src shared/build.gradle.kts build.gradle.kts settings.gradle.kts gradle/libs.versions.toml"
shared_rev() {
  (
    cd "$SHARED" || exit 1
    # shellcheck disable=SC2086
    git ls-files -co --exclude-standard -- $REV_PATHS | sort -u | while IFS= read -r f; do
      [ -f "$f" ] && echo "$f $(git hash-object -- "$f")"
    done | shasum -a 256 | cut -d' ' -f1
  )
}
REV="$(shared_rev)" || { echo "cannot compute shared revision" >&2; exit 1; }
IOS_REPO="$ROOT/KMP_template_ios"
REV_FILE_REL="Packages/KMPTemplate/.shared-rev"
COMMITTED_REV="$(cd "$IOS_REPO" && git show "HEAD:$REV_FILE_REL" 2>/dev/null | tr -d '[:space:]')"
printf '%s\n' "$REV" > "$IOS_REPO/$REV_FILE_REL"
if [ -n "$COMMITTED_REV" ] && [ "$COMMITTED_REV" = "$REV" ]; then
  echo "shared inputs unchanged (rev ${REV:0:12}): restoring committed shared.xcframework"
  (cd "$IOS_REPO" && git checkout -- Packages/KMPTemplate/shared.xcframework) || exit 1
else
  echo "shared inputs changed (rev ${REV:0:12}, committed ${COMMITTED_REV:0:12}): copying fresh release XCFramework"
  [ -d "$XCF_SRC" ] || { echo "missing $XCF_SRC" >&2; exit 1; }
  rm -rf "$IOS_PKG/shared.xcframework"
  cp -R "$XCF_SRC" "$IOS_PKG/shared.xcframework" || exit 1
fi

echo "==> web: nothing to do (node_modules/KMP_template_shared-shared is a symlink)"

echo "==> contract fingerprint"
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
dirty=""
if [ -n "$(cd "$SHARED" && git status --porcelain | grep -v '^?? \.kotlin/')" ]; then dirty=" (dirty)"; fi
{
  echo "generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "shared HEAD: $(cd "$SHARED" && git rev-parse --short HEAD)$dirty"
  echo "shared rev: $REV"
  for slice in ios-arm64 ios-arm64_x86_64-simulator; do
    echo "shared.h $slice: $(sha "$IOS_PKG/shared.xcframework/$slice/shared.framework/Headers/shared.h")"
  done
  d_ts="$(ls "$JS_DIST"/*.d.ts 2>/dev/null | head -n1)"
  echo "$(basename "${d_ts:-missing.d.ts}"): $( [ -n "$d_ts" ] && sha "$d_ts" || echo MISSING )"
} > "$CONTRACT"
cat "$CONTRACT"
