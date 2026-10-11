---
name: kmp-web-rules
description: Rules for web-agent. Preloaded into the agent; not for manual use
---

# Rules for working in KMP_template_web

A Vite page. Edit only inside `~/kmp-agents/KMP_template_web`.

## Searching
Use `find` and `grep` through Bash (there is no Glob/Grep on this machine), with the pattern in single quotes, for example `grep -n 'getInfo' KMP_template_web/node_modules/KMP_template_shared-shared/KMP_template_shared-shared.d.ts`.
Paths must be inside `~/kmp-agents`; no `-exec`, `-delete`, pipes or double quotes.

## Calling shared
`app.js` imports named exports from `'KMP_template_shared-shared'`. Only what shared exports through its `@JsExport` facade is available: check the names in `node_modules/KMP_template_shared-shared/KMP_template_shared-shared.d.ts` before using one. If the symbol is missing, put it in `NOT_DONE` for shared-agent.
The package is a symlink to shared's build directory, so `preserveSymlinks` in `vite.config.js` must stay as it is.

## JS dependencies
If shared added a JS dependency, declare it in this project's `package.json` and run `npm --prefix KMP_template_web install --ignore-scripts` (only with that flag).

## Build and smoke (from ~/kmp-agents)
- `npm --prefix KMP_template_web run build`
- both smoke variants: `scripts/smoke/web-smoke.sh browser` and `scripts/smoke/web-smoke.sh node`. Put their output in `VERIFIED_BY`.

## Running commands
- `npm --prefix KMP_template_web run build`
- `scripts/smoke/web-smoke.sh browser`
- `scripts/smoke/web-smoke.sh node`

Run it exactly like this. No pipes, redirects, tail, 2>&1 or echo $? — the Bash tool already returns the output and reports a non-zero exit as an error.

Skill-canary: SKILL-WEB-6TH5GK
