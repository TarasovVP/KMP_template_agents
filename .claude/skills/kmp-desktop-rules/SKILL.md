---
name: kmp-desktop-rules
description: Rules for desktop-agent. Preloaded into the agent; not for manual use
---

# Rules for working in KMP_template_desktop

A JavaFX app (Java 17, Maven). The whole UI is in `src/main/java/Main.java`. Edit only inside `~/kmp-agents/KMP_template_desktop`.

## Searching
Use `find` and `grep` through Bash (there is no Glob/Grep on this machine), with the pattern in single quotes, for example `grep -rn 'SystemInfo' KMP_template_desktop/src`.
Paths must be inside `~/kmp-agents`; no `-exec`, `-delete`, pipes or double quotes.

## Calling shared
Shared comes from mavenLocal (`~/.m2`) as `shared-jvm:1.0`; only the orchestrator publishes it. A Kotlin class is used from Java as a normal class: `new SystemInfo().getXxx()` (import `com.tarasovvp.kmptemplate.SystemInfo`).
Rely only on the shared API that already exists; if you need a symbol shared does not have, put it in `NOT_DONE` for shared-agent.

## Do not touch
The JavaFX platform `mac-aarch64` (`javafx.platform` in `pom.xml`) is set on purpose.

## Build and smoke (from ~/kmp-agents)
- Build offline and quiet: `mvn -f KMP_template_desktop/pom.xml -o -q compile` (`test` is also allowed).
- Behaviour smoke after the build: `scripts/smoke/desktop-smoke.sh` (prints `getInfo()` and `getDeviceModel()`, which must start with "Desktop ("). Put its output in `VERIFIED_BY`.

Skill-canary: SKILL-DESKTOP-G47083
