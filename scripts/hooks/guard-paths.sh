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
[ -n "$file" ] || deny "ОТКАЗ: не удалось определить путь файла из вызова инструмента (или нет jq/node). Правка заблокирована."

cwd="$(json_get cwd)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(resolve_path "$HOME/kmp-agents/$DIR" "/")"
target="$(resolve_path "$file" "$cwd")"

case "$target/" in
  "$root"/*) exit 0 ;;
esac

deny "ОТКАЗ: $file (→ $target) вне разрешённого каталога $root.
Тебе разрешены правки только внутри ~/kmp-agents/$DIR. Правки в другом проекте делает его агент
(shared → shared-agent, ios → ios-agent), а правки харнесса и скриптов — оркестратор.
Не пытайся обойти запрет: опиши нужную правку в поле NOT_DONE своего отчёта и верни его оркестратору."
