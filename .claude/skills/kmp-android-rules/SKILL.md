---
name: kmp-android-rules
description: Rules for android-agent. Preloaded into the agent; not for manual use
---

# Rules for working in KMP_template_android

A Jetpack Compose app. Edit only inside `~/kmp-agents/KMP_template_android`.

## Searching
Use `find` and `grep` through Bash (there is no Glob/Grep on this machine), with the pattern in single quotes, for example `grep -rn 'SystemInfo' KMP_template_android/app/src`.
Paths must be inside `~/kmp-agents`; no `-exec`, `-delete`, pipes or double quotes.

## Where shared is called
Shared is used from one place: `app/src/main/java/com/vnteam/kmp_template_android/MainActivity.kt` (`SystemInfo().getInfo()`).
Rely only on the shared API that already exists; if you need a symbol shared does not have, put it in `NOT_DONE` for shared-agent.

## How shared arrives
From mavenLocal (`~/.m2`): `shared-android:1.0`. Only the orchestrator publishes it (`publishToMavenLocal` via `propagate.sh`); you cannot and must not publish.

## Build and tests (from ~/kmp-agents)
`./KMP_template_android/gradlew -p KMP_template_android :app:assembleDebug :app:testDebugUnitTest --console=plain`
Allowed tasks: `assembleDebug`, `:app:assembleDebug`, `testDebugUnitTest`, `:app:testDebugUnitTest`, `help`; flags `-q`, `--console=plain`.

## Known warning
The `jvmTarget` warning during the build is known. Do not touch it without a separate task.

## Running commands
- `./KMP_template_android/gradlew -p KMP_template_android :app:assembleDebug :app:testDebugUnitTest --console=plain`

Run it exactly like this. No pipes, redirects, tail, 2>&1 or echo $? — the Bash tool already returns the output and reports a non-zero exit as an error.

Skill-canary: SKILL-ANDROID-HJ193Y
