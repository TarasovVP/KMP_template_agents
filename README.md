# KMP_template_agents

A harness and a set of [Claude Code](https://claude.com/claude-code) agents for the five repositories used in
[KMP: Integrating into Native Projects](https://medium.com/@vptarasov/kmp-integrating-into-native-projects-f0f35091706d):

| Repository | What it is |
|---|---|
| [KMP_template_shared](https://github.com/TarasovVP/KMP_template_shared) | the Kotlin Multiplatform module `:shared` (the only source of the contract) |
| [KMP_template_android](https://github.com/TarasovVP/KMP_template_android) | Android app (Compose) |
| [KMP_template_ios](https://github.com/TarasovVP/KMP_template_ios) | iOS app (SwiftUI) |
| [KMP_template_desktop](https://github.com/TarasovVP/KMP_template_desktop) | desktop app (JavaFX) |
| [KMP_template_web](https://github.com/TarasovVP/KMP_template_web) | web page (Vite) |

An orchestrator agent drives a task through `shared -> propagate -> platform agents -> build-all -> commits`;
every agent is confined to its own directory by hooks.

> Detailed walkthrough: [AI Agents for a KMP Developer](https://levelup.gitconnected.com/ai-agents-for-a-kmp-developer-82af4e8851a9)

## Layout

The five repositories are cloned **inside** the harness root; the scripts address them as subdirectories.
They are ignored by the harness git (see `.gitignore`) and stay independent repositories, with no submodules.

```
KMP_template_agents/            <- this repository
  .claude/agents, .claude/skills
  scripts/
  KMP_template_shared/          <- separate clones, ignored here
  KMP_template_android/
  KMP_template_ios/
  KMP_template_desktop/
  KMP_template_web/
```

## Install

```
git clone https://github.com/TarasovVP/KMP_template_agents.git
cd KMP_template_agents && scripts/clone-projects.sh
```

`clone-projects.sh` skips directories that already exist and needs nothing but `git`.
The harness does not pin project versions: it was checked against the current `main` of the five repositories on the publication date (2026-10-11).

## Requirements

macOS, Xcode, JDK 17, Maven, Node 18+, Android SDK, Claude Code. (`jq` is used by the hooks when installed; otherwise `node` is.)

## Run

From the harness root:

```
claude --agent orchestrator
```

## Scripts

- `scripts/clone-projects.sh` - clones the five repositories into the harness root (skips existing ones).
- `scripts/propagate.sh` - builds and publishes shared (`publishToMavenLocal`, XCFramework, JS library), resolves the desktop Maven dependencies online, copies the XCFramework into the iOS package (keyed by a content revision of shared's iOS inputs) and writes the contract fingerprint.
- `scripts/build-all.sh [--propagate]` - builds and smoke-tests all five projects and prints a result table.
- `scripts/check-propagation.sh` - end-to-end check that a marker added to shared's `commonMain` reaches android, desktop, ios and web, and disappears when reverted.
- `scripts/smoke/desktop-smoke.sh` - behaviour smoke for desktop (jshell calls `SystemInfo` methods).
- `scripts/smoke/web-smoke.sh <browser|node>` - behaviour smoke for web (imports the shared package and calls it).
- `scripts/usage-report.sh <session-id|path>` - token usage per agent and model from Claude Code transcripts.
- `scripts/hooks/test-guards.sh` - tests of the guard hooks.

## Agents

| Agent | Model | What it can do |
|---|---|---|
| `orchestrator` | opus | Breaks the task down, starts the other agents, runs the scripts, checks reports against `git diff`, commits. Does not edit code. Bash restricted to scripts, read-only git, `git add/restore/commit`, search. |
| `shared-agent` | opus | Edits `KMP_template_shared` only; builds with Gradle (no `publish*`); runs the web smoke. |
| `ios-agent` | sonnet | Edits `KMP_template_ios` only; builds with `xcodebuild`. |
| `android-agent` | sonnet | Edits `KMP_template_android` only; builds with Gradle (no `publish*`). |
| `desktop-agent` | haiku | Edits `KMP_template_desktop` only; builds with Maven (offline) and runs the desktop smoke. |
| `web-agent` | haiku | Edits `KMP_template_web` only; `npm run build`, `npm install --ignore-scripts`, web smoke. |

Platform rules live in preloaded skills (`.claude/skills/kmp-<platform>-rules`). Every agent returns a report in a fixed format
(`STATUS, FILES_CHANGED, VERIFIED_BY, CONTRACT, RISKS, NOT_DONE`); an edit outside its directory goes into `NOT_DONE`, never around the hook.

## Hooks

- `scripts/hooks/guard-paths.sh <dir>` (Edit, Write, NotebookEdit) allows writes only inside `~/kmp-agents/<dir>`; paths are normalised (`..`, symlinks).
- `scripts/hooks/guard-bash.sh <profile>` (Bash) allows one plain command per call from a per-profile whitelist:
  no chaining, redirects or substitution outside single quotes, double quotes rejected, `find`/`grep`/`ls` limited to the harness root and read-only forms,
  platform builds and smokes in their own project, `publish*` and commits only for the orchestrator. The orchestrator profile lets calls of the five known subagents through (their own hooks check them).
- Every denial appends one JSON line to `logs/hook-denials.jsonl` (time, agent type, profile, tool, command or path, reason). Logging never changes a decision.

## License

MIT, see [LICENSE](LICENSE).
