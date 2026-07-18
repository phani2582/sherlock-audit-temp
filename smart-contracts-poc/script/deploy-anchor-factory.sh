#!/usr/bin/env bash
set -euo pipefail

# ── Deploy AnchoredProviderFactory on ethereum, base, hyperevm ─────────
# Wraps script/DeployAnchorFactory.s.sol (CREATE3, deterministic address per
# REFERENCE + DEPLOY_VERSION) across the three target chains.
#
# The factory anchors to ONE reference oracle, chosen PER-NETWORK (the salt + registry
# key are keyed on it, so each family gets its own deterministic address):
#   chainlink  → deployments.dataStreamsOracle   (ethereum, base)
#   compressed → deployments.compressedOracle     (hyperevm — no Pyth/CL infra there)
#   pyth       → deployments.oracle
# Defaults: hyperevm → compressed; every other chain → $REFERENCE (default chainlink).
# Override per network with REF_<NET> (e.g. REF_BASE=pyth) and/or ORACLE_<NET>=0x...
# A chain whose chosen oracle is unset in networks.json is skipped unless its
# ORACLE_<NET> is given; the resolved oracle MUST already be deployed (the script
# requires bytecode at it).
#
# ── Usage ──────────────────────────────────────────────────────────────
# Dry-run (simulate, no broadcast):
#   PRIVATE_KEY=0x... DEPLOY_VERSION=v1 bash script/deploy-anchor-factory.sh
#
# Real deployment:
#   PRIVATE_KEY=0x... DEPLOY_VERSION=v1 bash script/deploy-anchor-factory.sh --broadcast
#
# hyperevm needs a CompressedOracle deployed there first (read from
# deployments.compressedOracle, or pass ORACLE_HYPEREVM=0x...).
#
# Prereqs (CREATE3): CreateX (0xba5Ed0…ba5Ed) is deployed on all three chains.

# ── Required env ────────────────────────────────────────────────────────
: "${PRIVATE_KEY:?Set PRIVATE_KEY env var}"
: "${DEPLOY_VERSION:?Set DEPLOY_VERSION env var (e.g. v1)}"
REFERENCE="${REFERENCE:-chainlink}"   # default family for non-hyper chains

# RPCs come from foundry.toml [rpc_endpoints] (alias == network name), so --rpc-url <net> resolves.
NETWORKS=(ethereum base hyperevm)

# Per-network reference family: REF_<NET> override, else hyperevm→compressed, else $REFERENCE.
ref_for() {
  local var="REF_$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  if [[ -n "${!var:-}" ]]; then echo "${!var}"
  elif [[ "$1" == "hyperevm" ]]; then echo "compressed"
  else echo "$REFERENCE"; fi
}

# networks.json deployments key for a reference family ("" = invalid).
key_for() {
  case "$1" in
    chainlink)  echo "dataStreamsOracle" ;;
    pyth)       echo "oracle" ;;
    compressed) echo "compressedOracle" ;;
    *)          echo "" ;;
  esac
}

# Per-network ORACLE override env: ORACLE_ETHEREUM / ORACLE_BASE / ORACLE_HYPEREVM
get_oracle_override() {
  local var="ORACLE_$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  echo "${!var:-}"
}

# Resolved oracle from networks.json for a given deployments key (may be empty).
config_oracle() {
  node -e "const c=require('./script/config/networks.json'); process.stdout.write((c['$1']?.deployments?.['$2'])||'')" 2>/dev/null || echo ""
}

# ── Broadcast flag ───────────────────────────────────────────────────────
BROADCAST=""
if [[ "${1:-}" == "--broadcast" ]]; then
  BROADCAST="--broadcast"
  echo "MODE: broadcast (real deployment) — default reference=$REFERENCE (hyperevm=compressed)"
else
  echo "MODE: dry-run (simulation only, pass --broadcast to deploy) — default reference=$REFERENCE (hyperevm=compressed)"
fi

FAILED=()
OK=()

for net in "${NETWORKS[@]}"; do
  ref=$(ref_for "$net")
  key=$(key_for "$ref")
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  $net  (reference=$ref)"
  echo "════════════════════════════════════════════════════════════"

  if [[ -z "$key" ]]; then
    echo "✗ $net — invalid reference '$ref' (use chainlink|pyth|compressed)"
    FAILED+=("$net:bad-ref")
    continue
  fi

  # Resolve the oracle: explicit override wins, else networks.json[net].deployments[key].
  oracle_override=$(get_oracle_override "$net")
  resolved="${oracle_override:-$(config_oracle "$net" "$key")}"
  if [[ -z "$resolved" ]]; then
    echo "⏭  $net — no $key in networks.json and no ORACLE_${net^^} override; skipping"
    FAILED+=("$net:no-oracle")
    continue
  fi

  # Pass the override through to the forge script (it reads vm.envOr("ORACLE", 0)).
  ORACLE_ENV=()
  [[ -n "$oracle_override" ]] && ORACLE_ENV=(ORACLE="$oracle_override")

  extra=""
  [[ "$net" == "hyperevm" ]] && extra="--skip-simulation"  # non-standard chain; skip gas sim

  echo "── Deploy AnchoredProviderFactory (oracle=$resolved) ──"
  if env NETWORK="$net" DEPLOY_VERSION="$DEPLOY_VERSION" REFERENCE="$ref" \
        PRIVATE_KEY="$PRIVATE_KEY" "${ORACLE_ENV[@]}" \
        forge script script/DeployAnchorFactory.s.sol \
        --rpc-url "$net" $BROADCAST $extra; then
    echo "✓ $net"
    OK+=("$net")
  else
    echo "✗ deploy FAILED on $net"
    FAILED+=("$net:deploy")
  fi
done

echo ""
echo "════════════════════════════════════════════════════════════"
[[ -z "$BROADCAST" ]] && echo "  Dry-run complete" || echo "  Deployment complete"
echo "════════════════════════════════════════════════════════════"
[[ ${#OK[@]} -gt 0 ]] && echo "OK: ${OK[*]}"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "All OK."
else
  echo "Skipped/failed:"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi
