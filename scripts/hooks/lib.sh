# Shared helpers for the guard hooks (sourced, bash 3.2 compatible).

# log_denial <message>: append one JSON line to logs/hook-denials.jsonl (override: $HOOK_DENIAL_LOG). Never affects the decision:
# every failure is ignored. Uses globals set by the hooks: HOOK_SCOPE (profile or directory), INPUT (hook JSON).
log_denial() {
  (
    command -v jq >/dev/null 2>&1 || exit 0
    local log="${HOOK_DENIAL_LOG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/logs/hook-denials.jsonl}"
    local at tool target
    at="$(json_get agent_type)"; tool="$(json_get tool_name)"
    target="$(json_get tool_input.command)"
    [ -n "$target" ] || target="$(json_get tool_input.file_path)"
    [ -n "$target" ] || target="$(json_get tool_input.notebook_path)"
    mkdir -p "$(dirname "$log")"
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg at "${at:-main}" --arg scope "${HOOK_SCOPE:-?}" --arg tool "$tool" \
       --arg target "${target:0:300}" --arg reason "$(printf '%s' "$1" | head -n 1 | cut -c1-300)" \
       '{ts:$ts, agent_type:$at, scope:$scope, tool_name:$tool, target:$target, reason:$reason}' >> "$log"
  ) >/dev/null 2>&1 || true
}

# deny <message>: print the message to stderr, log the denial and block the tool call (exit 2).
deny() { log_denial "$*"; printf '%s\n' "$*" >&2; exit 2; }

# json_get <dotted.path>: read a string field from $INPUT. jq if installed, else node, else nothing (callers fail closed).
json_get() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r --arg p "$1" 'getpath($p | split(".")) // empty' 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    printf '%s' "$INPUT" | node -e '
      let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
        try { let v = JSON.parse(d); for (const k of process.argv[1].split(".")) v = v == null ? v : v[k];
              if (v != null) process.stdout.write(String(v)); } catch (e) {}
      });' "$1"
  fi
}

# resolve_path <path> <base-dir>: absolute physical path (handles "..", ".", symlinks, not-yet-existing tails).
resolve_path() {
  local path="$1" base="$2" cur="/" comp rest n=0 target
  case "$path" in /*) ;; *) path="$base/$path" ;; esac
  rest="$path"
  while [ -n "$rest" ]; do
    n=$((n + 1)); [ "$n" -gt 200 ] && { printf '%s' "/__unresolvable__"; return; }
    rest="${rest#/}"                       # drop leading slashes
    [ -z "$rest" ] && break
    comp="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    case "$comp" in
      ""|".") continue ;;
      "..") cur="$(dirname "$cur")"; continue ;;
    esac
    if [ -L "${cur%/}/$comp" ]; then
      target="$(readlink "${cur%/}/$comp")"
      case "$target" in
        /*) cur="/"; rest="$target${rest:+/$rest}" ;;
        *)  rest="$target${rest:+/$rest}" ;;
      esac
    else
      cur="${cur%/}/$comp"
    fi
  done
  printf '%s' "$cur"
}
