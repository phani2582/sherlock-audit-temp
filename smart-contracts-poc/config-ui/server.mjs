#!/usr/bin/env node
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CONFIG_FILE = join(__dirname, '..', 'script', 'config', 'networks.json');
const PORT = parseInt(process.env.CONFIG_PORT || '3031', 10);
const BASE_PATH = process.env.BASE_PATH || '';

// --- data helpers ---

function readAll() {
  if (!existsSync(CONFIG_FILE)) return {};
  return JSON.parse(readFileSync(CONFIG_FILE, 'utf-8'));
}

function writeAll(data) {
  writeFileSync(CONFIG_FILE, JSON.stringify(data, null, 2) + '\n');
}

// --- HTML ---

function renderHTML() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Config Manager</title>
<style>
  :root {
    --bg: #0d1117; --bg2: #161b22; --bg3: #21262d;
    --border: #30363d; --text: #e6edf3; --text2: #8b949e;
    --accent: #58a6ff; --accent2: #388bfd; --green: #3fb950;
    --red: #f85149; --yellow: #d29922;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; background: var(--bg); color: var(--text); display: flex; height: 100vh; overflow: hidden; }

  .sidebar { width: 220px; min-width: 220px; background: var(--bg2); border-right: 1px solid var(--border); display: flex; flex-direction: column; }
  .sidebar-header { padding: 16px; border-bottom: 1px solid var(--border); font-weight: 600; font-size: 14px; color: var(--accent); letter-spacing: 0.5px; }
  .network-list { flex: 1; overflow-y: auto; padding: 8px 0; }
  .network-item { padding: 8px 16px; cursor: pointer; font-size: 13px; display: flex; align-items: center; gap: 8px; transition: background 0.15s; }
  .network-item:hover { background: var(--bg3); }
  .network-item.active { background: var(--bg3); color: var(--accent); font-weight: 600; }
  .network-item .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); flex-shrink: 0; }
  .network-item .dot.partial { background: var(--yellow); }
  .network-item .dot.empty { background: var(--text2); }
  .network-item .section-count { margin-left: auto; font-size: 11px; color: var(--text2); }

  .main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
  .toolbar { padding: 12px 20px; border-bottom: 1px solid var(--border); display: flex; align-items: center; gap: 12px; background: var(--bg2); }
  .toolbar h2 { font-size: 16px; font-weight: 600; }
  .toolbar .badge { font-size: 11px; background: var(--bg3); border: 1px solid var(--border); border-radius: 12px; padding: 2px 8px; color: var(--text2); }

  .tabs { display: flex; gap: 0; border-bottom: 1px solid var(--border); background: var(--bg2); padding: 0 20px; }
  .tab { padding: 10px 16px; font-size: 13px; cursor: pointer; border-bottom: 2px solid transparent; color: var(--text2); transition: all 0.15s; }
  .tab:hover { color: var(--text); }
  .tab.active { color: var(--accent); border-bottom-color: var(--accent); font-weight: 600; }

  .content { flex: 1; overflow-y: auto; padding: 20px; }
  .editor { width: 100%; min-height: 300px; background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 16px; font-family: 'SF Mono', 'Fira Code', monospace; font-size: 13px; line-height: 1.6; color: var(--text); resize: vertical; outline: none; tab-size: 2; }
  .editor:focus { border-color: var(--accent); }
  .editor.invalid { border-color: var(--red); }

  .btn-row { display: flex; gap: 8px; margin-top: 12px; align-items: center; }
  .btn { padding: 6px 16px; font-size: 13px; border-radius: 6px; border: 1px solid var(--border); cursor: pointer; font-weight: 500; transition: all 0.15s; }
  .btn-primary { background: var(--accent2); color: #fff; border-color: var(--accent2); }
  .btn-primary:hover { background: var(--accent); }
  .btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
  .btn-secondary { background: var(--bg3); color: var(--text); }
  .btn-secondary:hover { background: var(--border); }
  .btn-danger { background: transparent; color: var(--red); border-color: var(--red); }
  .btn-danger:hover { background: var(--red); color: #fff; }
  .status { font-size: 12px; color: var(--text2); margin-left: 8px; }
  .status.ok { color: var(--green); }
  .status.err { color: var(--red); }

  .deploy-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; }
  .deploy-card { background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 16px; cursor: pointer; transition: border-color 0.15s; }
  .deploy-card:hover { border-color: var(--accent); }
  .deploy-card h3 { font-size: 14px; margin-bottom: 12px; }
  .field { margin-bottom: 8px; }
  .field-label { font-size: 11px; color: var(--text2); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 2px; }
  .field-value { font-family: monospace; font-size: 12px; word-break: break-all; }
  .field-value.set { color: var(--accent); }
  .field-value.unset { color: var(--text2); font-style: italic; }

  .empty-state { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: var(--text2); gap: 8px; }

  ::-webkit-scrollbar { width: 8px; }
  ::-webkit-scrollbar-track { background: var(--bg); }
  ::-webkit-scrollbar-thumb { background: var(--bg3); border-radius: 4px; }
</style>
</head>
<body>
<div class="sidebar">
  <div class="sidebar-header">CONFIG MANAGER</div>
  <div class="network-list" id="networkList"></div>
</div>
<div class="main">
  <div class="toolbar">
    <h2 id="toolbarTitle">Overview</h2>
    <span class="badge" id="toolbarBadge"></span>
  </div>
  <div class="tabs" id="tabsBar" style="display:none"></div>
  <div class="content" id="content">
    <div class="empty-state">Loading...</div>
  </div>
</div>

<script>
const BASE = window.location.pathname.replace(/\\/$/, '') + '/';
let D = {};
let sel = '__overview';
let tab = null;

async function load() {
  D = await (await fetch(BASE + 'api/config')).json();
  render();
}

function render() {
  renderSidebar();
  if (sel === '__overview') renderOverview();
  else renderNetwork();
}

function renderSidebar() {
  const el = document.getElementById('networkList');
  const nets = Object.keys(D).sort();
  let h = item('__overview', 'Overview', '');
  for (const n of nets) {
    const d = D[n].deployments || {};
    const hasAddr = Object.values(d).some(v => v && v !== '0x0000000000000000000000000000000000000000');
    const sections = Object.keys(D[n]).length;
    const dot = hasAddr ? '' : sections > 1 ? 'partial' : 'empty';
    h += item(n, n, dot, sections);
  }
  el.innerHTML = h;
}

function item(key, label, dot, count) {
  const cls = sel === key ? ' active' : '';
  const dotHtml = dot !== undefined && dot !== '' ? '<span class="dot ' + dot + '"></span>' : key !== '__overview' ? '<span class="dot"></span>' : '';
  const countHtml = count ? '<span class="section-count">' + count + '</span>' : '';
  return '<div class="network-item' + cls + '" onclick="go(\\'' + key + '\\')">' + dotHtml + label + countHtml + '</div>';
}

function go(key) { sel = key; tab = null; render(); }

function renderOverview() {
  document.getElementById('toolbarTitle').textContent = 'Overview';
  const nets = Object.keys(D).sort();
  document.getElementById('toolbarBadge').textContent = nets.length + ' networks';
  document.getElementById('tabsBar').style.display = 'none';

  let h = '<div class="deploy-grid">';
  for (const n of nets) {
    const dep = D[n].deployments || {};
    const orc = D[n].oracle || {};
    const acc = D[n].access || {};
    h += '<div class="deploy-card" onclick="go(\\'' + n + '\\')"><h3>' + n + '</h3>';
    for (const [k, v] of Object.entries(dep)) {
      const ok = v && v !== '0x0000000000000000000000000000000000000000';
      h += '<div class="field"><div class="field-label">' + k + '</div><div class="field-value ' + (ok ? 'set' : 'unset') + '">' + (ok ? v : 'not deployed') + '</div></div>';
    }
    if (orc.maxTimeDrift !== undefined)
      h += '<div class="field"><div class="field-label">oracle drift</div><div class="field-value">' + orc.maxTimeDrift + 's</div></div>';
    const ac = (acc.admins || []).length;
    h += '<div class="field"><div class="field-label">admins</div><div class="field-value ' + (ac ? 'set' : 'unset') + '">' + (ac || 'none') + '</div></div>';
    const extras = Object.keys(D[n]).filter(k => !['deployments','oracle','access'].includes(k));
    if (extras.length)
      h += '<div class="field"><div class="field-label">extra</div><div class="field-value">' + extras.join(', ') + '</div></div>';
    h += '</div>';
  }
  h += '</div>';
  document.getElementById('content').innerHTML = h;
}

function renderNetwork() {
  const cfg = D[sel] || {};
  const sections = Object.keys(cfg).sort();
  document.getElementById('toolbarTitle').textContent = sel;
  document.getElementById('toolbarBadge').textContent = sections.length + ' sections';
  const tb = document.getElementById('tabsBar');
  tb.style.display = 'flex';
  if (!tab || !sections.includes(tab)) tab = sections[0] || null;
  tb.innerHTML = sections.map(s =>
    '<div class="tab' + (tab === s ? ' active' : '') + '" onclick="setTab(\\'' + s + '\\')">' + s + '</div>'
  ).join('');
  renderEditor();
}

function setTab(t) {
  tab = t;
  document.querySelectorAll('.tab').forEach(el => el.classList.toggle('active', el.textContent === t));
  renderEditor();
}

function renderEditor() {
  if (!tab) { document.getElementById('content').innerHTML = '<div class="empty-state">No sections</div>'; return; }
  const data = D[sel][tab];
  const json = JSON.stringify(data, null, 2);
  const rows = Math.max(json.split('\\n').length + 2, 10);
  document.getElementById('content').innerHTML =
    '<textarea class="editor" id="ed" rows="' + rows + '">' + esc(json) + '</textarea>' +
    '<div class="btn-row">' +
    '<button class="btn btn-primary" id="saveBtn" onclick="save()" disabled>Save</button>' +
    '<button class="btn btn-secondary" onclick="reset()">Reset</button>' +
    '<button class="btn btn-secondary" onclick="fmt()">Format</button>' +
    '<span class="status" id="st"></span></div>';
  const ed = document.getElementById('ed');
  ed._orig = json;
  ed.addEventListener('input', check);
  ed.addEventListener('keydown', e => {
    if (e.key === 'Tab') { e.preventDefault(); const s=e.target.selectionStart; e.target.value=e.target.value.substring(0,s)+'  '+e.target.value.substring(e.target.selectionEnd); e.target.selectionStart=e.target.selectionEnd=s+2; e.target.dispatchEvent(new Event('input')); }
  });
}

function esc(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

function check() {
  const ed = document.getElementById('ed'), btn = document.getElementById('saveBtn'), st = document.getElementById('st');
  const changed = ed.value !== ed._orig;
  let valid = true;
  try { JSON.parse(ed.value); ed.classList.remove('invalid'); } catch { valid = false; ed.classList.add('invalid'); }
  btn.disabled = !changed || !valid;
  st.textContent = !valid ? 'Invalid JSON' : changed ? 'Unsaved changes' : '';
  st.className = 'status' + (!valid ? ' err' : '');
}

function reset() { const ed = document.getElementById('ed'); ed.value = ed._orig; ed.dispatchEvent(new Event('input')); }
function fmt() { const ed = document.getElementById('ed'); try { ed.value = JSON.stringify(JSON.parse(ed.value), null, 2); ed.dispatchEvent(new Event('input')); } catch {} }

async function save() {
  const ed = document.getElementById('ed'), st = document.getElementById('st'), btn = document.getElementById('saveBtn');
  let data; try { data = JSON.parse(ed.value); } catch { return; }
  btn.disabled = true; st.textContent = 'Saving...'; st.className = 'status';
  try {
    const r = await fetch(BASE + 'api/config/' + sel + '/' + tab, {
      method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(data),
    });
    if (!r.ok) throw new Error(await r.text());
    D[sel][tab] = data;
    ed._orig = JSON.stringify(data, null, 2); ed.value = ed._orig;
    st.textContent = 'Saved'; st.className = 'status ok'; ed.classList.remove('invalid');
    setTimeout(() => { if (st.textContent === 'Saved') st.textContent = ''; }, 2000);
  } catch (e) { st.textContent = 'Error: ' + e.message; st.className = 'status err'; btn.disabled = false; }
}

load();
</script>
</body>
</html>`;
}

// --- Server ---

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (BASE_PATH && url.pathname.startsWith(BASE_PATH)) {
    url.pathname = url.pathname.slice(BASE_PATH.length) || '/';
  }

  // GET /api/config — full config
  if (req.method === 'GET' && url.pathname === '/api/config') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(readAll()));
    return;
  }

  // GET /api/config/:network/:section
  if (req.method === 'GET' && url.pathname.startsWith('/api/config/')) {
    const [network, section] = url.pathname.slice('/api/config/'.length).split('/');
    if (network && section) {
      const all = readAll();
      const data = all[network]?.[section];
      if (data === undefined) { res.writeHead(404); res.end('Not found'); return; }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data, null, 2));
      return;
    }
  }

  // PUT /api/config/:network/:section
  if (req.method === 'PUT' && url.pathname.startsWith('/api/config/')) {
    const [network, section] = url.pathname.slice('/api/config/'.length).split('/');
    if (network && section) {
      let body = '';
      req.on('data', c => { body += c; });
      req.on('end', () => {
        try {
          const data = JSON.parse(body);
          const all = readAll();
          if (!all[network]) all[network] = {};
          all[network][section] = data;
          writeAll(all);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
          console.log(`  Updated ${network}.${section}`);
        } catch (err) {
          res.writeHead(400, { 'Content-Type': 'text/plain' });
          res.end('Invalid JSON: ' + err.message);
        }
      });
      return;
    }
  }

  // HTML
  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderHTML());
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found');
});

server.listen(PORT, () => {
  console.log(`\x1b[36mConfig Manager\x1b[0m running at \x1b[1mhttp://localhost:${PORT}\x1b[0m`);
  console.log(`  Config file: ${CONFIG_FILE}`);
  const data = readAll();
  console.log(`  Networks: ${Object.keys(data).sort().join(', ')}`);
});
