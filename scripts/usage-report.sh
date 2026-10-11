#!/usr/bin/env bash
# Token usage of a main session and its subagents, from the Claude Code transcripts in ~/.claude/projects/.
# Usage: scripts/usage-report.sh <session-id | path to the main session .jsonl>
# Reads <session>.jsonl and <session>/subagents/agent-*.jsonl (+ agent-*.meta.json, whose agentType names the agent).
# One API message is written to the transcript as several lines (one per content block) with the same usage,
# so usage is counted once per message.id, taking the maximum of each field over its lines (the first line is written while
# streaming starts and has a near-zero output_tokens). "calls" = tool_use blocks (counted once per tool_use id). No cost conversion.
set -u
arg="${1:-}"
[ -n "$arg" ] || { echo "usage: usage-report.sh <session-id | path to main session .jsonl>" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "usage-report.sh needs node" >&2; exit 2; }
if [ -f "$arg" ]; then main="$arg"
else
  main=""
  for f in "$HOME"/.claude/projects/*/"$arg".jsonl; do [ -f "$f" ] && main="$f" && break; done
  [ -n "$main" ] || { echo "session '$arg' not found under ~/.claude/projects/*/" >&2; exit 2; }
fi
exec node -e '
const fs = require("fs"), path = require("path");
const main = process.argv[1];
const dir = main.replace(/\.jsonl$/, "") + "/subagents";
const rows = new Map();   // "agent\tmodel" -> {in,out,cw,cr,calls,runs:Set}
function add(agent, run, file) {
  const msgs = new Map(), seenTool = new Set();   // message.id -> {model, in, out, cw, cr} (field-wise max over all lines)
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line) continue;
    let e; try { e = JSON.parse(line); } catch { continue; }
    if (e.type !== "assistant" || !e.message) continue;
    const m = e.message, u = m.usage, model = m.model || "?";
    const key0 = agent + "\t" + model;
    if (!rows.has(key0)) rows.set(key0, { agent, model, in: 0, out: 0, cw: 0, cr: 0, calls: 0, runs: new Set() });
    const r = rows.get(key0); r.runs.add(run);
    if (u && m.id) {
      const x = msgs.get(m.id) || (msgs.set(m.id, { model, in: 0, out: 0, cw: 0, cr: 0 }), msgs.get(m.id));
      x.in = Math.max(x.in, u.input_tokens || 0); x.out = Math.max(x.out, u.output_tokens || 0);
      x.cw = Math.max(x.cw, u.cache_creation_input_tokens || 0); x.cr = Math.max(x.cr, u.cache_read_input_tokens || 0);
    }
    for (const c of Array.isArray(m.content) ? m.content : []) {
      if (c.type === "tool_use" && c.id && !seenTool.has(c.id)) { seenTool.add(c.id); r.calls++; }
    }
  }
  for (const x of msgs.values()) {
    const r = rows.get(agent + "\t" + x.model);
    r.in += x.in; r.out += x.out; r.cw += x.cw; r.cr += x.cr;
  }
}
// main session: named by its agent-setting entry (e.g. orchestrator), else "main"
let mainName = "main";
for (const line of fs.readFileSync(main, "utf8").split("\n")) {
  if (line.includes("\"agent-setting\"")) { try { const e = JSON.parse(line); if (e.agentSetting) mainName = e.agentSetting; } catch {} break; }
}
add(mainName + " (main)", main, main);
if (fs.existsSync(dir)) {
  for (const f of fs.readdirSync(dir).filter(f => /^agent-.*\.jsonl$/.test(f)).sort()) {
    let name = "unknown";
    try { name = JSON.parse(fs.readFileSync(path.join(dir, f.replace(/\.jsonl$/, ".meta.json")), "utf8")).agentType || name; } catch {}
    add(name, f, path.join(dir, f));
  }
}
const list = [...rows.values()];
const fmt = n => n.toLocaleString("en-US").replace(/,/g, " ");
const head = ["agent", "model", "input", "output", "cache write", "cache read", "calls"];
const body = list.map(r => [r.agent + (r.runs.size > 1 ? " x" + r.runs.size : ""), r.model, fmt(r.in), fmt(r.out), fmt(r.cw), fmt(r.cr), String(r.calls)]);
const tot = list.reduce((a, r) => ({ in: a.in + r.in, out: a.out + r.out, cw: a.cw + r.cw, cr: a.cr + r.cr, calls: a.calls + r.calls }), { in: 0, out: 0, cw: 0, cr: 0, calls: 0 });
body.push(["TOTAL", "", fmt(tot.in), fmt(tot.out), fmt(tot.cw), fmt(tot.cr), String(tot.calls)]);
const w = head.map((h, i) => Math.max(h.length, ...body.map(r => r[i].length)));
const line = r => r.map((c, i) => i < 2 ? c.padEnd(w[i]) : c.padStart(w[i])).join(" | ");
console.log("session: " + main);
console.log(line(head)); console.log(w.map(n => "-".repeat(n)).join("-+-"));
body.forEach((r, i) => { if (i === body.length - 1) console.log(w.map(n => "-".repeat(n)).join("-+-")); console.log(line(r)); });
' "$main"
