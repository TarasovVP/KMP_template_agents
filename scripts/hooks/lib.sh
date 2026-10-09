# Shared helpers for the guard hooks (sourced, bash 3.2 compatible).

# deny <message>: print the message to stderr and block the tool call (exit 2).
deny() { printf '%s\n' "$*" >&2; exit 2; }

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
