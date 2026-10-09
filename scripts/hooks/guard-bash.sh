#!/usr/bin/env bash
# PreToolUse hook for Bash: single plain commands only, matched against a per-profile whitelist.
# Usage: guard-bash.sh <shared|ios>      (stdin: hook JSON)
set -u
set -f   # no globbing while we split the command into words
. "$(dirname "$0")/lib.sh"

PROFILE="${1:-}"
INPUT="$(cat)"
cmd="$(json_get tool_input.command)"

FOOTER="Публикация (publish*), propagate.sh, build-all.sh, коммиты и правки через shell (sed -i, tee, перенаправления) тебе недоступны.
Если нужна такая операция — не обходи запрет: впиши её в NOT_DONE своего отчёта, её выполнит оркестратор."

case "$PROFILE" in
  shared) FORMS="  ./KMP_template_shared/gradlew -p KMP_template_shared <таски и флаги> (таски без 'publish')
  git -C KMP_template_shared status|diff|log [аргументы]" ;;
  ios)    FORMS="  xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj [-scheme KMP_template_ios] [-configuration Debug|Release]
      [-destination 'generic/platform=iOS Simulator'] [-derivedDataPath /tmp/<имя>] [CODE_SIGNING_ALLOWED=NO] [build|clean|test]
  git -C KMP_template_ios status|diff|log [аргументы]" ;;
  *) deny "guard-bash.sh: unknown or missing profile '$PROFILE' (hook misconfigured)" ;;
esac

deny_form() { deny "ОТКАЗ: $1
Разрешённые формы команд (одна простая команда, без ; & | \` \$ < > \\ и переводов строк):
$FORMS
$FOOTER"; }

[ -n "$cmd" ] || deny_form "пустая команда или не удалось прочитать её из вызова (нет jq/node)"
case "$cmd" in *$'\n'*|*$'\r'*) deny_form "команда содержит перевод строки" ;; esac
if printf '%s' "$cmd" | LC_ALL=C grep -q '[;&|`<>$\\]'; then
  deny_form "команда содержит запрещённый символ (цепочки, подстановки, перенаправления)"
fi

git_args_ok() {   # remaining args of an allowed read-only git command
  local t
  for t in "$@"; do
    case "$t" in --output*|--no-index|--ext-diff|-O*) deny_form "git: аргумент '$t' запрещён" ;; esac
    printf '%s' "$t" | LC_ALL=C grep -Eq '^[-A-Za-z0-9_.:=/~^@,%+]+$' || deny_form "git: недопустимый аргумент '$t'"
  done
}

case "$PROFILE" in
  shared)
    gp="./KMP_template_shared/gradlew -p KMP_template_shared"
    if [[ "$cmd" == "$gp" || "$cmd" == "$gp "* ]]; then
      rest="${cmd#"$gp"}"
      for t in $rest; do
        case "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" in
          *publish*) deny "ОТКАЗ: таск '$t' содержит publish. Публикация артефактов (publishToMavenLocal и т. п.) — только оркестратор через propagate.sh.
Если в этом есть нужда, впиши это в NOT_DONE своего отчёта и верни его оркестратору." ;;
        esac
        case "$t" in
          --console=plain|--stacktrace|--info|--warn|--offline|--rerun-tasks|--continue|--parallel|-q|--quiet|-x) ;;
          -*) deny_form "gradle: флаг '$t' не разрешён" ;;
          *)  printf '%s' "$t" | LC_ALL=C grep -Eq '^:?[A-Za-z][A-Za-z0-9_.:-]*$' || deny_form "gradle: недопустимый аргумент '$t'" ;;
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
    deny_form "команда не входит в белый список профиля shared: $cmd"
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
        [ "$matched" -eq 1 ] || deny_form "xcodebuild: недопустимые аргументы:$rest"
      done
      exit 0
    fi
    gg="git -C KMP_template_ios"
    for sub in status diff log; do
      if [[ "$cmd" == "$gg $sub" || "$cmd" == "$gg $sub "* ]]; then
        rest="${cmd#"$gg $sub"}"; git_args_ok $rest; exit 0
      fi
    done
    deny_form "команда не входит в белый список профиля ios: $cmd"
    ;;
esac
