# kmp-agents

Five independent git repositories. `KMP_template_shared` is the KMP module; the other four are native consumers.
The `~/kmp-agents` directory is itself a repository too (the harness: `scripts/`, `.claude/agents/`, `logs/`).

| Directory | What it is | Build |
|---|---|---|
| `KMP_template_shared` | KMP module `:shared`: Kotlin 2.2.0, targets android/ios/jvm/js. The only source of the contract. | Gradle |
| `KMP_template_android` | Android app (Compose) | Gradle |
| `KMP_template_desktop` | JavaFX app, Java 17 | Maven |
| `KMP_template_ios` | SwiftUI app | Xcode |
| `KMP_template_web` | Vite page | npm |

## Contract and expect/actual
The public API lives in `KMP_template_shared/shared/src/commonMain` (currently `SystemInfo().getInfo()`).
Platform parts are wired through `expect fun getPlatform()` with `actual` in `androidMain`, `iosMain`, `jvmMain`, `jsMain`.
Each consumer calls shared from a single place (`MainActivity.kt`, `Main.java`, `ContentView.swift`, `app.js`).

## How shared reaches the platforms
- android, desktop: via `~/.m2` (mavenLocal): `shared-android:1.0`, `shared-jvm:1.0`.
- ios: a prebuilt `shared.xcframework` in `KMP_template_ios/Packages/KMPTemplate`, attached as a local SPM package. No CocoaPods.
- web: the `shared/build/dist/js/productionLibrary` directory is symlinked into `node_modules`; the distribution's JS dependencies must be declared in web's `package.json`.

All of this is laid out by `scripts/propagate.sh`. Agents do not run it.

## Roles and workflow
1. `orchestrator` - breaks the task down, drives the process, runs the scripts, verifies reports and commits. Does not edit code.
2. `shared-agent` - edits only `KMP_template_shared`.
3. `ios-agent` - edits only `KMP_template_ios` (sonnet).
4. `android-agent` - edits only `KMP_template_android` (sonnet).
5. `desktop-agent` - edits only `KMP_template_desktop` (haiku).
6. `web-agent` - edits only `KMP_template_web` (haiku).
Order: orchestrator -> shared-agent (only if the contract changes) -> `propagate.sh` (only then) -> platform agents (in parallel when independent) -> `build-all.sh` -> verify reports against `git diff` and `build-all` -> commits.
If a task does not change shared, shared-agent and `propagate.sh` are skipped.
An agent that needs an edit outside its directory does not work around the restriction; it writes the edit into `NOT_DONE` of its report.

## Orchestrator only
`scripts/propagate.sh`, `scripts/build-all.sh`, `scripts/check-propagation.sh`, any `publish*`, any `git commit`, changes under `~/kmp-agents/scripts` and `.claude`.
Platform agents verify their work only by building their own project and return a report in the format from their definition.
