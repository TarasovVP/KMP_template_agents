---
name: kmp-shared-rules
description: Rules for shared-agent. Preloaded into the agent; not for manual use
---

# Rules for working in KMP_template_shared

The `:shared` module (Kotlin 2.2.0, AGP 8.11.1, Gradle 8.13). Targets: android (release), iosX64/iosArm64/iosSimulatorArm64 (static framework `shared`), jvm, js (IR, `binaries.library()` only).
Edit only inside `~/kmp-agents/KMP_template_shared`. Publishing (`publish*`), propagate and commits are done by the orchestrator.

## CocoaPods
Shared supports CocoaPods through its podspec for external consumers; KMP_template_ios connects shared via SPM; do not touch the podspec or the `cocoapods` block without a separate task.

## Searching
Use `find` and `grep` through Bash (there is no Glob/Grep on this machine), with the pattern in single quotes, for example `grep -rn 'getInfo' KMP_template_shared/shared/src`.
Paths must be inside `~/kmp-agents`; no `-exec`, `-delete`, pipes or double quotes.

## Check every new public API against the four exports
1. **JS.** Classes from commonMain are not visible outside. A top-level facade with `@JsExport` in `jsMain` is needed, like `getInfo()` and `getDeviceModel()` in `SystemInfoFacade.kt`.
   If shared gains a new JS dependency, it must be declared in `KMP_template_web/package.json` (you cannot edit it), otherwise `propagate.sh` will fail - put it in `NOT_DONE` and mention it in the report.
2. **Swift.** Check how the name and `suspend` look in the ObjC header (`shared/build/XCFrameworks/release/shared.xcframework/ios-arm64/shared.framework/Headers/shared.h` after a build): `swift_name`, `suspend` becomes a completionHandler/async, default values, sealed hierarchies and generics are lost or changed.
3. **Java.** Desktop calls `shared-jvm` from Java: default parameters need `@JvmOverloads`, top-level functions end up in a `<File>Kt` class (use `@file:JvmName` if needed).
4. **Android.** Code in `androidMain`/commonMain, `minSdk` 24, `compileSdk` 36; the consumer uses `shared-android`.
In the report, mark each of the four exports as verified or not, and by what.

## Build (from ~/kmp-agents, always with -p)
- everything: `./KMP_template_shared/gradlew -p KMP_template_shared assemble`
- XCFramework: `... assembleSharedReleaseXCFramework`; JS library: `... :shared:jsBrowserProductionLibraryDistribution`
There are no tests in the module yet: verification is a successful `assemble` plus inspecting the header/`.d.ts`.

## Verify JS behaviour after any edit in jsMain or commonMain
Compiling is not enough: rebuild the JS distribution and run both web smoke variants (no `propagate.sh` needed, the web project reads the build directory through a symlink):
1. `./KMP_template_shared/gradlew -p KMP_template_shared :shared:jsBrowserProductionLibraryDistribution`
2. `scripts/smoke/web-smoke.sh browser` (a stubbed `navigator`, expects `getDeviceModel()` = "Browser")
3. `scripts/smoke/web-smoke.sh node` (plain Node, expects "Node")
Put the output of both runs in `VERIFIED_BY`. A failing variant is a behaviour defect: fix it in shared or, if the cause is outside your directory, put it in `NOT_DONE`.

## Note
Kotlin/Native strings are stored in the binary as UTF-16LE: plain `strings` does not find them.

## Running commands
- `./KMP_template_shared/gradlew -p KMP_template_shared assemble`

Run it exactly like this. No pipes, redirects, tail, 2>&1 or echo $? — the Bash tool already returns the output and reports a non-zero exit as an error.

Skill-canary: SKILL-SHARED-MF3279
