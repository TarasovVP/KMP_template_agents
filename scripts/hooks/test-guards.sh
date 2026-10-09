#!/usr/bin/env bash
# Feed JSON to the guard hooks and check exit codes (0 = allow, 2 = deny). Exit 0 only if every case passes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export HOME="${HOME:?}"
LINK="$ROOT/KMP_template_shared/.guard-test-link"
LINK_IN="$ROOT/KMP_template_shared/.guard-test-link-in"
trap 'rm -f "$LINK" "$LINK_IN"' EXIT
ln -s /tmp "$LINK"                                              # symlink pointing outside the allowed dir
ln -s "$ROOT/KMP_template_shared/shared/src" "$LINK_IN"         # symlink staying inside

command -v jq >/dev/null 2>&1 || command -v node >/dev/null 2>&1 || { echo "need jq or node to build test JSON"; exit 1; }
mkjson() {   # mkjson <tool> <key> <value> [cwd]
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg t "$1" --arg k "$2" --arg v "$3" --arg c "${4:-$ROOT}" '{tool_name:$t, cwd:$c, tool_input:{($k):$v}}'
  else
    node -e 'console.log(JSON.stringify({tool_name:process.argv[1],cwd:process.argv[4],tool_input:{[process.argv[2]]:process.argv[3]}}))' "$1" "$2" "$3" "${4:-$ROOT}"
  fi
}

pass=0; fail=0
check() {   # check <expected-exit> <label> <json> <hook> [hook-args...]
  local want="$1" label="$2" json="$3"; shift 3
  local err; err="$(printf '%s' "$json" | "$HERE/$1" "${@:2}" 2>&1 >/dev/null)"; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); printf 'ok    %-52s exit=%s\n' "$label" "$got"
  else fail=$((fail + 1)); printf 'FAIL  %-52s want=%s got=%s  %s\n' "$label" "$want" "$got" "$err"; fi
}

S="$ROOT/KMP_template_shared"; I="$ROOT/KMP_template_ios"
echo "--- guard-paths.sh KMP_template_shared"
P=(guard-paths.sh KMP_template_shared)
check 0 "Edit inside shared"                     "$(mkjson Edit file_path "$S/shared/src/commonMain/X.kt")" "${P[@]}"
check 0 "Write new file in new dir inside shared" "$(mkjson Write file_path "$S/shared/src/newdir/deep/Y.kt")" "${P[@]}"
check 0 "relative path + cwd=shared"             "$(mkjson Edit file_path "shared/src/X.kt" "$S")" "${P[@]}"
check 0 "NotebookEdit inside shared"             "$(mkjson NotebookEdit notebook_path "$S/n.ipynb")" "${P[@]}"
check 0 "symlink staying inside shared"          "$(mkjson Edit file_path "$LINK_IN/commonMain/X.kt")" "${P[@]}"
check 0 "../ that stays inside shared"           "$(mkjson Edit file_path "$S/shared/../shared/src/X.kt")" "${P[@]}"
check 2 "Edit in ios repo"                       "$(mkjson Edit file_path "$I/KMP_template_ios/ContentView.swift")" "${P[@]}"
check 2 "../ escape to ios"                      "$(mkjson Edit file_path "$S/../KMP_template_ios/x")" "${P[@]}"
check 2 "../ escape to /etc"                     "$(mkjson Write file_path "$S/../../../../etc/hosts")" "${P[@]}"
check 2 "symlink pointing outside"               "$(mkjson Write file_path "$LINK/evil.txt")" "${P[@]}"
check 2 "relative path + cwd=repo root"          "$(mkjson Edit file_path "shared/src/X.kt" "$ROOT")" "${P[@]}"
check 2 "sibling dir with same prefix"           "$(mkjson Edit file_path "${S}_evil/x")" "${P[@]}"
check 2 "scripts/ of the harness"                "$(mkjson Edit file_path "$ROOT/scripts/build-all.sh")" "${P[@]}"
check 2 "NotebookEdit outside"                   "$(mkjson NotebookEdit notebook_path "/tmp/n.ipynb")" "${P[@]}"
check 2 "no path in tool_input"                  "$(mkjson Edit other value)" "${P[@]}"
check 2 "garbage stdin"                          "not json" "${P[@]}"
echo "--- guard-paths.sh KMP_template_ios"
check 0 "Edit inside ios"                        "$(mkjson Edit file_path "$I/KMP_template_ios/ContentView.swift")" guard-paths.sh KMP_template_ios
check 2 "Edit in shared (ios guard)"             "$(mkjson Edit file_path "$S/shared/src/X.kt")" guard-paths.sh KMP_template_ios

echo "--- guard-bash.sh shared"
B=(guard-bash.sh shared); G="./KMP_template_shared/gradlew -p KMP_template_shared"
check 0 "gradle assemble"                        "$(mkjson Bash command "$G assemble")" "${B[@]}"
check 0 "gradle tasks + flags"                   "$(mkjson Bash command "$G :shared:assembleSharedReleaseXCFramework --console=plain --stacktrace")" "${B[@]}"
check 0 "git -C shared status"                   "$(mkjson Bash command "git -C KMP_template_shared status")" "${B[@]}"
check 0 "git -C shared log -n 5 --oneline"       "$(mkjson Bash command "git -C KMP_template_shared log -n 5 --oneline")" "${B[@]}"
check 0 "git -C shared diff -- path"             "$(mkjson Bash command "git -C KMP_template_shared diff -- shared/src")" "${B[@]}"
check 2 "publishToMavenLocal"                    "$(mkjson Bash command "$G :shared:publishToMavenLocal")" "${B[@]}"
check 2 "publish (lower-case in name)"           "$(mkjson Bash command "$G publishAndroidReleasePublicationToMavenLocal")" "${B[@]}"
check 2 "chain with &&"                          "$(mkjson Bash command "$G assemble && ls")" "${B[@]}"
check 2 "chain with ;"                           "$(mkjson Bash command "$G assemble; rm -rf x")" "${B[@]}"
check 2 "pipe"                                   "$(mkjson Bash command "git -C KMP_template_shared log | head")" "${B[@]}"
check 2 "|| chain"                               "$(mkjson Bash command "$G assemble || true")" "${B[@]}"
check 2 "command substitution \$()"              "$(mkjson Bash command "$G \$(whoami)")" "${B[@]}"
check 2 "backticks"                              "$(mkjson Bash command "$G \`whoami\`")" "${B[@]}"
check 2 "redirect >"                             "$(mkjson Bash command "git -C KMP_template_shared log > /tmp/x")" "${B[@]}"
check 2 "redirect <"                             "$(mkjson Bash command "$G assemble < /dev/null")" "${B[@]}"
check 2 "newline"                                "$(mkjson Bash command "$G assemble
rm -rf /")" "${B[@]}"
check 2 "sed -i"                                 "$(mkjson Bash command "sed -i '' s/a/b/ KMP_template_shared/shared/build.gradle.kts")" "${B[@]}"
check 2 "other project via -p"                   "$(mkjson Bash command "./KMP_template_android/gradlew -p KMP_template_android assembleDebug")" "${B[@]}"
check 2 "gradle -p other dir"                    "$(mkjson Bash command "./KMP_template_shared/gradlew -p KMP_template_ios assemble")" "${B[@]}"
check 2 "gradle init script"                     "$(mkjson Bash command "$G -I evil.gradle assemble")" "${B[@]}"
check 2 "git --output"                           "$(mkjson Bash command "git -C KMP_template_shared diff --output=/tmp/x")" "${B[@]}"
check 2 "git commit"                             "$(mkjson Bash command "git -C KMP_template_shared commit -m x")" "${B[@]}"
check 2 "git -C ios (shared profile)"            "$(mkjson Bash command "git -C KMP_template_ios status")" "${B[@]}"
check 2 "cat file"                               "$(mkjson Bash command "cat KMP_template_shared/local.properties")" "${B[@]}"
check 2 "empty command"                          "$(mkjson Bash command "")" "${B[@]}"

echo "--- guard-bash.sh ios"
B=(guard-bash.sh ios); X="xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj"
check 0 "xcodebuild build"                       "$(mkjson Bash command "$X -scheme KMP_template_ios -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kmp-ios-dd CODE_SIGNING_ALLOWED=NO build")" "${B[@]}"
check 0 "xcodebuild Release"                     "$(mkjson Bash command "$X -scheme KMP_template_ios -configuration Release CODE_SIGNING_ALLOWED=NO build")" "${B[@]}"
check 0 "git -C ios diff"                        "$(mkjson Bash command "git -C KMP_template_ios diff")" "${B[@]}"
check 2 "xcodebuild other project"               "$(mkjson Bash command "xcodebuild -project Other/Other.xcodeproj -scheme X build")" "${B[@]}"
check 2 "xcodebuild && rm"                       "$(mkjson Bash command "$X build && rm -rf /tmp/x")" "${B[@]}"
check 2 "xcodebuild derivedData outside /tmp"    "$(mkjson Bash command "$X -derivedDataPath /Users/x/dd build")" "${B[@]}"
check 2 "xcodebuild unknown arg"                 "$(mkjson Bash command "$X -scheme KMP_template_ios OTHER_LDFLAGS=-evil build")" "${B[@]}"
check 2 "xcodebuild extra-quoted"                "$(mkjson Bash command "$X -scheme 'KMP_template_ios' build")" "${B[@]}"
check 2 "gradle (ios profile)"                   "$(mkjson Bash command "$G assemble")" "${B[@]}"
check 2 "git -C shared (ios profile)"            "$(mkjson Bash command "git -C KMP_template_shared status")" "${B[@]}"
check 2 "propagate.sh"                           "$(mkjson Bash command "scripts/propagate.sh")" "${B[@]}"
check 2 "unknown profile"                        "$(mkjson Bash command "git status")" guard-bash.sh nope

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
