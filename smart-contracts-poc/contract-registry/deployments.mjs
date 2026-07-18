// Shared deployment resolution: carry-forward + "deployed-in" version mark.
//
// Each version snapshots only what networks.json held at promote time. Because CREATE3 addresses
// are salted with DEPLOY_VERSION, an address unchanged across versions means the contract was NOT
// redeployed. So for a given version we resolve, per (contract, network), the most recent non-empty
// address from versions <= target (carrying forward when that version didn't redeploy it), tagged
// with the version where that exact address was first recorded contiguously = its deploy version.
//
// Idempotent: deployment values may be bare "0x.." strings OR { address, version } objects.

export function addrOf(v) {
  if (!v) return '';
  return typeof v === 'object' ? (v.address || '') : v;
}

export function numCmp(a, b) { return String(a).localeCompare(String(b), undefined, { numeric: true }); }
export function sortedVersions(reg) { return Object.keys(reg.versions || {}).sort(numCmp); }

// layers: [{ version, deployments, removed }] ordered oldest -> newest.
//   removed: array of contract names tombstoned at that version (suppresses carry-forward for the
//   contract from that version onward, until it is deployed again in a later layer).
// Returns { contract: { network: { address, version } } } reflecting the newest layer.
export function effectiveFromLayers(layers) {
  const out = {};
  layers.forEach((layer, i) => {
    const dep = layer.deployments || {};
    for (const c in dep) {
      for (const n in dep[c]) {
        const addr = addrOf(dep[c][n]);
        if (!addr) continue;
        if (!out[c]) out[c] = {};
        out[c][n] = { address: addr, _i: i }; // later layers overwrite -> latest non-empty wins
      }
    }
    for (const c of (layer.removed || [])) {
      if (out[c]) for (const n in out[c]) out[c][n] = { removed: true }; // tombstone known networks
    }
  });
  const res = {};
  for (const c in out) {
    for (const n in out[c]) {
      const cur = out[c][n];
      if (cur.removed) continue; // suppressed by a tombstone with no later redeploy
      const { address, _i } = cur;
      let o = _i; // walk back over the contiguous run of the same address -> its deploy version
      while (o - 1 >= 0 && addrOf(layers[o - 1].deployments?.[c]?.[n]) === address) o--;
      if (!res[c]) res[c] = {};
      res[c][n] = { address, version: layers[o].version };
    }
  }
  return res;
}

// Per-version view: carries forward contracts not redeployed in `target`, each tagged with the
// version it was deployed in.
export function versionDeployments(reg, target) {
  const layers = sortedVersions(reg)
    .filter(v => numCmp(v, target) <= 0)
    .map(v => ({ version: v, deployments: reg.versions[v].deployments || {}, removed: reg.versions[v].removedDeployments || [] }));
  return effectiveFromLayers(layers);
}

// Current ("latest networks.json") view: current addresses only (no carry-forward of absent ones),
// each tagged with the version it was deployed in (null if not present in any tagged version yet).
export function currentDeployments(reg) {
  const layers = sortedVersions(reg).map(v => ({ version: v, deployments: reg.versions[v].deployments || {}, removed: reg.versions[v].removedDeployments || [] }));
  layers.push({ version: null, deployments: reg.deployments || {} });
  const eff = effectiveFromLayers(layers);
  const cur = reg.deployments || {};
  const out = {};
  for (const c in cur) {
    for (const n in cur[c]) {
      if (addrOf(cur[c][n]) && eff[c]?.[n]) {
        if (!out[c]) out[c] = {};
        out[c][n] = eff[c][n];
      }
    }
  }
  return out;
}

// Mutates `reg` so every stored record carries the { address, version } shape: each version's
// deployments (carry-forward + mark) and the top-level current deployments. Idempotent — safe to
// run on already-baked data.
export function bakeDeployments(reg) {
  const vs = sortedVersions(reg);
  const computedVersions = {};
  for (const v of vs) computedVersions[v] = versionDeployments(reg, v);
  const computedCurrent = currentDeployments(reg);
  for (const v of vs) reg.versions[v].deployments = computedVersions[v];
  reg.deployments = computedCurrent;
  return reg;
}
