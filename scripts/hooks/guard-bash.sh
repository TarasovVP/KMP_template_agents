#!/usr/bin/env bash
# PreToolUse hook for Bash: single plain commands only, matched against a per-profile whitelist.
# Usage: guard-bash.sh <shared|ios|android|desktop|web|orchestrator>      (stdin: hook JSON)
#
# The command is tokenized here. Outside single quotes only [A-Za-z0-9_./=:,+@%-] and spaces are accepted
# (so no ; & | ` $ < > \ ( ) * ? [ ] { } " # ! newline); a leading ~/ is expanded to $HOME.
# Single quotes must be balanced; double quotes are not accepted outside single quotes.
# Inside single quotes anything goes (the shell does not interpret it).
set -u
set -f   # no globbing while we split the command into words
export LC_ALL=C
. "$(dirname "$0")/lib.sh"

PROFILE="${1:-}"
HOOK_SCOPE="$PROFILE"
INPUT="$(cat)"
cmd="$(json_get tool_input.command)"
cwd="$(json_get cwd)"; [ -n "$cwd" ] || cwd="$PWD"
ROOT="$(resolve_path "$HOME/kmp-agents" "/")"

# The orchestrator runs as the main session (--agent), so its frontmatter hook fires for EVERY Bash call of the session,
# including calls made by its subagents (which are checked by their own hooks). Hook input of a subagent call carries
# agent_id and agent_type (e.g. "web-agent"). Only a non-empty agent_id together with one of the five known agent types is
# passed through; anything else (no fields, empty, unknown type, "orchestrator") is checked as the orchestrator's own call.
if [ "$PROFILE" = orchestrator ]; then
  caller_id="$(json_get agent_id)"; caller_type="$(json_get agent_type)"
  if [ -n "$caller_id" ]; then
    case "$caller_type" in
      shared-agent|ios-agent|android-agent|desktop-agent|web-agent) exit 0 ;;
    esac
  fi
fi

SEARCH_FORMS="  find <paths inside ~/kmp-agents> [-name|-iname|-path|-ipath 'pat'] [-type f|d] [-maxdepth N] [-mindepth N] [-print]
  grep [-rRnilLcwxEFHhosI] [-A N] [-B N] [-C N] [--include=..] [--exclude=..] [--exclude-dir=..] 'pattern' <paths inside ~/kmp-agents>
  ls [-lahtrRFSd1] <paths inside ~/kmp-agents>
  (single quotes only; the pattern must be in single quotes; no -exec/-delete/-fprint*/-printf)"

case "$PROFILE" in
  shared) FORMS="  ./KMP_template_shared/gradlew -p KMP_template_shared <tasks and flags> (no 'publish' tasks)
  git -C KMP_template_shared status|diff|log [args]
  scripts/smoke/web-smoke.sh browser|node   (web behaviour smoke; run after :shared:jsBrowserProductionLibraryDistribution)
$SEARCH_FORMS"
          FOOTER="Publishing (publish*), propagate.sh, build-all.sh, commits and edits through the shell (sed -i, tee, redirects) are not available to you.
If you need such an operation, do not work around the restriction: put it in NOT_DONE of your report and the orchestrator will do it." ;;
  ios)    FORMS="  xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj [-scheme KMP_template_ios] [-configuration Debug|Release]
      [-destination 'generic/platform=iOS Simulator'] [-derivedDataPath /tmp/<name>] [CODE_SIGNING_ALLOWED=NO] [-quiet] [build|clean|test]
  git -C KMP_template_ios status|diff|log [args]
$SEARCH_FORMS"
          FOOTER="Publishing (publish*), propagate.sh, build-all.sh, commits and edits through the shell (sed -i, tee, redirects) are not available to you.
If you need such an operation, do not work around the restriction: put it in NOT_DONE of your report and the orchestrator will do it." ;;
  android) FORMS="  ./KMP_template_android/gradlew -p KMP_template_android <assembleDebug|:app:assembleDebug|testDebugUnitTest|:app:testDebugUnitTest|help> [-q] [--console=plain]
  git -C KMP_template_android status|diff|log [args]
$SEARCH_FORMS"
          FOOTER="Publishing (publish*), propagate.sh, build-all.sh, commits and edits through the shell (sed -i, tee, redirects) are not available to you.
If you need such an operation, do not work around the restriction: put it in NOT_DONE of your report and the orchestrator will do it." ;;
  desktop) FORMS="  mvn -f KMP_template_desktop/pom.xml -o [-q] compile|test
  scripts/smoke/desktop-smoke.sh   (behaviour smoke; run after mvn ... compile)
  git -C KMP_template_desktop status|diff|log [args]
$SEARCH_FORMS"
          FOOTER="Publishing (publish*), propagate.sh, build-all.sh, commits and edits through the shell (sed -i, tee, redirects) are not available to you.
If you need such an operation, do not work around the restriction: put it in NOT_DONE of your report and the orchestrator will do it." ;;
  web)    FORMS="  npm --prefix KMP_template_web run build
  npm --prefix KMP_template_web install --ignore-scripts
  scripts/smoke/web-smoke.sh browser|node
  git -C KMP_template_web status|diff|log [args]
$SEARCH_FORMS"
          FOOTER="Publishing (publish*), propagate.sh, build-all.sh, commits and edits through the shell (sed -i, tee, redirects) are not available to you.
If you need such an operation, do not work around the restriction: put it in NOT_DONE of your report and the orchestrator will do it." ;;
  orchestrator) FORMS="  scripts/propagate.sh | scripts/build-all.sh [--propagate] | scripts/check-propagation.sh | scripts/hooks/test-guards.sh
  git -C <. | KMP_template_shared|android|desktop|ios|web> status|diff|log|show [args]
  git -C <repo> add <paths inside the repo> | restore <paths inside the repo> | commit -m '<message in single quotes>'
$SEARCH_FORMS"
          FOOTER="push, reset, rebase, clean, checkout, stash and edits through the shell (sed, awk, cat, tee, redirects) are not available.
Do not work around the restriction: tell the user what you needed and why." ;;
  *) deny "guard-bash.sh: unknown or missing profile '$PROFILE' (hook misconfigured)" ;;
esac

deny_form() { deny "DENIED: $1
Allowed command forms (one plain command; outside single quotes no ; & | \` \$ < > \\ \" or newlines):
$FORMS
$FOOTER"; }

[ -n "$cmd" ] || deny_form "empty command, or it could not be read from the tool call (neither jq nor node is available)"

# ---- tokenizer: fills TOK (words, quotes removed) and TQ (1 if the word contained single quotes)
TOK=(); TQ=()
cur=""; have=0; quoted=0; inq=0; i=0; n=${#cmd}
while [ "$i" -lt "$n" ]; do
  c="${cmd:$i:1}"; i=$((i + 1))
  if [ "$inq" -eq 1 ]; then
    if [ "$c" = "'" ]; then inq=0; else cur="$cur$c"; fi
    continue
  fi
  case "$c" in
    "'") inq=1; have=1; quoted=1 ;;
    " ") if [ "$have" -eq 1 ]; then TOK+=("$cur"); TQ+=("$quoted"); cur=""; have=0; quoted=0; fi ;;
    [A-Za-z0-9_./=:,+@%-]) cur="$cur$c"; have=1 ;;
    "~")
      if [ "$have" -eq 0 ] && { [ "$i" -ge "$n" ] || [ "${cmd:$i:1}" = "/" ]; }; then cur="$HOME"; have=1
      else deny_form "'~' is only accepted at the start of a word as ~/"; fi ;;
    $'\n'|$'\r') deny_form "the command contains a newline outside single quotes" ;;
    '"') deny_form "double quotes are not accepted; use single quotes" ;;
    *) deny_form "the command contains the character '$c' outside single quotes (chaining, substitution, redirects, globs)" ;;
  esac
done
[ "$inq" -eq 0 ] || deny_form "single quotes are not balanced"
if [ "$have" -eq 1 ]; then TOK+=("$cur"); TQ+=("$quoted"); fi
nt=${#TOK[@]}
[ "$nt" -gt 0 ] || deny_form "empty command"

# ---- helpers
in_root() {   # in_root <path> [base-dir]: the physical path is inside ~/kmp-agents
  local t; t="$(resolve_path "$1" "${2:-$cwd}")"
  case "$t/" in "$ROOT"/*) return 0 ;; esac
  return 1
}

git_args_ok() {   # arguments of an allowed read-only git command
  local t
  for t in "$@"; do
    case "$t" in --output*|--no-index|--ext-diff|-O*) deny_form "git: argument '$t' is not allowed" ;; esac
    printf '%s' "$t" | grep -Eq '^[-A-Za-z0-9_.:=/~^@,%+]+$' || deny_form "git: invalid argument '$t'"
  done
}

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }

search_find() {
  local k=1 npaths=0 t
  while [ "$k" -lt "$nt" ]; do
    t="${TOK[$k]}"
    case "$t" in -*) break ;; esac
    in_root "$t" || deny_form "find: path '$t' is outside ~/kmp-agents"
    npaths=$((npaths + 1)); k=$((k + 1))
  done
  [ "$npaths" -gt 0 ] || deny_form "find: give at least one path inside ~/kmp-agents"
  while [ "$k" -lt "$nt" ]; do
    t="${TOK[$k]}"; k=$((k + 1))
    case "$t" in
      -name|-iname|-path|-ipath)
        [ "$k" -lt "$nt" ] || deny_form "find: $t needs a pattern"; k=$((k + 1)) ;;
      -type)
        [ "$k" -lt "$nt" ] || deny_form "find: -type needs f or d"
        case "${TOK[$k]}" in f|d) ;; *) deny_form "find: -type accepts only f or d" ;; esac
        k=$((k + 1)) ;;
      -maxdepth|-mindepth)
        [ "$k" -lt "$nt" ] && is_num "${TOK[$k]}" || deny_form "find: $t needs a number"; k=$((k + 1)) ;;
      -print) ;;
      *) deny_form "find: '$t' is not allowed (only -name -iname -path -ipath -type -maxdepth -mindepth -print)" ;;
    esac
  done
}

search_grep() {
  local k=1 t q have_pat=0 npaths=0
  while [ "$k" -lt "$nt" ]; do
    t="${TOK[$k]}"; q="${TQ[$k]}"; k=$((k + 1))
    case "$t" in
      -[ABC])
        [ "$k" -lt "$nt" ] && is_num "${TOK[$k]}" || deny_form "grep: $t needs a number"; k=$((k + 1)) ;;
      -[ABC][0-9]*)
        is_num "${t:2}" || deny_form "grep: invalid flag '$t'" ;;
      --include=?*|--exclude=?*|--exclude-dir=?*) ;;
      -*)
        printf '%s' "$t" | grep -Eq '^-[rRnilLcwxEFHhosI]+$' || deny_form "grep: flag '$t' is not allowed" ;;
      *)
        if [ "$have_pat" -eq 0 ]; then
          [ "$q" = 1 ] || deny_form "grep: the pattern must be in single quotes"
          have_pat=1
        else
          in_root "$t" || deny_form "grep: path '$t' is outside ~/kmp-agents"
          npaths=$((npaths + 1))
        fi ;;
    esac
  done
  [ "$have_pat" -eq 1 ] || deny_form "grep: no pattern"
  [ "$npaths" -gt 0 ] || deny_form "grep: give at least one path inside ~/kmp-agents"
}

search_ls() {
  local k=1 t npaths=0
  while [ "$k" -lt "$nt" ]; do
    t="${TOK[$k]}"; k=$((k + 1))
    case "$t" in
      -*) printf '%s' "$t" | grep -Eq '^-[lahtrRFSdA1]+$' || deny_form "ls: flag '$t' is not allowed" ;;
      *)  in_root "$t" || deny_form "ls: path '$t' is outside ~/kmp-agents"; npaths=$((npaths + 1)) ;;
    esac
  done
  if [ "$npaths" -eq 0 ]; then in_root "." || deny_form "ls: the current directory is outside ~/kmp-agents"; fi
}

# ---- absolute forms of the project paths: rewrite to the canonical relative form when they resolve to exactly the same place
# (only exact targets: the five project dirs, the gradlew of shared/android, desktop pom.xml, the ios .xcodeproj)
canonicalize() {
  local k t r out="" w
  for ((k = 0; k < nt; k++)); do
    t="${TOK[$k]}"
    if [ "${TQ[$k]}" = 0 ] && [ "${t:0:1}" = "/" ]; then
      r="$(resolve_path "$t" "$cwd")"
      case "$r" in
        "$ROOT/KMP_template_shared"|"$ROOT/KMP_template_android"|"$ROOT/KMP_template_desktop"|"$ROOT/KMP_template_ios"|"$ROOT/KMP_template_web"|\
        "$ROOT/KMP_template_desktop/pom.xml"|"$ROOT/KMP_template_ios/KMP_template_ios.xcodeproj")
          TOK[$k]="${r#"$ROOT/"}" ;;
        "$ROOT/KMP_template_shared/gradlew"|"$ROOT/KMP_template_android/gradlew")
          TOK[$k]="./${r#"$ROOT/"}" ;;
      esac
    fi
    w="${TOK[$k]}"; [ "${TQ[$k]}" = 1 ] && w="'$w'"
    out="${out:+$out }$w"
  done
  cmd="$out"
}

# ---- search: the same for every profile
case "${TOK[0]}" in
  find) search_find; exit 0 ;;
  grep) search_grep; exit 0 ;;
  ls)   search_ls;   exit 0 ;;
esac

# ---- orchestrator
orchestrator_profile() {
  local r repo d ok sub k t p npaths=0
  case "${TOK[0]}" in */*)
    r="$(resolve_path "${TOK[0]}" "$cwd")"
    case "$r" in
      "$ROOT/scripts/propagate.sh"|"$ROOT/scripts/check-propagation.sh"|"$ROOT/scripts/hooks/test-guards.sh")
        [ "$nt" -eq 1 ] || deny_form "${TOK[0]} takes no arguments"; return 0 ;;
      "$ROOT/scripts/build-all.sh")
        if [ "$nt" -eq 1 ] || { [ "$nt" -eq 2 ] && [ "${TOK[1]}" = "--propagate" ]; }; then return 0; fi
        deny_form "build-all.sh accepts only --propagate" ;;
    esac ;;
  esac

  if [ "${TOK[0]}" = git ] && [ "$nt" -ge 4 ] && [ "${TOK[1]}" = "-C" ]; then
    repo="$(resolve_path "${TOK[2]}" "$cwd")"; ok=0
    for d in "" /KMP_template_shared /KMP_template_android /KMP_template_desktop /KMP_template_ios /KMP_template_web; do
      [ "$repo" = "$ROOT$d" ] && ok=1
    done
    [ "$ok" -eq 1 ] || deny_form "git -C: '${TOK[2]}' is not one of the six repositories (. or KMP_template_<shared|android|desktop|ios|web>)"
    sub="${TOK[3]}"; k=4
    case "$sub" in
      status|diff|log|show)
        while [ "$k" -lt "$nt" ]; do git_args_ok "${TOK[$k]}"; k=$((k + 1)); done
        return 0 ;;
      add|restore)
        while [ "$k" -lt "$nt" ]; do
          t="${TOK[$k]}"; k=$((k + 1))
          [ "$t" = "--" ] && continue
          case "$t" in -*|:*|*'*'*|*'?'*|*'['*) deny_form "git $sub: argument '$t' is not allowed (explicit paths only)" ;; esac
          p="$(resolve_path "$t" "$repo")"
          case "$p/" in "$repo"/*) ;; *) deny_form "git $sub: path '$t' is outside the repository" ;; esac
          [ "$p" != "$repo" ] || deny_form "git $sub: give explicit paths, not the repository root"
          npaths=$((npaths + 1))
        done
        [ "$npaths" -gt 0 ] || deny_form "git $sub: no paths"
        return 0 ;;
      commit)
        if [ "$nt" -eq 6 ] && [ "${TOK[4]}" = "-m" ] && [ "${TQ[5]}" = 1 ] && [ -n "${TOK[5]}" ]; then return 0; fi
        deny_form "git commit: only  commit -m '<message in single quotes>'" ;;
      *) deny_form "git $sub is not allowed" ;;
    esac
  fi
  deny_form "command is not in the orchestrator profile whitelist: $cmd"
}

# smoke_script <name> <allowed-arg|-|...>: TOK[0] is exactly ~/kmp-agents/scripts/smoke/<name> with one of the listed args
# ("-" = no argument). Returns 0 if allowed, 1 if TOK[0] is a different command, denies if it is this script with wrong args.
smoke_script() {
  local name="$1" a; shift
  case "${TOK[0]}" in */*) ;; *) return 1 ;; esac
  [ "$(resolve_path "${TOK[0]}" "$cwd")" = "$ROOT/scripts/smoke/$name" ] || return 1
  for a in "$@"; do
    if [ "$a" = "-" ]; then [ "$nt" -eq 1 ] && return 0
    else [ "$nt" -eq 2 ] && [ "${TOK[1]}" = "$a" ] && return 0; fi
  done
  deny_form "$name: arguments are not allowed ($* )"
}

own_git() {   # own_git <repo-dir>: git -C <repo> status|diff|log [args]
  local g="git -C $1" sub rest
  for sub in status diff log; do
    if [[ "$cmd" == "$g $sub" || "$cmd" == "$g $sub "* ]]; then
      rest="${cmd#"$g $sub"}"; git_args_ok $rest; return 0
    fi
  done
  return 1
}

in_list() {   # in_list <word> <allowed...>
  local w="$1" a; shift
  for a in "$@"; do [ "$a" = "$w" ] && return 0; done
  return 1
}

platform_profile() {
  local k ntask=0 off=0 t
  case "$PROFILE" in
    android)
      own_git KMP_template_android && return 0
      if [ "${TOK[0]}" = "./KMP_template_android/gradlew" ] && [ "$nt" -ge 4 ] && [ "${TOK[1]}" = "-p" ] && [ "${TOK[2]}" = "KMP_template_android" ]; then
        for ((k = 3; k < nt; k++)); do
          t="${TOK[$k]}"
          case "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" in *publish*) deny "DENIED: task '$t' contains publish. Publishing is done only by the orchestrator.
Put it in NOT_DONE of your report." ;; esac
          if in_list "$t" -q --console=plain; then :
          elif in_list "$t" assembleDebug :app:assembleDebug testDebugUnitTest :app:testDebugUnitTest help; then ntask=$((ntask + 1))
          else deny_form "gradle: '$t' is not allowed (tasks: assembleDebug :app:assembleDebug testDebugUnitTest :app:testDebugUnitTest help; flags: -q --console=plain)"; fi
        done
        [ "$ntask" -gt 0 ] || deny_form "gradle: give at least one task"
        return 0
      fi
      deny_form "command is not in the android profile whitelist: $cmd" ;;
    desktop)
      own_git KMP_template_desktop && return 0
      if smoke_script desktop-smoke.sh -; then return 0; fi
      if [ "${TOK[0]}" = mvn ] && [ "$nt" -ge 4 ] && [ "${TOK[1]}" = "-f" ] && [ "${TOK[2]}" = "KMP_template_desktop/pom.xml" ]; then
        for ((k = 3; k < nt; k++)); do
          t="${TOK[$k]}"
          if [ "$t" = "-o" ]; then off=1
          elif [ "$t" = "-q" ]; then :
          elif in_list "$t" compile test; then ntask=$((ntask + 1))
          else deny_form "mvn: '$t' is not allowed (flags: -o -q; phases: compile test)"; fi
        done
        [ "$off" -eq 1 ] || deny_form "mvn: -o (offline) is required"
        [ "$ntask" -gt 0 ] || deny_form "mvn: give a phase (compile or test)"
        return 0
      fi
      deny_form "command is not in the desktop profile whitelist: $cmd" ;;
    web)
      own_git KMP_template_web && return 0
      if smoke_script web-smoke.sh browser node; then return 0; fi
      if [ "${TOK[0]}" = npm ] && [ "$nt" -ge 3 ] && [ "${TOK[1]}" = "--prefix" ] && [ "${TOK[2]}" = "KMP_template_web" ]; then
        if [ "$nt" -eq 5 ] && [ "${TOK[3]}" = run ] && [ "${TOK[4]}" = build ]; then return 0; fi
        if [ "$nt" -eq 5 ] && [ "${TOK[3]}" = install ] && [ "${TOK[4]}" = "--ignore-scripts" ]; then return 0; fi
      fi
      deny_form "command is not in the web profile whitelist: $cmd" ;;
  esac
}

[ "$PROFILE" = orchestrator ] || canonicalize

# ---- per-profile commands (these match the raw command string; the tokenizer above has already vetted the characters)
case "$PROFILE" in
  orchestrator) orchestrator_profile; exit 0 ;;
  shared)
    if smoke_script web-smoke.sh browser node; then exit 0; fi
    gp="./KMP_template_shared/gradlew -p KMP_template_shared"
    if [[ "$cmd" == "$gp" || "$cmd" == "$gp "* ]]; then
      rest="${cmd#"$gp"}"
      for t in $rest; do
        case "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" in
          *publish*) deny "DENIED: task '$t' contains publish. Publishing artifacts (publishToMavenLocal etc.) is done only by the orchestrator via propagate.sh.
If you need it, put it in NOT_DONE of your report and return it to the orchestrator." ;;
        esac
        case "$t" in
          --console=plain|--stacktrace|--info|--warn|--offline|--rerun-tasks|--continue|--parallel|-q|--quiet|-x) ;;
          -*) deny_form "gradle: flag '$t' is not allowed" ;;
          *)  printf '%s' "$t" | grep -Eq '^:?[A-Za-z][A-Za-z0-9_.:-]*$' || deny_form "gradle: invalid argument '$t'" ;;
        esac
      done
      exit 0
    fi
    gg="git -C KMP_template_shared"
    for sub in status diff log; do
      if [[ "$cmd" == "$gg $sub" || "$cmd" == "$gg $sub "* ]]; then
        rest="${cmd#"$gg $sub"}"; git_args_ok $rest; exit 0
      fi
    done
    deny_form "command is not in the shared profile whitelist: $cmd"
    ;;
  android|desktop|web) platform_profile; exit 0 ;;
  ios)
    xp="xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj"
    if [[ "$cmd" == "$xp" || "$cmd" == "$xp "* ]]; then
      rest="${cmd#"$xp"}"
      chunks=(
        '^ -scheme KMP_template_ios'
        '^ -configuration (Debug|Release)'
        "^ -destination 'generic/platform=iOS Simulator'"
        '^ -derivedDataPath /tmp/[A-Za-z0-9_.-]+'
        '^ CODE_SIGNING_ALLOWED=NO'
        '^ -quiet'
        '^ (build|clean|test)'
      )
      while [ -n "$rest" ]; do
        matched=0
        for re in "${chunks[@]}"; do
          if [[ "$rest" =~ $re ]]; then
            len=${#BASH_REMATCH[0]}; tail="${rest:$len}"
            if [ -z "$tail" ] || [ "${tail:0:1}" = " " ]; then rest="$tail"; matched=1; break; fi
          fi
        done
        [ "$matched" -eq 1 ] || deny_form "xcodebuild: invalid arguments:$rest"
      done
      exit 0
    fi
    gg="git -C KMP_template_ios"
    for sub in status diff log; do
      if [[ "$cmd" == "$gg $sub" || "$cmd" == "$gg $sub "* ]]; then
        rest="${cmd#"$gg $sub"}"; git_args_ok $rest; exit 0
      fi
    done
    deny_form "command is not in the ios profile whitelist: $cmd"
    ;;
esac
