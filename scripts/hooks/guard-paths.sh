#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit: allow only paths inside ~/kmp-agents/<allowed-dir>.
# Usage: guard-paths.sh <allowed-dir>      (stdin: hook JSON)
set -u
. "$(dirname "$0")/lib.sh"

DIR="${1:-}"
[ -n "$DIR" ] || deny "guard-paths.sh: allowed directory argument is missing (hook misconfigured)"

INPUT="$(cat)"
file="$(json_get tool_input.file_path)"
[ -n "$file" ] || file="$(json_get tool_input.notebook_path)"
[ -n "$file" ] || deny "DENIED: could not determine the file path from the tool call (or neither jq nor node is available). Edit blocked."

cwd="$(json_get cwd)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(resolve_path "$HOME/kmp-agents/$DIR" "/")"
target="$(resolve_path "$file" "$cwd")"

case "$target/" in
  "$root"/*) exit 0 ;;
esac

deny "DENIED: $file (-> $target) is outside the allowed directory $root.
You may only edit inside ~/kmp-agents/$DIR. Edits in another project belong to that project's agent
(shared -> shared-agent, ios -> ios-agent); edits to the harness and scripts belong to the orchestrator.
Do not try to work around this: describe the needed edit in the NOT_DONE field of your report and return it to the orchestrator."
