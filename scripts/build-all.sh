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
  local cp_file out
  cp_file="$(mktemp)"
  mvn -B -o -q dependency:build-classpath -Dmdep.outputFile="$cp_file" || return 1
  out="$(printf '%s\n%s\n/exit\n' \
          'System.out.println("info=" + new com.tarasovvp.kmptemplate.SystemInfo().getInfo());' \
          'System.out.println("deviceModel=" + new com.tarasovvp.kmptemplate.SystemInfo().getDeviceModel());' \
        | jshell --class-path "$(cat "$cp_file"):target/classes" -s 2>&1)"
  rm -f "$cp_file"
  echo "$out"
  # jshell exits 0 even when the snippet throws, so check the output
  echo "$out" | grep -qE 'Exception|Error' && { echo "SMOKE FAIL (desktop): behaviour is broken, not the build: exception in jshell output"; return 1; }
  echo "$out" | grep -q 'Hello from KMP module' || { echo "SMOKE FAIL (desktop): behaviour is broken, not the build: getInfo() did not print the greeting"; return 1; }
  echo "$out" | grep -q 'deviceModel=Desktop (' || { echo "SMOKE FAIL (desktop): behaviour is broken, not the build: getDeviceModel() must start with \"Desktop (\""; return 1; }
  return 0
}
check_ios() {
  cd "$ROOT/KMP_template_ios" && xcodebuild -project KMP_template_ios.xcodeproj -scheme KMP_template_ios \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kmp-ios-dd \
    CODE_SIGNING_ALLOWED=NO build
}
check_web() {
  cd "$ROOT/KMP_template_web" && npm run build \
    && node --preserve-symlinks "$ROOT/scripts/smoke/web-smoke.mjs" "$ROOT/KMP_template_web"
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
