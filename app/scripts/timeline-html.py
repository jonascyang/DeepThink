#!/usr/bin/env python3
"""Turns `tmd-store-stress jsonl` output into a self-contained HTML timeline showing every field of every record.

    swift run tmd-store-stress jsonl path/to/thinkmyday.sqlite > records.jsonl
    python3 scripts/timeline-html.py records.jsonl timeline.html "标题"

The page holds the recorded text in plain form. Keep it on this Mac; do not commit or upload it.
"""
import html
import json
import sys

src, out = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else "原始记录"
rows = [json.loads(line) for line in open(src, encoding="utf-8") if line.strip()]
data = json.dumps(rows, ensure_ascii=False).replace("</", "<\\/")

page = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root {
  --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --line: rgba(0,0,0,0.08);
  --content: #0062cc; --focus: #5e5ce6; --layout: #8e8e93; --gap: #c93400; --hidden: #8e8e93; --presence: #248a3d;
  --chip: rgba(0,0,0,0.05); --code: #f2f2f4;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1c1c1e; --card: #2c2c2e; --text: #f5f5f7; --muted: #98989d; --line: rgba(255,255,255,0.1);
    --content: #409cff; --focus: #7d7aff; --gap: #ff9f0a; --presence: #30d158; --chip: rgba(255,255,255,0.08); --code: #1c1c1e;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 13px/1.5 -apple-system, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif; }
header { position: sticky; top: 0; z-index: 2; background: color-mix(in srgb, var(--bg) 88%, transparent);
  backdrop-filter: blur(20px); border-bottom: 1px solid var(--line); padding: 14px 20px 10px; }
h1 { font-size: 17px; margin: 0 0 2px; }
.sub { color: var(--muted); }
.controls { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 10px; }
.chip { border: 0; border-radius: 6px; padding: 3px 9px; background: var(--chip); color: var(--text); font: inherit; cursor: pointer; }
.chip[aria-pressed="false"] { opacity: 0.45; }
.chip i { font-style: normal; display: inline-block; width: 8px; height: 8px; border-radius: 4px; margin-right: 5px; }
select, input[type=search] { font: inherit; padding: 3px 8px; border-radius: 6px; border: 1px solid var(--line);
  background: var(--card); color: var(--text); }
input[type=search] { width: 220px; }
main { max-width: 1100px; margin: 0 auto; padding: 12px 20px 60px; }
.day { margin: 18px 0 8px; font-weight: 600; }
.rec { display: grid; grid-template-columns: 92px 1fr; gap: 12px; padding: 10px 0; border-bottom: 1px solid var(--line); }
.time { font: 12px/1.4 ui-monospace, "SF Mono", Menlo, monospace; color: var(--muted); }
.time b { color: var(--text); font-weight: 500; display: block; font-size: 13px; }
.card { background: var(--card); border-radius: 10px; padding: 10px 12px; box-shadow: 0 0 0 1px var(--line); min-width: 0; }
.head { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
.kind { font-size: 11px; font-weight: 600; padding: 1px 7px; border-radius: 5px; color: #fff; }
.headline { font-weight: 600; }
table.fields { border-collapse: collapse; margin-top: 6px; width: 100%; }
table.fields td { padding: 1px 10px 1px 0; vertical-align: top; overflow-wrap: anywhere; }
table.fields td:first-child { color: var(--muted); white-space: nowrap; width: 1%; font: 12px ui-monospace, Menlo, monospace; }
.lines { margin-top: 8px; padding: 8px 10px; background: var(--code); border-radius: 8px; white-space: pre-wrap; overflow-wrap: anywhere; }
.lines .n { color: var(--muted); font: 11px ui-monospace, Menlo, monospace; margin-right: 8px; user-select: none; }
table.wins { border-collapse: collapse; margin-top: 8px; width: 100%; font-size: 12px; }
table.wins th, table.wins td { text-align: left; padding: 3px 8px 3px 0; border-bottom: 1px solid var(--line); }
table.wins th { color: var(--muted); font-weight: 500; }
details { margin-top: 6px; }
summary { color: var(--muted); cursor: pointer; font-size: 12px; }
pre { margin: 6px 0 0; padding: 8px 10px; background: var(--code); border-radius: 8px; overflow-x: auto; font: 11.5px/1.45 ui-monospace, Menlo, monospace; }
.hidden-note { color: var(--muted); }
.empty { color: var(--muted); padding: 40px 0; text-align: center; }
@media (max-width: 640px) {
  header { padding: 12px 16px 8px; } main { padding: 8px 16px 40px; }
  .rec { grid-template-columns: 1fr; gap: 4px; } .time b { display: inline; margin-right: 6px; }
  input[type=search] { width: 100%; }
}
</style>
</head>
<body>
<header>
  <h1>__TITLE__</h1>
  <div class="sub" id="summary"></div>
  <div class="controls" id="kinds"></div>
  <div class="controls">
    <select id="app"><option value="">全部 App</option></select>
    <select id="screen"><option value="">全部屏幕</option></select>
    <input type="search" id="q" placeholder="搜索文字、标题、网址">
    <button class="chip" id="expand" aria-pressed="false">展开原始 JSON</button>
  </div>
</header>
<main id="list"></main>
<script>
const rows = __DATA__;
const KINDS = {
  windowText: ["窗口文字", "var(--content)"], focus: ["焦点", "var(--focus)"], layout: ["布局", "var(--layout)"],
  gap: ["缺口", "var(--gap)"], presence: ["状态", "var(--presence)"],
  activity: ["操作", "#bf5af2"], file: ["文件", "#ff9f0a"],
};
const SIDE = { full: "整屏", left: "左", right: "右", center: "中" };
const placeLabel = p => !p ? "" : (p.screen < 0 ? "屏幕外" : `屏幕 ${p.screen + 1} ${SIDE[p.side] || p.side}`) + " · ";
const FILESRC = { document: "打开的文件", finderFolder: "访达所在文件夹", finderSelection: "访达选中" };
const GAP = { noAccessibilityPermission: "没有辅助功能权限", readFailed: "读取失败", unreadable: "读不到文字，OCR 也没有结果",
  noAccessibilityWindow: "辅助功能里找不到这个窗口", blocked: "不看名单里的窗口", neverRead: "永不读取的窗口" };
const STATE = { idle: "无输入", active: "恢复输入", asleep: "睡眠", awake: "唤醒", locked: "锁屏", unlocked: "解锁",
  recordingStarted: "开始记录", recordingStopped: "停止记录" };
const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const clock = t => new Date(t * 1000).toLocaleTimeString("zh-CN", { hour12: false });
const date = t => new Date(t * 1000).toLocaleDateString("zh-CN", { month: "long", day: "numeric", weekday: "short" });
const dur = s => s < 60 ? `${Math.round(s)} 秒` : s < 3600 ? `${Math.floor(s / 60)} 分 ${Math.round(s % 60)} 秒` : `${Math.floor(s / 3600)} 小时 ${Math.round(s % 3600 / 60)} 分`;

const days = Object.fromEntries(rows.filter(r => r.type === "day").map(d => [d.id, d]));
const records = rows.filter(r => r.type === "record").sort((a, b) => a.at - b.at);
const apps = [...new Set(records.map(r => r.body && r.body.appName).filter(Boolean))].sort();
const screenOf = r => r.body && r.body.place ? r.body.place.screen : null;
const counts = {};
records.forEach(r => counts[r.kind] = (counts[r.kind] || 0) + 1);
const on = Object.fromEntries(Object.keys(KINDS).map(k => [k, true]));

if (records.length) {
  const span = records[records.length - 1].at - records[0].at;
  document.getElementById("summary").textContent =
    `${records.length} 条记录 · ${clock(records[0].at)}–${clock(records[records.length - 1].at)}（${dur(span)}） · ${apps.length} 个 App`;
}
const kindBox = document.getElementById("kinds");
for (const [k, [label, color]] of Object.entries(KINDS)) {
  const b = document.createElement("button");
  b.className = "chip"; b.setAttribute("aria-pressed", "true");
  b.innerHTML = `<i style="background:${color}"></i>${label} ${counts[k] || 0}`;
  b.onclick = () => { on[k] = !on[k]; b.setAttribute("aria-pressed", on[k]); render(); };
  kindBox.appendChild(b);
}
const appSel = document.getElementById("app");
apps.forEach(a => appSel.add(new Option(a, a)));
appSel.onchange = render;
const screenSel = document.getElementById("screen");
[...new Set(records.map(screenOf).filter(s => s !== null && s >= 0))].sort().forEach(s => screenSel.add(new Option(`屏幕 ${s + 1}`, s)));
screenSel.onchange = render;
document.getElementById("q").oninput = render;
const expandBtn = document.getElementById("expand");
expandBtn.onclick = () => { const v = expandBtn.getAttribute("aria-pressed") !== "true"; expandBtn.setAttribute("aria-pressed", v);
  document.querySelectorAll("details.raw").forEach(d => d.open = v); };

function headline(r) {
  const b = r.body || {};
  switch (r.kind) {
    case "windowText": return `${placeLabel(b.place)}${b.appName || "?"}${b.title ? " — " + b.title : ""}`;
    case "focus": return placeLabel(b.place) + (b.hidden ? `焦点切到${GAP[b.hidden] || b.hidden}：${b.appName || "?"}` : `焦点：${b.appName || "?"}${b.title ? " — " + b.title : ""}`);
    case "gap": return (GAP[b.reason] || b.reason) + (b.appName ? `：${b.appName}` : "");
    case "activity": return `${placeLabel(b.place)}操作 · ${b.appName}（${clock(b.from)}–${clock(b.to)}）`;
    case "file": return `${FILESRC[b.source] || b.source}：${b.name}`;
    case "presence": return STATE[b.state] || b.state;
    case "layout": return `${(b.screens || []).length} 块屏幕，${(b.windows || []).length} 个可见窗口`;
    default: return r.kind;
  }
}

function fields(obj, skip) {
  const tr = Object.entries(obj).filter(([k]) => !skip.includes(k)).map(([k, v]) => {
    let s = v;
    if (v === null) s = "—";
    else if (typeof v === "boolean") s = v ? "是" : "否";
    else if (["since", "from", "to", "created", "downloadedAt"].includes(k) && typeof v === "number") s = `${clock(v)}（${v}）`;
    else if (k === "place" && v) s = `${placeLabel(v).replace(" · ", "")} · x ${v.frame[0][0]}, y ${v.frame[0][1]}, ${v.frame[1][0]} × ${v.frame[1][1]}`;
    else if (typeof v === "object") s = JSON.stringify(v);
    return `<tr><td>${esc(k)}</td><td>${esc(s)}</td></tr>`;
  });
  return tr.length ? `<table class="fields">${tr.join("")}</table>` : "";
}

function body(r) {
  const b = r.body;
  if (typeof b !== "object" || b === null) return `<div class="lines">${esc(b)}</div>`;
  let h = "";
  if (r.kind === "layout") {
    h += fields(b, ["windows", "screens"]);
    h += `<table class="wins"><tr><th>屏幕</th><th>x, y</th><th>宽 × 高</th></tr>` + (b.screens || []).map((s, i) =>
      `<tr><td>${i + 1}</td><td>${s[0][0]}, ${s[0][1]}</td><td>${s[1][0]} × ${s[1][1]}</td></tr>`).join("") + `</table>`;
    h += `<table class="wins"><tr><th>#</th><th>窗口</th><th>App</th><th>bundleID</th><th>屏幕</th><th>x, y</th><th>宽 × 高</th><th>可见</th><th>焦点</th><th>不读</th></tr>` +
      (b.windows || []).map((w, i) => `<tr><td>${i + 1}</td><td>${w.windowID}</td><td>${esc(w.appName || "—")}</td><td>${esc(w.bundleID || "—")}</td>
        <td>${w.screen < 0 ? "屏幕外" : w.screen + 1}</td><td>${w.frame[0][0]}, ${w.frame[0][1]}</td><td>${w.frame[1][0]} × ${w.frame[1][1]}</td>
        <td>${Math.round(w.visible * 100)}%</td><td>${w.focused ? "●" : ""}</td><td>${esc(w.hidden ? (GAP[w.hidden] || w.hidden) : "")}</td></tr>`).join("") + `</table>`;
  } else {
    h += fields(b, ["added"]);
    if (Array.isArray(b.added)) {
      h += `<div class="lines">${b.added.map((l, i) => `<span class="n">${String(i + 1).padStart(3)}</span>${esc(l)}`).join("\\n") || '<span class="hidden-note">（没有新的行）</span>'}</div>`;
    }
  }
  return h;
}

function render() {
  const q = document.getElementById("q").value.trim().toLowerCase();
  const app = appSel.value;
  const list = document.getElementById("list");
  const scr = screenSel.value;
  const shown = records.filter(r => on[r.kind] !== false && (!app || (r.body && r.body.appName === app))
    && (scr === "" || screenOf(r) === null || String(screenOf(r)) === scr)
    && (!q || JSON.stringify(r.body).toLowerCase().includes(q)));
  if (!shown.length) { list.innerHTML = '<div class="empty">没有符合条件的记录</div>'; return; }
  let html = "", lastDay = null, prev = null;
  for (const r of shown) {
    if (r.dayID !== lastDay) {
      const d = days[r.dayID];
      lastDay = r.dayID; prev = null;
      html += `<div class="day">复盘日 ${d ? date(d.startedAt) + " " + clock(d.startedAt) + (d.endedAt ? "–" + clock(d.endedAt) : " 起 · 记录中") : r.dayID}</div>`;
    }
    const d = days[r.dayID];
    const [label, color] = KINDS[r.kind] || [r.kind, "var(--muted)"];
    const since = d ? `开启后 ${dur(r.at - d.startedAt)}` : "";
    const gap = prev ? `距上条 ${dur(r.at - prev)}` : "";
    prev = r.at;
    html += `<div class="rec">
      <div class="time"><b>${clock(r.at)}</b>${since}<br>${gap}</div>
      <div class="card">
        <div class="head"><span class="kind" style="background:${color}">${label}</span><span class="headline">${esc(headline(r))}</span></div>
        ${body(r)}
        <details class="raw"${expandBtn.getAttribute("aria-pressed") === "true" ? " open" : ""}><summary>原始 JSON · 记录 ${r.id}</summary><pre>${esc(JSON.stringify(r, null, 2))}</pre></details>
      </div>
    </div>`;
  }
  list.innerHTML = html;
}
render();
</script>
</body>
</html>
"""

with open(out, "w", encoding="utf-8") as f:
    f.write(page.replace("__TITLE__", html.escape(title)).replace("__DATA__", data))
print(out)
