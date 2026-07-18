#!/usr/bin/env node
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { versionDeployments, currentDeployments } from './deployments.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REGISTRY_FILE = join(__dirname, 'versions', 'registry.json');
const PORT = parseInt(process.env.REGISTRY_PORT || '3030', 10);

const c = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m',
  green: '\x1b[32m', cyan: '\x1b[36m', yellow: '\x1b[33m',
};

// --- data helpers ---

function loadRegistry() {
  if (!existsSync(REGISTRY_FILE)) return { latest: null, pending: null, deployments: {}, versions: {} };
  const reg = JSON.parse(readFileSync(REGISTRY_FILE, 'utf-8'));
  if (!reg.pending) reg.pending = null;
  if (!reg.deployments) reg.deployments = {};
  return reg;
}

function resolveVersion(v) {
  if (v === 'pending') return 'pending';
  if (!v || v === 'latest') return loadRegistry().latest;
  return v.replace(/^v/, '');
}

function getEntry(version) {
  const reg = loadRegistry();
  if (version === 'pending') return reg.pending;
  return reg.versions[version] || null;
}

function getContract(version, contract) {
  const entry = getEntry(version);
  if (!entry || !entry.contracts[contract]) return null;
  return entry.contracts[contract];
}

function wantsHtml(req) {
  return (req.headers.accept || '').includes('text/html');
}

// --- responses ---

function sendJson(res, data, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
  res.end(JSON.stringify(data, null, 2));
}

function sendHtml(res, html, status = 200) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Access-Control-Allow-Origin': '*' });
  res.end(html);
}

// --- HTML UI ---

function buildHtml() {
  const reg = loadRegistry();
  const versions = Object.keys(reg.versions).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  const latest = reg.latest;

  const allData = {};

  // Add pending as a pseudo-version (no per-version deployments yet, use global)
  if (reg.pending) {
    const contractSummary = {};
    for (const [name, data] of Object.entries(reg.pending.contracts)) {
      contractSummary[name] = { abiItems: data.abi.length };
    }
    allData['pending'] = {
      manifest: { timestamp: reg.pending.timestamp, commit: reg.pending.commit, branch: reg.pending.branch, solc: reg.pending.solc, contracts: contractSummary },
      contracts: reg.pending.contracts,
      deployments: currentDeployments(reg),
    };
  }

  for (const v of versions) {
    const entry = reg.versions[v];
    const contractSummary = {};
    for (const [name, data] of Object.entries(entry.contracts)) {
      contractSummary[name] = { abiItems: data.abi.length };
    }
    allData[v] = {
      manifest: { timestamp: entry.timestamp, commit: entry.commit, branch: entry.branch, solc: entry.solc, contracts: contractSummary },
      contracts: entry.contracts,
      deployments: versionDeployments(reg, v),
    };
  }

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Contract Registry</title>
<style>
  :root {
    --bg: #0d1117; --surface: #161b22; --surface2: #1c2129;
    --border: #30363d; --text: #e6edf3; --text2: #8b949e;
    --accent: #58a6ff; --accent2: #3fb950; --warn: #d29922;
    --red: #f85149; --orange: #f0883e;
    --font: 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;
    --radius: 8px;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: var(--font); background: var(--bg); color: var(--text); min-height: 100vh; }

  .app { display: flex; min-height: 100vh; }
  .sidebar { width: 280px; background: var(--surface); border-right: 1px solid var(--border); padding: 20px 0; flex-shrink: 0; display: flex; flex-direction: column; }
  .main { flex: 1; padding: 24px 32px; overflow-y: auto; min-width: 0; }

  .logo { padding: 0 20px 20px; border-bottom: 1px solid var(--border); margin-bottom: 12px; }
  .logo h1 { font-size: 15px; font-weight: 600; }
  .logo p { font-size: 11px; color: var(--text2); margin-top: 4px; }

  .version-select { padding: 0 16px; margin-bottom: 16px; }
  .version-select label { font-size: 11px; color: var(--text2); text-transform: uppercase; letter-spacing: .5px; display: block; margin-bottom: 6px; }
  .version-select select {
    width: 100%; padding: 6px 10px; background: var(--surface2); border: 1px solid var(--border);
    color: var(--text); border-radius: var(--radius); font-family: var(--font); font-size: 13px;
    cursor: pointer; outline: none;
  }
  .version-select select:focus { border-color: var(--accent); }

  .version-meta { padding: 0 16px; margin-bottom: 16px; font-size: 11px; color: var(--text2); line-height: 1.7; }
  .version-meta span { color: var(--text); }

  .nav-label { padding: 0 16px; font-size: 11px; color: var(--text2); text-transform: uppercase; letter-spacing: .5px; margin-bottom: 8px; }
  .nav { list-style: none; flex: 1; overflow-y: auto; }
  .nav li {
    padding: 8px 20px; cursor: pointer; font-size: 13px; color: var(--text2);
    transition: all .15s; border-left: 2px solid transparent;
  }
  .nav li:hover { background: var(--surface2); color: var(--text); }
  .nav li.active { background: var(--surface2); color: var(--accent); border-left-color: var(--accent); }
  .nav li .count { font-size: 11px; color: var(--text2); margin-left: 6px; }

  .header { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
  .header h2 { font-size: 20px; font-weight: 600; }
  .header .badge { font-size: 11px; padding: 3px 8px; background: var(--surface2); border: 1px solid var(--border); border-radius: 12px; color: var(--text2); }
  .header .badge.pending { border-color: var(--orange); color: var(--orange); }

  .toolbar { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
  .toolbar input {
    flex: 1; min-width: 200px; padding: 8px 12px; background: var(--surface); border: 1px solid var(--border);
    color: var(--text); border-radius: var(--radius); font-family: var(--font); font-size: 13px; outline: none;
  }
  .toolbar input:focus { border-color: var(--accent); }
  .toolbar input::placeholder { color: var(--text2); }
  .btn {
    padding: 8px 14px; background: var(--surface2); border: 1px solid var(--border); color: var(--text);
    border-radius: var(--radius); font-family: var(--font); font-size: 12px; cursor: pointer; transition: all .15s; white-space: nowrap;
  }
  .btn:hover { border-color: var(--accent); color: var(--accent); }
  .btn.copied { border-color: var(--accent2); color: var(--accent2); }

  .tab-row { display: flex; gap: 0; border-bottom: 1px solid var(--border); margin-bottom: 16px; }
  .tab {
    padding: 8px 16px; font-size: 12px; cursor: pointer; color: var(--text2);
    border-bottom: 2px solid transparent; transition: all .15s;
  }
  .tab:hover { color: var(--text); }
  .tab.active { color: var(--accent); border-bottom-color: var(--accent); }

  .abi-section { margin-bottom: 24px; }
  .abi-section h3 { font-size: 12px; color: var(--text2); text-transform: uppercase; letter-spacing: .5px; margin-bottom: 8px; padding-left: 4px; }
  .abi-item {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    margin-bottom: 6px; overflow: hidden; transition: border-color .15s;
  }
  .abi-item:hover { border-color: #484f58; }
  .abi-item summary {
    padding: 10px 14px; cursor: pointer; font-size: 13px; list-style: none;
    display: flex; align-items: center; gap: 10px; user-select: none;
  }
  .abi-item summary::-webkit-details-marker { display: none; }
  .abi-item summary::before { content: '\\25b6'; font-size: 9px; color: var(--text2); transition: transform .15s; flex-shrink: 0; }
  .abi-item[open] summary::before { transform: rotate(90deg); }
  .fn-name { color: var(--accent); font-weight: 500; }
  .fn-mutability { font-size: 11px; padding: 2px 6px; border-radius: 4px; }
  .mut-view { background: #1a3a2a; color: var(--accent2); }
  .mut-pure { background: #1a2a3a; color: var(--accent); }
  .mut-payable { background: #3a2a1a; color: var(--warn); }
  .mut-nonpayable { background: var(--surface2); color: var(--text2); }
  .fn-selector { font-size: 11px; color: var(--text2); margin-left: auto; }
  .abi-detail { padding: 0 14px 12px; font-size: 12px; color: var(--text2); }
  .abi-detail table { width: 100%; border-collapse: collapse; }
  .abi-detail th { text-align: left; font-weight: 500; color: var(--text2); padding: 4px 8px; font-size: 11px; text-transform: uppercase; letter-spacing: .3px; }
  .abi-detail td { padding: 4px 8px; }
  .abi-detail .type { color: var(--warn); }
  .abi-detail .param-name { color: var(--text); }
  .abi-detail .io-label { font-size: 10px; text-transform: uppercase; letter-spacing: .5px; color: var(--text2); margin: 8px 0 4px; }

  .event-item summary .fn-name { color: var(--warn); }
  .error-item summary .fn-name { color: var(--red); }

  .json-view {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 16px; font-size: 12px; overflow-x: auto; max-height: 70vh; overflow-y: auto;
    line-height: 1.6; white-space: pre; tab-size: 2;
  }
  .json-key { color: var(--accent); }
  .json-str { color: var(--accent2); }
  .json-num { color: var(--warn); }
  .json-bool { color: var(--red); }

  .empty { text-align: center; padding: 60px 20px; color: var(--text2); }
  .empty p { margin-bottom: 8px; }

  .sel-table { width: 100%; border-collapse: collapse; }
  .sel-table th { text-align: left; font-weight: 500; color: var(--text2); padding: 6px 10px; font-size: 11px; text-transform: uppercase; border-bottom: 1px solid var(--border); }
  .sel-table td { padding: 6px 10px; font-size: 13px; border-bottom: 1px solid var(--border); }
  .sel-table td:first-child { color: var(--text); }
  .sel-table td:last-child { color: var(--text2); font-size: 12px; }

  /* deployments */
  .deploy-card {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 14px 18px; margin-bottom: 8px;
  }
  .deploy-card .chain { font-size: 13px; font-weight: 500; color: var(--text); margin-bottom: 4px; display: flex; align-items: center; gap: 8px; }
  .deploy-card .addr { font-size: 12px; color: var(--accent); word-break: break-all; cursor: pointer; }
  .deploy-card .addr:hover { text-decoration: underline; }
  .deploy-ver {
    font-size: 10px; padding: 2px 7px; border-radius: 10px; white-space: nowrap;
    background: var(--surface2); border: 1px solid var(--border); color: var(--text2);
  }
  .deploy-ver.carried { border-color: var(--orange); color: var(--orange); }
  .deploy-none { color: var(--text2); font-size: 13px; padding: 20px 0; }

  @media (max-width: 768px) {
    .app { flex-direction: column; }
    .sidebar { width: 100%; border-right: none; border-bottom: 1px solid var(--border); }
    .main { padding: 16px; }
  }
</style>
</head>
<body>
<div class="app">
  <aside class="sidebar">
    <div class="logo">
      <h1>Contract Registry</h1>
      <p>Smart Contracts Browser</p>
    </div>
    <div class="version-select">
      <label>Version</label>
      <select id="versionSelect"></select>
    </div>
    <div class="version-meta" id="versionMeta"></div>
    <div class="nav-label">Contracts</div>
    <ul class="nav" id="contractNav"></ul>
  </aside>
  <main class="main" id="mainContent">
    <div class="empty"><p>Select a contract from the sidebar</p></div>
  </main>
</div>
<script>
const DATA = ${JSON.stringify(allData)};
const LATEST = ${JSON.stringify(latest)};
const HAS_PENDING = ${JSON.stringify(!!reg.pending)};

let currentVersion = HAS_PENDING ? 'pending' : LATEST;
let currentContract = null;
let currentTab = 'abi';
let searchQuery = '';

const $ = id => document.getElementById(id);
const $versionSelect = $('versionSelect');
const $versionMeta = $('versionMeta');
const $nav = $('contractNav');
const $main = $('mainContent');

function init() {
  const versions = Object.keys(DATA).sort((a, b) => {
    if (a === 'pending') return -1;
    if (b === 'pending') return 1;
    return b.localeCompare(a, undefined, { numeric: true });
  });
  $versionSelect.innerHTML = versions.map(v => {
    let label = v;
    if (v === 'pending') label = 'pending (draft)';
    else if (v === LATEST) label = v + ' (latest)';
    const sel = v === currentVersion ? ' selected' : '';
    return '<option value="' + v + '"' + sel + '>' + label + '</option>';
  }).join('');
  $versionSelect.addEventListener('change', () => { currentVersion = $versionSelect.value; currentContract = null; renderNav(); });
  renderNav();
}

function renderNav() {
  const d = DATA[currentVersion];
  if (!d) return;
  const m = d.manifest;
  const isPending = currentVersion === 'pending';
  $versionMeta.innerHTML =
    (isPending ? '<span style="color:var(--orange)">PENDING</span><br>' : '') +
    'commit <span>' + m.commit + '</span><br>' +
    'branch <span>' + m.branch + '</span><br>' +
    'solc <span>' + m.solc + '</span><br>' +
    'date <span>' + m.timestamp.slice(0, 10) + '</span>';

  const names = Object.keys(d.manifest.contracts);
  $nav.innerHTML = names.map(n => {
    const info = d.manifest.contracts[n];
    return '<li data-name="' + n + '"' + (n === currentContract ? ' class="active"' : '') + '>'
      + n + '<span class="count">' + info.abiItems + '</span></li>';
  }).join('');

  $nav.querySelectorAll('li').forEach(li => {
    li.addEventListener('click', () => { currentContract = li.dataset.name; renderNav(); renderMain(); });
  });

  if (!currentContract && names.length) { currentContract = names[0]; renderNav(); renderMain(); }
}

function renderMain() {
  const d = DATA[currentVersion];
  if (!d || !currentContract) return;
  const contract = d.contracts[currentContract];
  if (!contract) { $main.innerHTML = '<div class="empty"><p>Contract not found</p></div>'; return; }

  const totalFns = contract.abi.filter(i => i.type === 'function').length;
  const totalEvents = contract.abi.filter(i => i.type === 'event').length;
  const totalErrors = contract.abi.filter(i => i.type === 'error').length;
  const isPending = currentVersion === 'pending';
  const deploys = (DATA[currentVersion]?.deployments || {})[currentContract];
  const deployCount = deploys ? Object.keys(deploys).length : 0;

  let html = '<div class="header">';
  html += '<h2>' + currentContract + '</h2>';
  if (isPending) html += '<span class="badge pending">pending</span>';
  else html += '<span class="badge">v' + currentVersion + '</span>';
  html += '<span class="badge">' + totalFns + ' functions</span>';
  if (totalEvents) html += '<span class="badge">' + totalEvents + ' events</span>';
  if (totalErrors) html += '<span class="badge">' + totalErrors + ' errors</span>';
  if (deployCount) html += '<span class="badge">' + deployCount + ' chains</span>';
  html += '</div>';

  html += '<div class="toolbar">';
  html += '<input type="text" id="search" placeholder="Search functions, events, errors..." value="' + escHtml(searchQuery) + '">';
  html += '<button class="btn" id="copyAbi">Copy ABI</button>';
  html += '<button class="btn" id="copySelectors">Copy Selectors</button>';
  html += '</div>';

  const tabs = ['abi', 'selectors', 'deployments', 'json'];
  html += '<div class="tab-row">';
  tabs.forEach(t => {
    let label = t.charAt(0).toUpperCase() + t.slice(1);
    if (t === 'deployments' && deployCount) label += ' (' + deployCount + ')';
    html += '<div class="tab' + (currentTab === t ? ' active' : '') + '" data-tab="' + t + '">' + label + '</div>';
  });
  html += '</div>';

  html += '<div id="tabContent"></div>';
  $main.innerHTML = html;

  $('search').addEventListener('input', e => { searchQuery = e.target.value; renderTabContent(contract); });
  $('copyAbi').addEventListener('click', e => { copyToClipboard(JSON.stringify(contract.abi, null, 2), e.target); });
  $('copySelectors').addEventListener('click', e => { copyToClipboard(JSON.stringify(contract.methodIdentifiers, null, 2), e.target); });
  document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => {
    currentTab = t.dataset.tab;
    document.querySelectorAll('.tab').forEach(x => x.classList.toggle('active', x === t));
    renderTabContent(contract);
  }));
  renderTabContent(contract);
}

function renderTabContent(contract) {
  const $content = $('tabContent');
  if (currentTab === 'json') {
    $content.innerHTML = '<div class="json-view">' + syntaxHighlight(JSON.stringify(contract.abi, null, 2)) + '</div>';
  } else if (currentTab === 'selectors') {
    renderSelectors($content, contract);
  } else if (currentTab === 'deployments') {
    renderDeployments($content);
  } else {
    renderAbiView($content, contract);
  }
}

function renderDeployments($el) {
  const deploys = (DATA[currentVersion]?.deployments || {})[currentContract];
  if (!deploys || !Object.keys(deploys).length) {
    $el.innerHTML = '<div class="deploy-none">No deployments recorded for this contract.</div>';
    return;
  }
  const chains = Object.entries(deploys).sort((a, b) => a[0].localeCompare(b[0]));
  let html = '';
  for (const [chain, d] of chains) {
    // tolerate both shapes: { address, version } (current) or a bare "0x.." string (legacy)
    const addr = (d && typeof d === 'object') ? d.address : d;
    const ver = (d && typeof d === 'object') ? d.version : null;
    const carried = ver && currentVersion !== 'pending' && ver !== currentVersion;
    let badge = '';
    if (ver) {
      const label = carried ? 'since v' + ver : 'v' + ver;
      const title = carried
        ? 'Not redeployed in this version — carried over from v' + ver
        : 'Deployed in this version';
      badge = '<span class="deploy-ver' + (carried ? ' carried' : '') + '" title="' + escHtml(title) + '">' + escHtml(label) + '</span>';
    } else {
      badge = '<span class="deploy-ver carried" title="Current networks.json address, not yet in a tagged version">current</span>';
    }
    html += '<div class="deploy-card">';
    html += '<div class="chain">' + escHtml(chain) + badge + '</div>';
    html += '<div class="addr" data-addr="' + escHtml(addr) + '">' + escHtml(addr) + '</div>';
    html += '</div>';
  }
  $el.innerHTML = html;
  $el.querySelectorAll('.addr').forEach(el => {
    el.addEventListener('click', () => { copyToClipboard(el.dataset.addr, el); });
  });
}

function renderAbiView($el, contract) {
  const q = searchQuery.toLowerCase();
  const groups = { constructor: [], function: [], event: [], error: [], fallback: [], receive: [] };
  for (const item of contract.abi) {
    const t = item.type || 'function';
    if (!groups[t]) groups[t] = [];
    const name = item.name || t;
    if (q && !name.toLowerCase().includes(q) && !formatSig(item).toLowerCase().includes(q)) continue;
    groups[t].push(item);
  }
  let html = '';
  const sections = [['constructor','Constructor'],['function','Functions'],['event','Events'],['error','Errors'],['receive','Receive'],['fallback','Fallback']];
  for (const [key, label] of sections) {
    if (!groups[key] || !groups[key].length) continue;
    html += '<div class="abi-section"><h3>' + label + ' (' + groups[key].length + ')</h3>';
    for (const item of groups[key]) {
      const extraClass = key === 'event' ? ' event-item' : key === 'error' ? ' error-item' : '';
      html += renderAbiItem(item, contract.methodIdentifiers, extraClass);
    }
    html += '</div>';
  }
  if (!html) html = '<div class="empty"><p>No matches</p></div>';
  $el.innerHTML = html;
}

function renderAbiItem(item, selectors, extraClass) {
  const name = item.name || item.type;
  const sig = formatSig(item);
  const selector = selectors[sig] || '';
  const mutability = item.stateMutability || '';
  const mutClass = mutability ? ' mut-' + mutability : '';
  let html = '<details class="abi-item' + extraClass + '"><summary>';
  html += '<span class="fn-name">' + escHtml(name) + '</span>';
  if (mutability) html += '<span class="fn-mutability' + mutClass + '">' + mutability + '</span>';
  if (selector) html += '<span class="fn-selector">0x' + selector + '</span>';
  html += '</summary><div class="abi-detail">';
  if (item.inputs && item.inputs.length) { html += '<div class="io-label">Inputs</div>' + renderParamsTable(item.inputs); }
  if (item.outputs && item.outputs.length) { html += '<div class="io-label">Outputs</div>' + renderParamsTable(item.outputs); }
  if (sig && selector) { html += '<div class="io-label">Signature</div><div style="padding:4px 8px">' + escHtml(sig) + '</div>'; }
  html += '</div></details>';
  return html;
}

function renderParamsTable(params) {
  let html = '<table><tr><th>Name</th><th>Type</th></tr>';
  for (const p of params) { html += '<tr><td class="param-name">' + escHtml(p.name || '-') + '</td><td class="type">' + escHtml(p.type) + '</td></tr>'; }
  return html + '</table>';
}

function renderSelectors($el, contract) {
  const q = searchQuery.toLowerCase();
  const entries = Object.entries(contract.methodIdentifiers);
  const filtered = q ? entries.filter(([sig]) => sig.toLowerCase().includes(q)) : entries;
  if (!filtered.length) { $el.innerHTML = '<div class="empty"><p>No matches</p></div>'; return; }
  let html = '<table class="sel-table"><tr><th>Function</th><th>Selector</th></tr>';
  for (const [sig, sel] of filtered.sort((a, b) => a[0].localeCompare(b[0]))) {
    html += '<tr><td>' + escHtml(sig) + '</td><td>0x' + sel + '</td></tr>';
  }
  $el.innerHTML = html + '</table>';
}

function formatSig(item) {
  if (!item.name) return '';
  return item.name + '(' + (item.inputs || []).map(i => i.type).join(',') + ')';
}

function escHtml(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

function syntaxHighlight(json) {
  return json.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"([^"]+)"\\s*:/g, '<span class="json-key">"$1"</span>:')
    .replace(/: "([^"]*)"/g, ': <span class="json-str">"$1"</span>')
    .replace(/: (\\d+)/g, ': <span class="json-num">$1</span>')
    .replace(/: (true|false)/g, ': <span class="json-bool">$1</span>');
}

async function copyToClipboard(text, el) {
  try {
    await navigator.clipboard.writeText(text);
    const origColor = el.style.color;
    el.style.color = 'var(--accent2)';
    if (el.classList.contains('btn')) { el.classList.add('copied'); const orig = el.textContent; el.textContent = 'Copied!'; setTimeout(() => { el.classList.remove('copied'); el.textContent = orig; el.style.color = origColor; }, 1500); }
    else { setTimeout(() => { el.style.color = origColor; }, 1000); }
  } catch {}
}

init();
</script>
</body>
</html>`;
}

// --- request log ---
function logRequest(method, url, status) {
  const statusColor = status < 300 ? c.green : status < 400 ? c.yellow : '\x1b[31m';
  const time = new Date().toLocaleTimeString('en-GB');
  console.log(`  ${c.dim}${time}${c.reset}  ${method} ${url}  ${statusColor}${status}${c.reset}`);
}

// --- server ---

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const parts = url.pathname.split('/').filter(Boolean);

  if (parts.length === 0 && wantsHtml(req)) {
    logRequest(req.method, url.pathname, 200);
    return sendHtml(res, buildHtml());
  }

  // GET / — overview
  if (parts.length === 0) {
    const reg = loadRegistry();
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, {
      latest: reg.latest,
      pending: !!reg.pending,
      versions: Object.keys(reg.versions).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })),
    });
  }

  // GET /deployments  -> { contract: { network: { address, version } } } (current addresses, tagged)
  if (parts[0] === 'deployments' && parts.length === 1) {
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, currentDeployments(loadRegistry()));
  }

  // GET /deployments/:contract -> { network: { address, version } }
  if (parts[0] === 'deployments' && parts.length === 2) {
    const deploys = currentDeployments(loadRegistry())[parts[1]];
    if (!deploys) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: `no deployments for ${parts[1]}` }, 404); }
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, deploys);
  }

  // GET /pending
  if (parts[0] === 'pending' && parts.length === 1) {
    const reg = loadRegistry();
    if (!reg.pending) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: 'no pending snapshot' }, 404); }
    const contractSummary = {};
    for (const [name, data] of Object.entries(reg.pending.contracts)) {
      contractSummary[name] = { abiItems: data.abi.length, methods: Object.keys(data.methodIdentifiers).length };
    }
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, { ...reg.pending, contracts: contractSummary });
  }

  // GET /pending/:contract
  if (parts[0] === 'pending' && parts.length === 2) {
    const data = getContract('pending', parts[1]);
    if (!data) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: `${parts[1]} not found in pending` }, 404); }
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, { contract: parts[1], version: 'pending', ...data });
  }

  // GET /versions
  if (parts[0] === 'versions' && parts.length === 1) {
    const reg = loadRegistry();
    const versions = Object.keys(reg.versions).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    const result = versions.map(v => {
      const entry = reg.versions[v];
      const contractSummary = {};
      for (const [name, data] of Object.entries(entry.contracts)) {
        contractSummary[name] = { abiItems: data.abi.length, methods: Object.keys(data.methodIdentifiers).length };
      }
      return { version: v, timestamp: entry.timestamp, commit: entry.commit, branch: entry.branch, solc: entry.solc, contracts: contractSummary };
    });
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, result);
  }

  // GET /versions/:version
  if (parts[0] === 'versions' && parts.length === 2) {
    const version = resolveVersion(parts[1]);
    if (!version) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: 'no versions available' }, 404); }
    const reg = loadRegistry();
    const entry = getEntry(version);
    if (!entry) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: `version ${version} not found` }, 404); }
    const contractSummary = {};
    for (const [name, data] of Object.entries(entry.contracts)) {
      contractSummary[name] = { abiItems: data.abi.length, methods: Object.keys(data.methodIdentifiers).length };
    }
    // Carry-forward deployments tagged with the version each address was deployed in.
    const deployments = version === 'pending' ? currentDeployments(reg) : versionDeployments(reg, version);
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, { version, timestamp: entry.timestamp, commit: entry.commit, branch: entry.branch, solc: entry.solc, contracts: contractSummary, deployments });
  }

  // GET /:contract
  if (parts.length === 1) {
    const contract = parts[0];
    const version = resolveVersion(url.searchParams.get('version'));
    if (!version) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: 'no versions available' }, 404); }
    const data = getContract(version, contract);
    if (!data) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: `${contract} not found in v${version}` }, 404); }
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, { contract, version, ...data });
  }

  // GET /:contract/:version
  if (parts.length === 2) {
    const [contract, rawVersion] = parts;
    const version = resolveVersion(rawVersion);
    if (!version) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: 'no versions available' }, 404); }
    const data = getContract(version, contract);
    if (!data) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: `${contract} not found in v${version}` }, 404); }
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, { contract, version, ...data });
  }

  // GET /:contract/:version/abi
  if (parts.length === 3 && parts[2] === 'abi') {
    const [contract, rawVersion] = parts;
    const version = resolveVersion(rawVersion);
    if (!version) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: 'no versions available' }, 404); }
    const data = getContract(version, contract);
    if (!data) { logRequest(req.method, url.pathname, 404); return sendJson(res, { error: `${contract} not found in v${version}` }, 404); }
    logRequest(req.method, url.pathname, 200);
    return sendJson(res, data.abi);
  }

  logRequest(req.method, url.pathname, 404);
  sendJson(res, { error: 'not found' }, 404);
});

server.listen(PORT, () => {
  const reg = loadRegistry();
  const line = '\u2500'.repeat(46);
  console.log('');
  console.log(`${c.cyan}${line}${c.reset}`);
  console.log(`${c.bold}  Contract Registry${c.reset}`);
  console.log(`${c.cyan}${line}${c.reset}`);
  console.log('');
  console.log(`  ${c.green}Local${c.reset}   http://localhost:${PORT}`);
  console.log('');
  const versions = Object.keys(reg.versions).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (reg.latest) {
    console.log(`  ${c.dim}latest${c.reset}  v${reg.latest}  ${c.dim}(${versions.length} version${versions.length === 1 ? '' : 's'})${c.reset}`);
  }
  if (reg.pending) {
    console.log(`  ${c.yellow}pending${c.reset} ${reg.pending.commit}  ${c.dim}${reg.pending.timestamp.slice(0, 10)}${c.reset}`);
  }
  if (!reg.latest && !reg.pending) {
    console.log(`  ${c.yellow}No versions yet.${c.reset} Run: npm run registry:update -- <version>`);
  }
  const deployCount = Object.keys(reg.deployments).length;
  if (deployCount) {
    console.log(`  ${c.dim}deploys${c.reset} ${deployCount} contracts`);
  }
  console.log('');
  console.log(`  ${c.dim}API${c.reset}     GET /:contract            ${c.dim}latest ABI${c.reset}`);
  console.log(`          GET /:contract/pending    ${c.dim}pending ABI${c.reset}`);
  console.log(`          GET /:contract/:version   ${c.dim}specific version${c.reset}`);
  console.log(`          GET /deployments          ${c.dim}all addresses${c.reset}`);
  console.log(`          GET /deployments/:contract${c.dim} per contract${c.reset}`);
  console.log('');
  console.log(`${c.cyan}${line}${c.reset}`);
  console.log('');
});
