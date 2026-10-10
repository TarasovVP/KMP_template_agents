#!/usr/bin/env bash
# PreToolUse hook for Bash: single plain commands only, matched against a per-profile whitelist.
# Usage: guard-bash.sh <shared|ios>      (stdin: hook JSON)
set -u
set -f   # no globbing while we split the command into words
. "$(dirname "$0")/lib.sh"

PROFILE="${1:-}"
INPUT="$(cat)"
cmd="$(json_get tool_input.command)"

FOOTER="Publishing (publish*), propagate.sh, build-all.sh, commits and edits through the shell (sed -i, tee, redirects) are not available to you.
If you need such an operation, do not work around the restriction: put it in NOT_DONE of your report and the orchestrator will do it."

case "$PROFILE" in
  shared) FORMS="  ./KMP_template_shared/gradlew -p KMP_template_shared <tasks and flags> (no 'publish' tasks)
  git -C KMP_template_shared status|diff|log [args]" ;;
  ios)    FORMS="  xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj [-scheme KMP_template_ios] [-configuration Debug|Release]
      [-destination 'generic/platform=iOS Simulator'] [-derivedDataPath /tmp/<name>] [CODE_SIGNING_ALLOWED=NO] [build|clean|test]
  git -C KMP_template_ios status|diff|log [args]" ;;
  *) deny "guard-bash.sh: unknown or missing profile '$PROFILE' (hook misconfigured)" ;;
esac

deny_form() { deny "DENIED: $1
Allowed command forms (one plain command, no ; & | \` \$ < > \\ or newlines):
$FORMS
$FOOTER"; }

[ -n "$cmd" ] || deny_form "empty command, or it could not be read from the tool call (neither jq nor node is available)"
case "$cmd" in *$'\n'*|*$'\r'*) deny_form "the command contains a newline" ;; esac
if printf '%s' "$cmd" | LC_ALL=C grep -q '[;&|`<>$\\]'; then
  deny_form "the command contains a forbidden character (chaining, substitution, redirects)"
fi

git_args_ok() {   # remaining args of an allowed read-only git command
  local t
  for t in "$@"; do
    case "$t" in --output*|--no-index|--ext-diff|-O*) deny_form "git: argument '$t' is not allowed" ;; esac
    printf '%s' "$t" | LC_ALL=C grep -Eq '^[-A-Za-z0-9_.:=/~^@,%+]+$' || deny_form "git: invalid argument '$t'"
  done
}

case "$PROFILE" in
  shared)
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
          *)  printf '%s' "$t" | LC_ALL=C grep -Eq '^:?[A-Za-z][A-Za-z0-9_.:-]*$' || deny_form "gradle: invalid argument '$t'" ;;
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
        '^ (build|clean|test)'
      )
      while [ -n "$rest" ]; do
        matched=0
        for re in "${chunks[@]}"; do
          if [[ "$rest" =~ $re ]]; then
            n=${#BASH_REMATCH[0]}; tail="${rest:$n}"
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
