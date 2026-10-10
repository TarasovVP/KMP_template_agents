#!/usr/bin/env bash
# Behavioural smoke for desktop, the one way to run it (build-all.sh uses this too). Does NOT run `mvn compile`:
# run `mvn -f KMP_template_desktop/pom.xml -o compile` first so target/classes is current.
# Usage: scripts/smoke/desktop-smoke.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D="$ROOT/KMP_template_desktop"
fail() { echo "SMOKE FAIL (desktop): behaviour is broken, not the build: $1"; exit 1; }

[ -d "$D/target/classes" ] || { echo "desktop-smoke: $D/target/classes is missing; run mvn -f KMP_template_desktop/pom.xml -o compile first" >&2; exit 2; }
cp_file="$(mktemp)"
mvn -B -o -q -f "$D/pom.xml" dependency:build-classpath -Dmdep.outputFile="$cp_file" || { rm -f "$cp_file"; echo "desktop-smoke: cannot build the classpath" >&2; exit 2; }
out="$(printf '%s\n%s\n/exit\n' \
        'System.out.println("info=" + new com.tarasovvp.kmptemplate.SystemInfo().getInfo());' \
        'System.out.println("deviceModel=" + new com.tarasovvp.kmptemplate.SystemInfo().getDeviceModel());' \
      | jshell --class-path "$(cat "$cp_file"):$D/target/classes" -s 2>&1)"
rm -f "$cp_file"
echo "$out"
# jshell exits 0 even when the snippet throws, so check the output
echo "$out" | grep -qE 'Exception|Error' && fail "exception in jshell output"
echo "$out" | grep -q 'Hello from KMP module' || fail "getInfo() did not print the greeting"
echo "$out" | grep -q 'deviceModel=Desktop (' || fail "getDeviceModel() must start with \"Desktop (\""
echo "SMOKE OK (desktop)"
