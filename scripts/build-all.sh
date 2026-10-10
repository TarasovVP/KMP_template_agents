#!/usr/bin/env bash
# Build/test all five projects. One failing check does not stop the others.
# Usage: scripts/build-all.sh [--propagate]
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOGDIR="$ROOT/logs/$STAMP"
mkdir -p "$LOGDIR"

names=(); results=(); times=(); tails=()

# run_check <name> <function>: runs the function with output going to logs/<stamp>/<name>.log
run_check() {
  local name="$1" fn="$2" log="$LOGDIR/$1.log" start=$SECONDS rc
  printf '==> %s\n' "$name"
  "$fn" > "$log" 2>&1
  rc=$?
  names+=("$name"); times+=("$((SECONDS - start))s")
  if [ "$rc" -eq 0 ]; then results+=("ok"); tails+=("")
  else results+=("FAIL"); tails+=("$(tail -n 5 "$log")"); fi
}

check_shared()  { cd "$ROOT/KMP_template_shared"  && ./gradlew --console=plain assemble; }
check_android() { cd "$ROOT/KMP_template_android" && ./gradlew --console=plain :app:assembleDebug :app:testDebugUnitTest; }
check_desktop() {
  cd "$ROOT/KMP_template_desktop" || return 1
  mvn -B -o compile || return 1
  "$ROOT/scripts/smoke/desktop-smoke.sh"
}
check_ios() {
  cd "$ROOT/KMP_template_ios" && xcodebuild -project KMP_template_ios.xcodeproj -scheme KMP_template_ios \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kmp-ios-dd \
    CODE_SIGNING_ALLOWED=NO build
}
check_web() {
  cd "$ROOT/KMP_template_web" && npm run build || return 1
  # both variants always run; the summary shows which one failed (see scripts/smoke/web-smoke.mjs)
  local rc=0 mode
  for mode in browser node; do
    "$ROOT/scripts/smoke/web-smoke.sh" "$mode" || rc=1
  done
  return "$rc"
}

if [ "${1:-}" = "--propagate" ]; then
  run_check propagate "$ROOT/scripts/propagate.sh"
fi

run_check shared  check_shared
run_check android check_android
run_check desktop check_desktop
run_check ios     check_ios
run_check web     check_web

echo
printf '%-10s | %-6s | %-6s\n' project result time
printf '%-10s-+-%-6s-+-%-6s\n' ---------- ------ ------
fail=0
for i in "${!names[@]}"; do
  printf '%-10s | %-6s | %-6s\n' "${names[$i]}" "${results[$i]}" "${times[$i]}"
  if [ "${results[$i]}" != "ok" ]; then
    fail=1
    printf '%s\n' "${tails[$i]}" | sed 's/^/    | /'
  fi
done
echo "logs: $LOGDIR"
exit "$fail"
