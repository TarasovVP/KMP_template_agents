#!/usr/bin/env bash
# End-to-end check that a change in shared/commonMain reaches every consumer, and that reverting it removes it again.
# Usage: scripts/check-propagation.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/KMP_template_shared"
SRC_REL="shared/src/commonMain/kotlin/com/tarasovvp/kmptemplate/SystemInfo.kt"
ANCHOR="Hello from KMP module!"
MARKER="PROP_$(date +%Y%m%d%H%M%S)"
LOGDIR="$ROOT/logs/$(date +%Y%m%d-%H%M%S)-propagation"
IOS_DD=/tmp/kmp-ios-dd
mkdir -p "$LOGDIR"

APK="$ROOT/KMP_template_android/app/build/outputs/apk/debug/app-debug.apk"
IOS_APP="$IOS_DD/Build/Products/Debug-iphonesimulator/KMP_template_ios.app"
WEB_DIST="$ROOT/KMP_template_web/dist"
SMOKE_OUT="$LOGDIR/desktop-smoke.out"

shared_dirty() { (cd "$SHARED" && git status --porcelain | grep -v '^?? \.kotlin/'); }

revert_shared() { (cd "$SHARED" && git checkout -- "$SRC_REL"); }

# Always restore shared; fail if the tree is not clean afterwards.
cleanup() {
  local rc=$?
  revert_shared
  if [ -n "$(shared_dirty)" ]; then
    echo "ERROR: shared working tree is not clean after the run:" >&2
    shared_dirty >&2
    exit 1
  fi
  exit "$rc"
}
trap cleanup EXIT

if [ -n "$(shared_dirty)" ]; then
  echo "ERROR: shared working tree is dirty before the run; refusing to start:" >&2
  shared_dirty >&2
  trap - EXIT
  exit 1
fi

# --- per-platform build (log to $LOGDIR/<platform>-<phase>.log) and marker lookup ---
build_android() { (cd "$ROOT/KMP_template_android" && rm -f "$APK" && ./gradlew --console=plain :app:assembleDebug); }
find_android()  { [ -f "$APK" ] && unzip -p "$APK" 'classes*.dex' | strings | grep -q "$MARKER"; }

build_desktop() {
  (
    cd "$ROOT/KMP_template_desktop" || exit 1
    mvn -B -o compile || exit 1
    cp_file="$(mktemp)"
    mvn -B -o -q dependency:build-classpath -Dmdep.outputFile="$cp_file" || exit 1
    printf '%s\n/exit\n' 'System.out.println(new com.tarasovvp.kmptemplate.SystemInfo().getInfo());' \
      | jshell --class-path "$(cat "$cp_file"):target/classes" -s > "$SMOKE_OUT" 2>&1
    rm -f "$cp_file"
    cat "$SMOKE_OUT"
    grep -q 'Hello from KMP module' "$SMOKE_OUT"
  )
}
find_desktop() { grep -q "$MARKER" "$SMOKE_OUT"; }

build_ios() {
  (cd "$ROOT/KMP_template_ios" && rm -rf "$IOS_APP" && xcodebuild -project KMP_template_ios.xcodeproj -scheme KMP_template_ios \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$IOS_DD" CODE_SIGNING_ALLOWED=NO build)
}
# Kotlin/Native keeps string literals as UTF-16LE, so plain `strings` misses them: look for both encodings.
find_ios() {
  [ -d "$IOS_APP" ] || return 1
  local f
  while IFS= read -r -d '' f; do
    M="$MARKER" perl -0777 -ne 'BEGIN { $a = $ENV{M}; $u = join("\0", split //, $a); }
      exit((index($_, $a) >= 0 || index($_, $u) >= 0) ? 0 : 1)' "$f" && return 0
  done < <(find "$IOS_APP" -type f -print0)
  return 1
}

build_web() { (cd "$ROOT/KMP_template_web" && rm -rf dist && npm run build); }
find_web()  { [ -d "$WEB_DIST" ] && grep -rq "$MARKER" "$WEB_DIST"; }

PLATFORMS="android desktop ios web"
run_phase() {   # run_phase <phase-name> <results-array-name>  (marker expected: present in 'with', absent in 'without')
  local phase="$1" p res
  echo "==> [$phase] propagate"
  "$ROOT/scripts/propagate.sh" > "$LOGDIR/propagate-$phase.log" 2>&1 \
    || { echo "propagate failed, see $LOGDIR/propagate-$phase.log" >&2; return 1; }
  for p in $PLATFORMS; do
    echo "==> [$phase] build $p"
    if "build_$p" > "$LOGDIR/$p-$phase.log" 2>&1; then
      if "find_$p"; then res=found; else res=absent; fi
    else
      res=BUILD-FAIL
    fi
    eval "res_${phase}_${p}=$res"
  done
}

# Phase 1: marker injected into commonMain
sed -i '' "s/$ANCHOR/$ANCHOR $MARKER/" "$SHARED/$SRC_REL"
if ! grep -q "$MARKER" "$SHARED/$SRC_REL"; then echo "ERROR: could not inject marker" >&2; exit 1; fi
run_phase with || exit 1

# Phase 2: revert and make sure it is gone
revert_shared
if [ -n "$(shared_dirty)" ]; then echo "ERROR: revert left shared dirty" >&2; exit 1; fi
run_phase without || exit 1

echo
echo "marker: $MARKER"
printf '%-10s | %-16s | %-16s\n' platform "marker appeared" "marker gone"
printf '%-10s-+-%-16s-+-%-16s\n' ---------- ---------------- ----------------
fail=0
for p in $PLATFORMS; do
  eval "w=\$res_with_$p; wo=\$res_without_$p"
  a=NO; [ "$w" = found ] && a=yes
  g=NO; [ "$wo" = absent ] && g=yes
  [ "$a" = yes ] && [ "$g" = yes ] || fail=1
  printf '%-10s | %-16s | %-16s\n' "$p" "$a${w:+ ($w)}" "$g${wo:+ ($wo)}"
done
echo "logs: $LOGDIR"
exit "$fail"
