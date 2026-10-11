#!/usr/bin/env bash
# Behavioural smoke for desktop, the one way to run it (build-all.sh uses this too). Does NOT run `mvn compile`:
# run `mvn -f KMP_template_desktop/pom.xml -o compile` first so target/classes is current.
# Usage: scripts/smoke/desktop-smoke.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D="$ROOT/KMP_template_desktop"
fail_os() { echo "SMOKE FAIL (desktop): getOsVersion() is missing or threw: $1"; exit 1; }
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
# getOsVersion() (contract addition): must be callable and return a non-empty string; its meaning is not checked.
# Separate jshell run so that a missing method gives a clear message instead of a generic "Error" in the output above.
cp_file="$(mktemp)"
mvn -B -o -q -f "$D/pom.xml" dependency:build-classpath -Dmdep.outputFile="$cp_file" || { rm -f "$cp_file"; echo "desktop-smoke: cannot build the classpath" >&2; exit 2; }
os_out="$(printf '%s\n/exit\n' 'System.out.println("osVersion=" + new com.tarasovvp.kmptemplate.SystemInfo().getOsVersion());' \
        | jshell --class-path "$(cat "$cp_file"):$D/target/classes" -s 2>&1)"
rm -f "$cp_file"
echo "$os_out"
# the jshell echo of the snippet contains 'osVersion="', the real output has a value right after '='
echo "$os_out" | grep -q 'osVersion=[^" ]' || fail_os "$(echo "$os_out" | grep -E 'Exception|cannot find symbol|symbol:' | head -2 | sed 's/^[| ]*//' | tr '\n' ' ')${os_out:+(see jshell output above)}"
echo "SMOKE OK (desktop)"
