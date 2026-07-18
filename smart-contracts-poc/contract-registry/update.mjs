#!/usr/bin/env node
import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONTRACTS, DEPLOYMENT_MAP } from './contracts.mjs';
import { bakeDeployments } from './deployments.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const VERSIONS_DIR = join(__dirname, 'versions');
const REGISTRY_FILE = join(VERSIONS_DIR, 'registry.json');
const NETWORKS_FILE = join(ROOT, 'script', 'config', 'networks.json');
const OUT_DIR = join(ROOT, 'out');

const c = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m',
  green: '\x1b[32m', yellow: '\x1b[33m', red: '\x1b[31m',
  cyan: '\x1b[36m', magenta: '\x1b[35m', gray: '\x1b[90m',
};

function git(cmd) {
  try { return execSync(cmd, { cwd: ROOT, encoding: 'utf-8' }).trim(); }
  catch { return 'unknown'; }
}

function findArtifact(contract) {
  const file = contract.file || contract.name;
  const artifact = contract.artifact || contract.name;
  const p = join(OUT_DIR, `${file}.sol`, `${artifact}.json`);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf-8'));
}

function loadRegistry() {
  if (!existsSync(REGISTRY_FILE)) return { latest: null, pending: null, deployments: {}, versions: {} };
  const reg = JSON.parse(readFileSync(REGISTRY_FILE, 'utf-8'));
  if (!reg.pending) reg.pending = null;
  if (!reg.deployments) reg.deployments = {};
  return reg;
}

function saveRegistry(reg) {
  // Persist deployments in the { address, version } shape (carry-forward + deployed-in mark).
  bakeDeployments(reg);
  mkdirSync(VERSIONS_DIR, { recursive: true });
  writeFileSync(REGISTRY_FILE, JSON.stringify(reg, null, 2) + '\n');
}

function printHeader(text) {
  const line = '\u2500'.repeat(50);
  console.log(`\n${c.cyan}${line}${c.reset}`);
  console.log(`${c.bold}  ${text}${c.reset}`);
  console.log(`${c.cyan}${line}${c.reset}\n`);
}

// --- Sync deployments from networks.json ---

function readDeployments() {
  if (!existsSync(NETWORKS_FILE)) return {};
  const networks = JSON.parse(readFileSync(NETWORKS_FILE, 'utf-8'));
  const result = {};
  for (const [contract, mapping] of Object.entries(DEPLOYMENT_MAP)) {
    const addrs = {};
    for (const [network, config] of Object.entries(networks)) {
      if (mapping.networks && !mapping.networks.includes(network)) continue;
      if (mapping.exclude && mapping.exclude.includes(network)) continue;
      const addr = config.deployments?.[mapping.key];
      if (addr && addr !== '') addrs[network] = addr;
    }
    if (Object.keys(addrs).length) result[contract] = addrs;
  }
  return result;
}

function syncDeployments(reg) {
  reg.deployments = readDeployments();
}

// --- Build snapshot entry from current forge artifacts ---

function buildSnapshot({ build = false } = {}) {
  if (build) {
    console.log(`  ${c.cyan}Building contracts...${c.reset}\n`);
    execSync('forge build', { cwd: ROOT, stdio: 'inherit' });
    console.log('');
  }

  const commit = git('git rev-parse --short HEAD');
  const branch = git('git rev-parse --abbrev-ref HEAD');
  console.log(`  ${c.dim}branch${c.reset}  ${branch}`);
  console.log(`  ${c.dim}commit${c.reset}  ${commit}\n`);

  const entry = {
    timestamp: new Date().toISOString(),
    commit,
    branch,
    solc: '0.8.33',
    contracts: {},
  };

  const results = [];

  for (const contract of CONTRACTS) {
    const artifact = findArtifact(contract);
    if (!artifact) {
      results.push({ name: contract.name, ok: false });
      continue;
    }
    const data = {
      abi: artifact.abi,
      methodIdentifiers: artifact.methodIdentifiers || {},
    };
    entry.contracts[contract.name] = data;
    results.push({
      name: contract.name, ok: true,
      abi: data.abi.length,
      methods: Object.keys(data.methodIdentifiers).length,
    });
  }

  // Print results table
  const nameWidth = Math.max(...results.map(r => r.name.length), 8);
  console.log(`  ${c.dim}${'Contract'.padEnd(nameWidth)}  ${'ABI'.padStart(5)}  ${'Fns'.padStart(5)}  Status${c.reset}`);
  console.log(`  ${c.dim}${'\u2500'.repeat(nameWidth)}  ${'\u2500'.repeat(5)}  ${'\u2500'.repeat(5)}  ${'\u2500'.repeat(8)}${c.reset}`);

  for (const r of results) {
    if (r.ok) {
      console.log(`  ${r.name.padEnd(nameWidth)}  ${String(r.abi).padStart(5)}  ${String(r.methods).padStart(5)}  ${c.green}ok${c.reset}`);
    } else {
      console.log(`  ${r.name.padEnd(nameWidth)}  ${c.dim}    -      -${c.reset}  ${c.yellow}skip${c.reset}`);
    }
  }

  const ok = results.filter(r => r.ok).length;
  const skipped = results.length - ok;
  return { entry, ok, skipped };
}

// --- Commands ---

function printList() {
  const reg = loadRegistry();
  const versions = Object.keys(reg.versions).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));

  printHeader('Contract Registry \u2014 Versions');

  if (reg.pending) {
    const count = Object.keys(reg.pending.contracts).length;
    const date = reg.pending.timestamp.slice(0, 10);
    console.log(`  ${c.yellow}${c.bold}pending${c.reset}  ${c.dim}${date}  ${reg.pending.commit}  ${count} contracts${c.reset}`);
  }

  if (!versions.length && !reg.pending) {
    console.log(`${c.dim}  No versions found. Run: npm run registry:update -- <version>${c.reset}`);
    return;
  }

  for (const v of versions) {
    const entry = reg.versions[v];
    const count = Object.keys(entry.contracts).length;
    const isLatest = v === reg.latest;
    const tag = isLatest ? `${c.green} <- latest${c.reset}` : '';
    const date = entry.timestamp.slice(0, 10);
    console.log(`  ${c.bold}${v}${c.reset}${tag}  ${c.dim}${date}  ${entry.commit}  ${count} contracts${c.reset}`);
  }

  if (Object.keys(reg.deployments).length) {
    console.log(`\n  ${c.dim}Deployments:${c.reset}`);
    for (const [contract, addrs] of Object.entries(reg.deployments)) {
      const chains = Object.keys(addrs).join(', ');
      console.log(`    ${contract}  ${c.dim}${chains}${c.reset}`);
    }
  }

  console.log('');
}

function updatePending({ build = false } = {}) {
  printHeader('Contract Registry \u2014 Pending Snapshot');

  const reg = loadRegistry();
  const { entry, ok, skipped } = buildSnapshot({ build });

  reg.pending = entry;
  syncDeployments(reg);
  saveRegistry(reg);

  console.log(`\n  ${c.yellow}${c.bold}pending${c.reset} saved  ${c.dim}(${ok} contracts${skipped ? `, ${skipped} skipped` : ''})${c.reset}`);
  console.log(`  ${c.dim}Promote with: npm run registry:update -- <version> --promote${c.reset}\n`);
}

function promote(version, { force = false } = {}) {
  version = version.replace(/^v/, '');
  const reg = loadRegistry();

  if (!reg.pending) {
    console.log(`\n  ${c.red}No pending snapshot to promote.${c.reset} Run ${c.bold}--pending${c.reset} first.\n`);
    process.exit(1);
  }

  if (reg.versions[version] && !force) {
    console.log(`\n  ${c.red}Version ${c.bold}${version}${c.reset}${c.red} already exists.${c.reset} Use ${c.bold}--force${c.reset} to overwrite.\n`);
    process.exit(1);
  }

  printHeader(`Contract Registry \u2014 Promote pending -> v${version}`);

  const count = Object.keys(reg.pending.contracts).length;
  console.log(`  ${c.dim}commit${c.reset}  ${reg.pending.commit}`);
  console.log(`  ${c.dim}branch${c.reset}  ${reg.pending.branch}`);
  console.log(`  ${c.dim}date${c.reset}    ${reg.pending.timestamp.slice(0, 10)}`);
  console.log(`  ${c.dim}contracts${c.reset}  ${count}\n`);

  const deployments = readDeployments();
  reg.pending.deployments = deployments;
  reg.versions[version] = reg.pending;
  reg.latest = version;
  reg.pending = null;
  syncDeployments(reg);
  saveRegistry(reg);

  const deployCount = Object.values(deployments).reduce((n, d) => n + Object.keys(d).length, 0);
  console.log(`  ${c.green}${c.bold}v${version}${c.reset} promoted from pending  ${c.dim}(${count} contracts, ${deployCount} deployments)${c.reset}\n`);
}

function purgePending() {
  printHeader('Contract Registry — Purge pending');

  const reg = loadRegistry();
  if (!reg.pending) {
    console.log(`  ${c.dim}No pending snapshot to purge.${c.reset}\n`);
    return;
  }

  const count = Object.keys(reg.pending.contracts).length;
  const date = reg.pending.timestamp.slice(0, 10);
  reg.pending = null;
  saveRegistry(reg);

  console.log(`  ${c.yellow}${c.bold}pending purged${c.reset}  ${c.dim}(${count} contracts from ${date})${c.reset}\n`);
}

function update(version, { build = false, force = false } = {}) {
  version = version.replace(/^v/, '');

  const reg = loadRegistry();
  if (reg.versions[version] && !force) {
    console.log(`\n  ${c.red}Version ${c.bold}${version}${c.reset}${c.red} already exists.${c.reset} Use ${c.bold}--force${c.reset} to overwrite.\n`);
    process.exit(1);
  }

  printHeader(`Contract Registry \u2014 Snapshot v${version}`);

  const { entry, ok, skipped } = buildSnapshot({ build });

  entry.deployments = readDeployments();
  reg.versions[version] = entry;
  reg.latest = version;
  syncDeployments(reg);
  saveRegistry(reg);

  const deployCount = Object.values(entry.deployments).reduce((n, d) => n + Object.keys(d).length, 0);
  console.log(`\n  ${c.green}${c.bold}v${version}${c.reset} saved  ${c.dim}(${ok} contracts${skipped ? `, ${skipped} skipped` : ''}, ${deployCount} deployments)${c.reset}\n`);
}

function printUsage() {
  printHeader('Contract Registry \u2014 Update');
  console.log(`  ${c.bold}Usage:${c.reset}  npm run registry:update -- <version> [flags]`);
  console.log(`          npm run registry:update -- --pending [--build]\n`);
  console.log(`  ${c.bold}Flags:${c.reset}`);
  console.log(`    --pending        snapshot to pending (no version)`);
  console.log(`    --promote        promote pending to a version`);
  console.log(`    --purge-pending  discard the pending snapshot`);
  console.log(`    --build          forge build before snapshot`);
  console.log(`    --force          overwrite existing version`);
  console.log(`    --list           show saved versions\n`);
  console.log(`  ${c.bold}Examples:${c.reset}`);
  console.log(`    ${c.dim}npm run registry:update -- --pending${c.reset}`);
  console.log(`    ${c.dim}npm run registry:update -- --pending --build${c.reset}`);
  console.log(`    ${c.dim}npm run registry:update -- --purge-pending${c.reset}`);
  console.log(`    ${c.dim}npm run registry:update -- 1.0.0 --promote${c.reset}`);
  console.log(`    ${c.dim}npm run registry:update -- 1.0.0${c.reset}`);
  console.log(`    ${c.dim}npm run registry:update -- 1.0.0 --build${c.reset}\n`);
  process.exit(0);
}

// --- CLI ---
const args = process.argv.slice(2);
const flags = new Set(args.filter(a => a.startsWith('--')));
const positional = args.filter(a => !a.startsWith('--'));

if (flags.has('--list')) {
  printList();
} else if (flags.has('--purge-pending')) {
  purgePending();
} else if (flags.has('--pending')) {
  updatePending({ build: flags.has('--build') });
} else if (flags.has('--promote')) {
  if (!positional[0]) {
    console.log(`\n  ${c.red}Version required.${c.reset} Usage: npm run registry:update -- <version> --promote\n`);
    process.exit(1);
  }
  promote(positional[0], { force: flags.has('--force') });
} else if (positional[0]) {
  update(positional[0], { build: flags.has('--build'), force: flags.has('--force') });
} else {
  printUsage();
}
