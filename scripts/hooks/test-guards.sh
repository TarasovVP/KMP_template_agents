#!/usr/bin/env bash
# Feed JSON to the guard hooks and check exit codes (0 = allow, 2 = deny). Exit 0 only if every case passes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export HOME="${HOME:?}"
LINK="$ROOT/KMP_template_shared/.guard-test-link"
LINK_IN="$ROOT/KMP_template_shared/.guard-test-link-in"
DENY_LOG="$(mktemp)"; export HOOK_DENIAL_LOG="$DENY_LOG"   # keep the real logs/hook-denials.jsonl clean
trap 'rm -f "$LINK" "$LINK_IN" "$DENY_LOG"' EXIT
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

Q="'"
SEARCH_PROFILES=(shared ios orchestrator)
for prof in "${SEARCH_PROFILES[@]}"; do
  echo "--- search (find/grep/ls) in profile $prof"
  B=(guard-bash.sh "$prof")
  check 0 "grep 'a|b' quoted"                    "$(mkjson Bash command "grep -rn ${Q}a|b${Q} $S/shared/src")" "${B[@]}"
  check 0 "grep '\\\$' quoted"                    "$(mkjson Bash command "grep -rn ${Q}\\\$${Q} $S/shared/src")" "${B[@]}"
  check 0 "grep -A/--include/--exclude-dir"      "$(mkjson Bash command "grep -rn -A 2 ${Q}--include=*.kt${Q} --exclude-dir=build ${Q}fun get${Q} $S")" "${B[@]}"
  check 0 "grep -rnE relative path, cwd=root"    "$(mkjson Bash command "grep -rnE ${Q}Hello|Device${Q} KMP_template_shared/shared/src")" "${B[@]}"
  check 0 "grep with ~/ path"                    "$(mkjson Bash command "grep -rl ${Q}x${Q} ~/kmp-agents/KMP_template_ios")" "${B[@]}"
  check 2 "grep a|b unquoted"                    "$(mkjson Bash command "grep -rn a|b $S")" "${B[@]}"
  check 2 "grep \\\$ unquoted"                   "$(mkjson Bash command "grep -rn \\\$ $S")" "${B[@]}"
  check 2 "grep pattern not quoted"              "$(mkjson Bash command "grep -rn fun $S")" "${B[@]}"
  check 2 "grep double-quoted pattern"           "$(mkjson Bash command "grep -rn \"fun\" $S")" "${B[@]}"
  check 2 "grep outside ~/kmp-agents"            "$(mkjson Bash command "grep -rn ${Q}x${Q} /etc")" "${B[@]}"
  check 2 "grep ../ escape"                      "$(mkjson Bash command "grep -rn ${Q}x${Q} $S/../../..")" "${B[@]}"
  check 2 "grep symlink pointing outside"        "$(mkjson Bash command "grep -rn ${Q}x${Q} $LINK")" "${B[@]}"
  check 2 "grep -f (pattern file)"               "$(mkjson Bash command "grep -f /etc/passwd ${Q}x${Q} $S")" "${B[@]}"
  check 2 "grep unknown flag --color=always"     "$(mkjson Bash command "grep --color=always ${Q}x${Q} $S")" "${B[@]}"
  check 2 "grep without path"                    "$(mkjson Bash command "grep -rn ${Q}x${Q}")" "${B[@]}"
  check 2 "grep unbalanced quote"                "$(mkjson Bash command "grep -rn ${Q}x $S")" "${B[@]}"
  check 0 "find -name -type -maxdepth"           "$(mkjson Bash command "find $S/shared/src -maxdepth 3 -type f -name ${Q}*.kt${Q} -print")" "${B[@]}"
  check 0 "find -iname -path (relative, cwd=root)" "$(mkjson Bash command "find KMP_template_ios -iname ${Q}*.swift${Q} -path ${Q}*Packages*${Q}")" "${B[@]}"
  check 2 "find -exec"                           "$(mkjson Bash command "find $S -name ${Q}*.kt${Q} -exec cat ${Q}{}${Q} ${Q}+${Q}")" "${B[@]}"
  check 2 "find -exec bare"                      "$(mkjson Bash command "find $S -exec rm -rf x")" "${B[@]}"
  check 2 "find -delete"                         "$(mkjson Bash command "find $S -name ${Q}*.kt${Q} -delete")" "${B[@]}"
  check 2 "find -execdir"                        "$(mkjson Bash command "find $S -execdir rm x")" "${B[@]}"
  check 2 "find -ok"                             "$(mkjson Bash command "find $S -ok rm x")" "${B[@]}"
  check 2 "find -fprint"                         "$(mkjson Bash command "find $S -fprint /tmp/x")" "${B[@]}"
  check 2 "find -fls"                            "$(mkjson Bash command "find $S -fls /tmp/x")" "${B[@]}"
  check 2 "find -printf"                         "$(mkjson Bash command "find $S -printf ${Q}%p${Q}")" "${B[@]}"
  check 2 "find outside ~/kmp-agents"            "$(mkjson Bash command "find /etc -name ${Q}passwd${Q}")" "${B[@]}"
  check 2 "find / "                              "$(mkjson Bash command "find / -name ${Q}x${Q}")" "${B[@]}"
  check 2 "find second path outside"             "$(mkjson Bash command "find $S /tmp -name ${Q}x${Q}")" "${B[@]}"
  check 2 "find without path"                    "$(mkjson Bash command "find -name ${Q}x${Q}")" "${B[@]}"
  check 2 "find -type l"                         "$(mkjson Bash command "find $S -type l")" "${B[@]}"
  check 0 "ls inside"                            "$(mkjson Bash command "ls -la $S/shared")" "${B[@]}"
  check 0 "ls without args, cwd=root"            "$(mkjson Bash command "ls")" "${B[@]}"
  check 2 "ls /etc"                              "$(mkjson Bash command "ls /etc")" "${B[@]}"
  check 2 "ls ~"                                 "$(mkjson Bash command "ls ~")" "${B[@]}"
  check 2 "ls ../ escape"                        "$(mkjson Bash command "ls $S/../..")" "${B[@]}"
  check 2 "ls without args, cwd outside"         "$(mkjson Bash command "ls" /tmp)" "${B[@]}"
  check 2 "ls glob unquoted"                     "$(mkjson Bash command "ls $S/*")" "${B[@]}"
  check 2 "ls | head"                            "$(mkjson Bash command "ls $S | head")" "${B[@]}"
done

echo "--- guard-bash.sh ios: -quiet"
B=(guard-bash.sh ios); X="xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj"
check 0 "xcodebuild -quiet"                      "$(mkjson Bash command "$X -scheme KMP_template_ios -quiet CODE_SIGNING_ALLOWED=NO build")" "${B[@]}"

echo "--- guard-bash.sh orchestrator"
B=(guard-bash.sh orchestrator)
check 0 "scripts/propagate.sh"                   "$(mkjson Bash command "scripts/propagate.sh")" "${B[@]}"
check 0 "./scripts/propagate.sh"                 "$(mkjson Bash command "./scripts/propagate.sh")" "${B[@]}"
check 0 "absolute scripts/build-all.sh"          "$(mkjson Bash command "$ROOT/scripts/build-all.sh")" "${B[@]}"
check 0 "build-all.sh --propagate"               "$(mkjson Bash command "scripts/build-all.sh --propagate")" "${B[@]}"
check 0 "check-propagation.sh"                   "$(mkjson Bash command "scripts/check-propagation.sh")" "${B[@]}"
check 0 "test-guards.sh"                         "$(mkjson Bash command "scripts/hooks/test-guards.sh")" "${B[@]}"
check 0 "git -C . status"                        "$(mkjson Bash command "git -C . status")" "${B[@]}"
check 0 "git -C ios status --short"              "$(mkjson Bash command "git -C KMP_template_ios status --short")" "${B[@]}"
check 0 "git -C web log -n 3 --oneline"          "$(mkjson Bash command "git -C KMP_template_web log -n 3 --oneline")" "${B[@]}"
check 0 "git -C android diff HEAD -- path"       "$(mkjson Bash command "git -C KMP_template_android diff HEAD -- app/src")" "${B[@]}"
check 0 "git -C desktop show HEAD"               "$(mkjson Bash command "git -C KMP_template_desktop show HEAD")" "${B[@]}"
check 0 "git -C shared add paths"                "$(mkjson Bash command "git -C KMP_template_shared add CLAUDE.md shared/src")" "${B[@]}"
check 0 "git -C . add harness paths"             "$(mkjson Bash command "git -C . add scripts/hooks/guard-bash.sh .claude")" "${B[@]}"
check 0 "git -C ios restore path"                "$(mkjson Bash command "git -C KMP_template_ios restore -- Packages/KMPTemplate/.shared-rev")" "${B[@]}"
check 0 "git commit -m '...'"                    "$(mkjson Bash command "git -C KMP_template_ios commit -m ${Q}Update shared; \$x \"y\" \`z\`${Q}")" "${B[@]}"
check 0 "git commit -m multi-line"               "$(mkjson Bash command "git -C . commit -m ${Q}Title

Body line

Co-Authored-By: X <x@y>${Q}")" "${B[@]}"
check 0 "grep in orchestrator"                   "$(mkjson Bash command "grep -rn ${Q}a|b${Q} $ROOT/logs")" "${B[@]}"
check 2 "git push"                               "$(mkjson Bash command "git -C KMP_template_shared push")" "${B[@]}"
check 2 "git push origin main"                   "$(mkjson Bash command "git -C . push origin main")" "${B[@]}"
check 2 "git reset --hard"                       "$(mkjson Bash command "git -C . reset --hard")" "${B[@]}"
check 2 "git rebase"                             "$(mkjson Bash command "git -C . rebase main")" "${B[@]}"
check 2 "git clean -fd"                          "$(mkjson Bash command "git -C . clean -fd")" "${B[@]}"
check 2 "git checkout"                           "$(mkjson Bash command "git -C . checkout main")" "${B[@]}"
check 2 "git stash"                              "$(mkjson Bash command "git -C . stash")" "${B[@]}"
check 2 "git without -C"                         "$(mkjson Bash command "git status")" "${B[@]}"
check 2 "git -C other repo"                      "$(mkjson Bash command "git -C /tmp status")" "${B[@]}"
check 2 "git -C subdir (not a repo root)"        "$(mkjson Bash command "git -C KMP_template_shared/shared status")" "${B[@]}"
check 2 "git diff --output"                      "$(mkjson Bash command "git -C . diff --output=/tmp/x")" "${B[@]}"
check 2 "git add -A"                             "$(mkjson Bash command "git -C . add -A")" "${B[@]}"
check 2 "git add repo root (.)"                  "$(mkjson Bash command "git -C KMP_template_ios add .")" "${B[@]}"
check 2 "git add ../ escape"                     "$(mkjson Bash command "git -C KMP_template_ios add ../KMP_template_shared/x")" "${B[@]}"
check 2 "git add pathspec magic"                 "$(mkjson Bash command "git -C KMP_template_ios add :/")" "${B[@]}"
check 2 "git add without paths"                  "$(mkjson Bash command "git -C KMP_template_ios add")" "${B[@]}"
check 2 "git restore --staged"                   "$(mkjson Bash command "git -C KMP_template_ios restore --staged x")" "${B[@]}"
check 2 "git commit -a"                          "$(mkjson Bash command "git -C . commit -a -m ${Q}x${Q}")" "${B[@]}"
check 2 "git commit --amend"                     "$(mkjson Bash command "git -C . commit --amend -m ${Q}x${Q}")" "${B[@]}"
check 2 "git commit -m unquoted"                 "$(mkjson Bash command "git -C . commit -m msg")" "${B[@]}"
check 2 "git commit -m double-quoted"            "$(mkjson Bash command "git -C . commit -m \"msg\"")" "${B[@]}"
check 2 "git commit && push"                     "$(mkjson Bash command "git -C . commit -m ${Q}x${Q} && git -C . push")" "${B[@]}"
check 2 "git commit message then extra"          "$(mkjson Bash command "git -C . commit -m ${Q}x${Q} ${Q}y${Q}")" "${B[@]}"
check 2 "sed -i"                                 "$(mkjson Bash command "sed -i ${Q}${Q} ${Q}s/a/b/${Q} KMP_template_shared/x")" "${B[@]}"
check 2 "awk"                                    "$(mkjson Bash command "awk ${Q}{print}${Q} KMP_template_shared/x")" "${B[@]}"
check 2 "cat"                                    "$(mkjson Bash command "cat logs/contract.txt")" "${B[@]}"
check 2 "tee"                                    "$(mkjson Bash command "tee x")" "${B[@]}"
check 2 "build-all.sh with other arg"            "$(mkjson Bash command "scripts/build-all.sh --evil")" "${B[@]}"
check 2 "propagate.sh with args"                 "$(mkjson Bash command "scripts/propagate.sh x")" "${B[@]}"
check 2 "script outside scripts/"                "$(mkjson Bash command "/tmp/propagate.sh")" "${B[@]}"
check 2 "other script"                           "$(mkjson Bash command "scripts/evil.sh")" "${B[@]}"
check 2 "script chained"                         "$(mkjson Bash command "scripts/propagate.sh; rm -rf x")" "${B[@]}"
check 2 "xcodebuild (orchestrator profile)"      "$(mkjson Bash command "xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj build")" "${B[@]}"
check 2 "gradle (orchestrator profile)"          "$(mkjson Bash command "./KMP_template_shared/gradlew -p KMP_template_shared assemble")" "${B[@]}"
check 2 "empty command"                          "$(mkjson Bash command "")" "${B[@]}"

echo "--- guard-bash.sh shared: web-smoke.sh"
B=(guard-bash.sh shared)
check 0 "web-smoke.sh browser"                   "$(mkjson Bash command "scripts/smoke/web-smoke.sh browser")" "${B[@]}"
check 0 "web-smoke.sh node"                      "$(mkjson Bash command "scripts/smoke/web-smoke.sh node")" "${B[@]}"
check 0 "./web-smoke.sh node"                    "$(mkjson Bash command "./scripts/smoke/web-smoke.sh node")" "${B[@]}"
check 0 "absolute web-smoke.sh browser"          "$(mkjson Bash command "$ROOT/scripts/smoke/web-smoke.sh browser")" "${B[@]}"
check 2 "web-smoke.sh other argument"            "$(mkjson Bash command "scripts/smoke/web-smoke.sh evil")" "${B[@]}"
check 2 "web-smoke.sh no argument"               "$(mkjson Bash command "scripts/smoke/web-smoke.sh")" "${B[@]}"
check 2 "web-smoke.sh two arguments"             "$(mkjson Bash command "scripts/smoke/web-smoke.sh browser node")" "${B[@]}"
check 2 "web-smoke.sh chained"                   "$(mkjson Bash command "scripts/smoke/web-smoke.sh node; rm -rf x")" "${B[@]}"
check 2 "web-smoke.mjs directly"                 "$(mkjson Bash command "node --preserve-symlinks scripts/smoke/web-smoke.mjs x node")" "${B[@]}"
check 2 "scripts/build-all.sh (shared)"          "$(mkjson Bash command "scripts/build-all.sh")" "${B[@]}"
check 2 "scripts/propagate.sh (shared)"          "$(mkjson Bash command "scripts/propagate.sh")" "${B[@]}"
check 2 "scripts/check-propagation.sh (shared)"  "$(mkjson Bash command "scripts/check-propagation.sh")" "${B[@]}"
check 2 "scripts/hooks/guard-bash.sh (shared)"   "$(mkjson Bash command "scripts/hooks/guard-bash.sh shared")" "${B[@]}"
check 2 "other smoke script"                     "$(mkjson Bash command "scripts/smoke/other.sh node")" "${B[@]}"
check 2 "web-smoke.sh outside ~/kmp-agents"      "$(mkjson Bash command "/tmp/scripts/smoke/web-smoke.sh node")" "${B[@]}"
check 2 "web-smoke.sh (ios profile)"             "$(mkjson Bash command "scripts/smoke/web-smoke.sh node")" guard-bash.sh ios
check 2 "web-smoke.sh (orchestrator profile)"    "$(mkjson Bash command "scripts/smoke/web-smoke.sh node")" guard-bash.sh orchestrator

echo "--- guard-bash.sh android"
B=(guard-bash.sh android); AG="./KMP_template_android/gradlew -p KMP_template_android"
check 0 "android assembleDebug"                  "$(mkjson Bash command "$AG assembleDebug")" "${B[@]}"
check 0 "android :app tasks + flags"             "$(mkjson Bash command "$AG :app:assembleDebug :app:testDebugUnitTest -q --console=plain")" "${B[@]}"
check 0 "android help"                           "$(mkjson Bash command "$AG help")" "${B[@]}"
check 0 "git -C android diff"                    "$(mkjson Bash command "git -C KMP_template_android diff")" "${B[@]}"
check 0 "android search"                         "$(mkjson Bash command "grep -rn ${Q}shared${Q} KMP_template_android/app/src")" "${B[@]}"
check 2 "android publishToMavenLocal"            "$(mkjson Bash command "$AG publishToMavenLocal")" "${B[@]}"
check 2 "android task not in list"               "$(mkjson Bash command "$AG assembleRelease")" "${B[@]}"
check 2 "android no task"                        "$(mkjson Bash command "$AG -q")" "${B[@]}"
check 2 "android flag not in list"               "$(mkjson Bash command "$AG assembleDebug --offline")" "${B[@]}"
check 2 "android -I init script"                 "$(mkjson Bash command "$AG -I evil.gradle assembleDebug")" "${B[@]}"
check 2 "android gradlew without -p"             "$(mkjson Bash command "./KMP_template_android/gradlew assembleDebug")" "${B[@]}"
check 2 "android gradlew of shared"              "$(mkjson Bash command "./KMP_template_shared/gradlew -p KMP_template_shared assemble")" "${B[@]}"
check 2 "android -p other dir"                   "$(mkjson Bash command "./KMP_template_android/gradlew -p KMP_template_shared assembleDebug")" "${B[@]}"
check 2 "android chained"                        "$(mkjson Bash command "$AG assembleDebug && ls")" "${B[@]}"
check 2 "git -C ios (android profile)"           "$(mkjson Bash command "git -C KMP_template_ios status")" "${B[@]}"
check 2 "git commit (android profile)"           "$(mkjson Bash command "git -C KMP_template_android commit -m ${Q}x${Q}")" "${B[@]}"
check 2 "web-smoke (android profile)"            "$(mkjson Bash command "scripts/smoke/web-smoke.sh node")" "${B[@]}"
check 2 "desktop-smoke (android profile)"        "$(mkjson Bash command "scripts/smoke/desktop-smoke.sh")" "${B[@]}"
check 2 "propagate.sh (android profile)"         "$(mkjson Bash command "scripts/propagate.sh")" "${B[@]}"

echo "--- guard-bash.sh desktop"
B=(guard-bash.sh desktop); M="mvn -f KMP_template_desktop/pom.xml"
check 0 "mvn -o compile"                         "$(mkjson Bash command "$M -o compile")" "${B[@]}"
check 0 "mvn -o -q test"                         "$(mkjson Bash command "$M -o -q test")" "${B[@]}"
check 0 "mvn -o compile test"                    "$(mkjson Bash command "$M -o compile test")" "${B[@]}"
check 0 "desktop-smoke.sh"                       "$(mkjson Bash command "scripts/smoke/desktop-smoke.sh")" "${B[@]}"
check 0 "absolute desktop-smoke.sh"              "$(mkjson Bash command "$ROOT/scripts/smoke/desktop-smoke.sh")" "${B[@]}"
check 0 "git -C desktop log"                     "$(mkjson Bash command "git -C KMP_template_desktop log -n 3")" "${B[@]}"
check 0 "desktop find"                           "$(mkjson Bash command "find KMP_template_desktop/src -name ${Q}*.java${Q}")" "${B[@]}"
check 2 "mvn without -f"                         "$(mkjson Bash command "mvn -o compile")" "${B[@]}"
check 2 "mvn -f other pom"                       "$(mkjson Bash command "mvn -f KMP_template_web/pom.xml -o compile")" "${B[@]}"
check 2 "mvn without -o"                         "$(mkjson Bash command "$M compile")" "${B[@]}"
check 2 "mvn only flags"                         "$(mkjson Bash command "$M -o -q")" "${B[@]}"
check 2 "mvn install"                            "$(mkjson Bash command "$M -o install")" "${B[@]}"
check 2 "mvn deploy"                             "$(mkjson Bash command "$M -o deploy")" "${B[@]}"
check 2 "mvn exec:java"                          "$(mkjson Bash command "$M -o exec:java")" "${B[@]}"
check 2 "mvn -D property"                        "$(mkjson Bash command "$M -o compile -Dmaven.test.skip=true")" "${B[@]}"
check 2 "desktop-smoke.sh with arg"              "$(mkjson Bash command "scripts/smoke/desktop-smoke.sh x")" "${B[@]}"
check 2 "web-smoke (desktop profile)"            "$(mkjson Bash command "scripts/smoke/web-smoke.sh node")" "${B[@]}"
check 2 "build-all.sh (desktop profile)"         "$(mkjson Bash command "scripts/build-all.sh")" "${B[@]}"
check 2 "git -C web (desktop profile)"           "$(mkjson Bash command "git -C KMP_template_web status")" "${B[@]}"
check 2 "git push (desktop profile)"             "$(mkjson Bash command "git -C KMP_template_desktop push")" "${B[@]}"

echo "--- guard-bash.sh web"
B=(guard-bash.sh web); N="npm --prefix KMP_template_web"
check 0 "npm run build"                          "$(mkjson Bash command "$N run build")" "${B[@]}"
check 0 "npm install --ignore-scripts"           "$(mkjson Bash command "$N install --ignore-scripts")" "${B[@]}"
check 0 "web-smoke.sh browser"                   "$(mkjson Bash command "scripts/smoke/web-smoke.sh browser")" "${B[@]}"
check 0 "web-smoke.sh node"                      "$(mkjson Bash command "scripts/smoke/web-smoke.sh node")" "${B[@]}"
check 0 "git -C web status"                      "$(mkjson Bash command "git -C KMP_template_web status")" "${B[@]}"
check 0 "web grep node_modules d.ts"             "$(mkjson Bash command "grep -n ${Q}getInfo${Q} KMP_template_web/node_modules/KMP_template_shared-shared/KMP_template_shared-shared.d.ts")" "${B[@]}"
check 2 "npm install without --ignore-scripts"   "$(mkjson Bash command "$N install")" "${B[@]}"
check 2 "npm install other package"              "$(mkjson Bash command "$N install left-pad --ignore-scripts")" "${B[@]}"
check 2 "npm install flag first, extra"          "$(mkjson Bash command "$N install --ignore-scripts --force")" "${B[@]}"
check 2 "npm ci"                                 "$(mkjson Bash command "$N ci")" "${B[@]}"
check 2 "npm run other script"                   "$(mkjson Bash command "$N run dev")" "${B[@]}"
check 2 "npm run build extra arg"                "$(mkjson Bash command "$N run build -- --evil")" "${B[@]}"
check 2 "npm without --prefix"                   "$(mkjson Bash command "npm run build")" "${B[@]}"
check 2 "npm --prefix other dir"                 "$(mkjson Bash command "npm --prefix KMP_template_desktop run build")" "${B[@]}"
check 2 "npm publish"                            "$(mkjson Bash command "$N publish")" "${B[@]}"
check 2 "npx"                                    "$(mkjson Bash command "npx vite build")" "${B[@]}"
check 2 "node script directly"                   "$(mkjson Bash command "node scripts/smoke/web-smoke.mjs x node")" "${B[@]}"
check 2 "web-smoke.sh other arg"                 "$(mkjson Bash command "scripts/smoke/web-smoke.sh evil")" "${B[@]}"
check 2 "desktop-smoke (web profile)"            "$(mkjson Bash command "scripts/smoke/desktop-smoke.sh")" "${B[@]}"
check 2 "git -C android (web profile)"           "$(mkjson Bash command "git -C KMP_template_android status")" "${B[@]}"
check 2 "git commit (web profile)"               "$(mkjson Bash command "git -C KMP_template_web commit -m ${Q}x${Q}")" "${B[@]}"
check 2 "propagate.sh (web profile)"             "$(mkjson Bash command "scripts/propagate.sh")" "${B[@]}"
check 2 "cat package.json"                       "$(mkjson Bash command "cat KMP_template_web/package.json")" "${B[@]}"

echo "--- guard-paths.sh for android, desktop, web"
for plat in android desktop web; do
  PD="$ROOT/KMP_template_$plat"
  case "$plat" in android) OTHER="$ROOT/KMP_template_web" ;; *) OTHER="$ROOT/KMP_template_android" ;; esac
  check 0 "$plat: edit inside own dir"           "$(mkjson Edit file_path "$PD/some/dir/File.x")" guard-paths.sh "KMP_template_$plat"
  check 2 "$plat: edit in another project"       "$(mkjson Edit file_path "$OTHER/some/File.x")" guard-paths.sh "KMP_template_$plat"
  check 2 "$plat: ../ escape"                    "$(mkjson Write file_path "$PD/../KMP_template_shared/x")" guard-paths.sh "KMP_template_$plat"
done

echo "--- guard-bash.sh orchestrator: calls made by subagents"
B=(guard-bash.sh orchestrator)
mkjson_agent() {   # mkjson_agent <command> <agent_id> <agent_type>
  jq -nc --arg v "$1" --arg c "$ROOT" --arg i "$2" --arg t "$3" '{tool_name:"Bash", cwd:$c, agent_id:$i, agent_type:$t, tool_input:{command:$v}}'
}
check 0 "subagent call (web-agent) passes through"      "$(mkjson_agent "npm --prefix KMP_template_web run build" a1b2c3 web-agent)" "${B[@]}"
check 0 "subagent call (android-agent) passes through"  "$(mkjson_agent "./KMP_template_android/gradlew -p KMP_template_android :app:assembleDebug" a1b2c3 android-agent)" "${B[@]}"
check 0 "subagent call, command the orchestrator lacks" "$(mkjson_agent "mvn -f KMP_template_desktop/pom.xml -o compile" a1b2c3 desktop-agent)" "${B[@]}"
check 2 "same command without agent_id is checked"      "$(mkjson Bash command "npm --prefix KMP_template_web run build")" "${B[@]}"
check 2 "agent_id empty -> checked"                     "$(mkjson_agent "npm --prefix KMP_template_web run build" "" "")" "${B[@]}"
check 2 "agent_type only (main session --agent) checked" "$(mkjson_agent "sed -i x y" "" orchestrator)" "${B[@]}"
check 2 "agent_id with agent_type orchestrator checked" "$(mkjson_agent "git -C . push" a1b2c3 orchestrator)" "${B[@]}"
check 0 "orchestrator own allowed command, agent_type"  "$(mkjson_agent "git -C . status" "" orchestrator)" "${B[@]}"
check 2 "other profile ignores agent_id (shared)"       "$(mkjson_agent "sed -i x y" a1b2c3 web-agent)" guard-bash.sh shared

echo "--- absolute forms of own project paths"
SA=(guard-bash.sh shared); IA=(guard-bash.sh ios); AA=(guard-bash.sh android); DA=(guard-bash.sh desktop); WA=(guard-bash.sh web)
check 0 "shared: abs gradlew -p abs"             "$(mkjson Bash command "$ROOT/KMP_template_shared/gradlew -p $ROOT/KMP_template_shared assemble")" "${SA[@]}"
check 0 "shared: rel gradlew, abs -p"            "$(mkjson Bash command "./KMP_template_shared/gradlew -p $ROOT/KMP_template_shared assemble")" "${SA[@]}"
check 0 "shared: git -C abs"                     "$(mkjson Bash command "git -C $ROOT/KMP_template_shared status")" "${SA[@]}"
check 0 "shared: abs form, cwd elsewhere"        "$(mkjson Bash command "git -C $ROOT/KMP_template_shared status" /tmp)" "${SA[@]}"
check 2 "shared: abs -p into ios"                "$(mkjson Bash command "$ROOT/KMP_template_shared/gradlew -p $ROOT/KMP_template_ios assemble")" "${SA[@]}"
check 2 "shared: abs gradlew of android"         "$(mkjson Bash command "$ROOT/KMP_template_android/gradlew -p $ROOT/KMP_template_shared assemble")" "${SA[@]}"
check 2 "shared: abs outside ~/kmp-agents"       "$(mkjson Bash command "/tmp/KMP_template_shared/gradlew -p /tmp/KMP_template_shared assemble")" "${SA[@]}"
check 2 "shared: git -C abs other repo"          "$(mkjson Bash command "git -C $ROOT/KMP_template_ios status")" "${SA[@]}"
check 2 "shared: git -C abs subdir"              "$(mkjson Bash command "git -C $ROOT/KMP_template_shared/shared status")" "${SA[@]}"
check 2 "shared: git -C abs with ../"            "$(mkjson Bash command "git -C $ROOT/KMP_template_shared/../KMP_template_ios status")" "${SA[@]}"
check 0 "ios: abs -project"                      "$(mkjson Bash command "xcodebuild -project $ROOT/KMP_template_ios/KMP_template_ios.xcodeproj -scheme KMP_template_ios -destination ${Q}generic/platform=iOS Simulator${Q} -quiet build")" "${IA[@]}"
check 0 "ios: git -C abs"                        "$(mkjson Bash command "git -C $ROOT/KMP_template_ios diff")" "${IA[@]}"
check 2 "ios: abs -project of another project"   "$(mkjson Bash command "xcodebuild -project /tmp/Other/Other.xcodeproj build")" "${IA[@]}"
check 2 "ios: abs git -C shared"                 "$(mkjson Bash command "git -C $ROOT/KMP_template_shared status")" "${IA[@]}"
check 0 "android: abs gradlew -p abs"            "$(mkjson Bash command "$ROOT/KMP_template_android/gradlew -p $ROOT/KMP_template_android :app:assembleDebug")" "${AA[@]}"
check 0 "android: git -C abs"                    "$(mkjson Bash command "git -C $ROOT/KMP_template_android log -n 2")" "${AA[@]}"
check 2 "android: abs -p into shared"            "$(mkjson Bash command "$ROOT/KMP_template_android/gradlew -p $ROOT/KMP_template_shared assembleDebug")" "${AA[@]}"
check 2 "android: abs gradlew of shared"         "$(mkjson Bash command "$ROOT/KMP_template_shared/gradlew -p $ROOT/KMP_template_android assembleDebug")" "${AA[@]}"
check 2 "android: abs publish"                   "$(mkjson Bash command "$ROOT/KMP_template_android/gradlew -p $ROOT/KMP_template_android publishToMavenLocal")" "${AA[@]}"
check 0 "desktop: abs mvn -f"                    "$(mkjson Bash command "mvn -f $ROOT/KMP_template_desktop/pom.xml -o -q compile")" "${DA[@]}"
check 0 "desktop: git -C abs"                    "$(mkjson Bash command "git -C $ROOT/KMP_template_desktop status")" "${DA[@]}"
check 2 "desktop: abs mvn -f web pom"            "$(mkjson Bash command "mvn -f $ROOT/KMP_template_web/pom.xml -o compile")" "${DA[@]}"
check 2 "desktop: abs mvn -f outside"            "$(mkjson Bash command "mvn -f /tmp/pom.xml -o compile")" "${DA[@]}"
check 0 "web: abs npm --prefix"                  "$(mkjson Bash command "npm --prefix $ROOT/KMP_template_web run build")" "${WA[@]}"
check 0 "web: abs npm install"                   "$(mkjson Bash command "npm --prefix $ROOT/KMP_template_web install --ignore-scripts")" "${WA[@]}"
check 0 "web: git -C abs"                        "$(mkjson Bash command "git -C $ROOT/KMP_template_web status")" "${WA[@]}"
check 2 "web: abs npm --prefix desktop"          "$(mkjson Bash command "npm --prefix $ROOT/KMP_template_desktop run build")" "${WA[@]}"
check 2 "web: abs npm --prefix outside"          "$(mkjson Bash command "npm --prefix /tmp run build")" "${WA[@]}"
check 2 "web: abs npm install w/o flag"          "$(mkjson Bash command "npm --prefix $ROOT/KMP_template_web install")" "${WA[@]}"
check 2 "web: git -C abs symlink escape"         "$(mkjson Bash command "git -C $LINK status")" "${WA[@]}"

echo "--- guard-bash.sh orchestrator: which subagent types pass through"
B=(guard-bash.sh orchestrator)
for at in shared-agent ios-agent android-agent desktop-agent web-agent; do
  check 0 "agent_type $at passes"                "$(mkjson_agent "sed -i x y" a1b2c3 "$at")" "${B[@]}"
done
check 2 "unknown agent_type"                     "$(mkjson_agent "sed -i x y" a1b2c3 general-purpose)" "${B[@]}"
check 2 "agent_type Explore"                     "$(mkjson_agent "sed -i x y" a1b2c3 Explore)" "${B[@]}"
check 2 "empty agent_type, agent_id set"         "$(mkjson_agent "sed -i x y" a1b2c3 "")" "${B[@]}"
check 2 "known agent_type, empty agent_id"       "$(mkjson_agent "sed -i x y" "" web-agent)" "${B[@]}"
check 2 "no agent fields at all"                 "$(mkjson Bash command "sed -i x y")" "${B[@]}"
check 2 "agent_type lookalike"                   "$(mkjson_agent "sed -i x y" a1b2c3 web-agent-evil)" "${B[@]}"
check 2 "agent_type with different case"         "$(mkjson_agent "sed -i x y" a1b2c3 Web-Agent)" "${B[@]}"

echo "--- denial log (logs/hook-denials.jsonl, redirected to a temp file here)"
dlines() { wc -l < "$DENY_LOG" | tr -d ' '; }
n0=$(dlines)
printf '%s' "$(mkjson Bash command "git -C KMP_template_ios status")" | "$HERE/guard-bash.sh" ios >/dev/null 2>&1; rc=$?
n1=$(dlines)
[ "$rc" -eq 0 ] && [ "$n1" -eq "$n0" ] && { pass=$((pass + 1)); echo "ok    allowed call writes no line"; } || { fail=$((fail + 1)); echo "FAIL  allowed call writes no line (rc=$rc, $n0 -> $n1)"; }
printf '%s' "$(mkjson_agent "sed -i x y" a1b2c3 web-agent)" | "$HERE/guard-bash.sh" web >/dev/null 2>&1; rc=$?
n2=$(dlines)
[ "$rc" -eq 2 ] && [ "$n2" -eq $((n1 + 1)) ] && { pass=$((pass + 1)); echo "ok    denied bash call writes exactly one line"; } || { fail=$((fail + 1)); echo "FAIL  denied bash call writes exactly one line (rc=$rc, $n1 -> $n2)"; }
last="$(tail -n 1 "$DENY_LOG")"
if command -v jq >/dev/null 2>&1 && printf '%s' "$last" | jq -e '.agent_type == "web-agent" and .scope == "web" and .tool_name == "Bash" and .target == "sed -i x y" and (.reason | length > 0) and (.ts | length > 0)' >/dev/null; then
  pass=$((pass + 1)); echo "ok    line has agent_type, scope, tool_name, target, reason, ts"
else fail=$((fail + 1)); echo "FAIL  denial line content: $last"; fi
printf '%s' "$(mkjson Edit file_path "$I/x")" | "$HERE/guard-paths.sh" KMP_template_shared >/dev/null 2>&1; rc=$?
n3=$(dlines); last="$(tail -n 1 "$DENY_LOG")"
if [ "$rc" -eq 2 ] && [ "$n3" -eq $((n2 + 1)) ] && printf '%s' "$last" | jq -e '.agent_type == "main" and .scope == "KMP_template_shared" and .tool_name == "Edit"' >/dev/null; then
  pass=$((pass + 1)); echo "ok    denied path call: one line, agent_type=main"
else fail=$((fail + 1)); echo "FAIL  denied path call (rc=$rc, $n2 -> $n3): $last"; fi
long="$(printf 'x%.0s' $(seq 1 500))"
printf '%s' "$(mkjson Bash command "git -C KMP_template_ios commit -m $long")" | "$HERE/guard-bash.sh" ios >/dev/null 2>&1
if [ "$(tail -n 1 "$DENY_LOG" | jq -r '.target | length')" -le 300 ]; then pass=$((pass + 1)); echo "ok    target is cut to 300 characters"; else fail=$((fail + 1)); echo "FAIL  target not cut"; fi
n4=$(dlines)
printf '%s' "$(mkjson Bash command "sed -i x y")" | HOOK_DENIAL_LOG=/dev/null/no/such/dir/log.jsonl "$HERE/guard-bash.sh" ios >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ "$(dlines)" -eq "$n4" ] && { pass=$((pass + 1)); echo "ok    unwritable log: the denial still stands (exit 2)"; } || { fail=$((fail + 1)); echo "FAIL  unwritable log changed the decision (rc=$rc)"; }

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
