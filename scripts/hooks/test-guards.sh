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

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
