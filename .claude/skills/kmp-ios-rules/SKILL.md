---
name: kmp-ios-rules
description: Rules for ios-agent. Preloaded into the agent; not for manual use
---

# Rules for working in KMP_template_ios

A SwiftUI app. shared is used as `import shared` (`SystemInfo().getInfo()` in `ContentView.swift`).
Edit only inside `~/kmp-agents/KMP_template_ios`.

## Searching
Use `find` and `grep` through Bash (there is no Glob/Grep on this machine), with the pattern in single quotes, for example `grep -rn 'SystemInfo' KMP_template_ios`.
Paths must be inside `~/kmp-agents`; no `-exec`, `-delete`, pipes or double quotes.

## How shared arrives
The prebuilt binary `Packages/KMPTemplate/shared.xcframework` is attached as a local SPM package (`Package.swift`, `.binaryTarget`). CocoaPods is gone.
Do not touch `Packages/KMPTemplate/.shared-rev` or the XCFramework itself: the orchestrator updates them through `propagate.sh`.
Look up the shared API in `Packages/KMPTemplate/shared.xcframework/ios-arm64/shared.framework/Headers/shared.h`; if the symbol you need is missing, that is a task for shared-agent - put it in `NOT_DONE`.

## Build (from ~/kmp-agents)
Build with `-quiet`:
`xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj -scheme KMP_template_ios -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kmp-ios-dd CODE_SIGNING_ALLOWED=NO -quiet build`
(Release: add `-configuration Release`.) There is no test target.

## Note
Kotlin/Native strings are stored in the binary as UTF-16LE: plain `strings` does not find them.

## Running commands
- `xcodebuild -project KMP_template_ios/KMP_template_ios.xcodeproj -scheme KMP_template_ios -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kmp-ios-dd CODE_SIGNING_ALLOWED=NO -quiet build`

Run it exactly like this. No pipes, redirects, tail, 2>&1 or echo $? — the Bash tool already returns the output and reports a non-zero exit as an error.

Skill-canary: SKILL-IOS-3F8FM1
