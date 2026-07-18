#!/usr/bin/env bash
set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────────
# Dry-run (simulate on all chains, no broadcast):
#   PRIVATE_KEY=0x... bash script/grant-factory-roles-all.sh
#
# Real deployment:
#   PRIVATE_KEY=0x... bash script/grant-factory-roles-all.sh --broadcast
#
# Reads per-network config from:
#   script/config/{NETWORK}/deployments.json    → factory address
#   script/config/{NETWORK}/access.json → role grants
#
# Networks without access.json are skipped automatically.

# ── RPC endpoints ─────────────────────────────────────────────────────
RPC_ETHEREUM="https://eth-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_BASE="https://base-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_POLYGON="https://polygon-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_BSC="https://bnb-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_ARBITRUM="https://arb-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_OPTIMISM="https://opt-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_AVALANCHE="https://avax-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_MEGAETH="https://megaeth-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_BERACHAIN="https://berachain-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"
RPC_MONAD="https://monad-mainnet.g.alchemy.com/v2/sWIgoNy7Z9oYR5-OXzCZOqNf4fWrFi9N"

# ── Deployer key ──────────────────────────────────────────────────────
: "${PRIVATE_KEY:?Set PRIVATE_KEY env var}"

# ── Broadcast flag ────────────────────────────────────────────────────
BROADCAST=""
if [[ "${1:-}" == "--broadcast" ]]; then
  BROADCAST="--broadcast"
  echo "MODE: broadcast (real transactions)"
else
  echo "MODE: dry-run (simulation only, pass --broadcast to execute)"
fi

# ── Network list ──────────────────────────────────────────────────────
NETWORKS=(ethereum base bsc polygon arbitrum optimism avalanche megaeth berachain monad)

# ── Resolve RPC for a network ─────────────────────────────────────────
get_rpc() {
  local net="$1"
  case "$net" in
    ethereum)   echo "$RPC_ETHEREUM" ;;
    base)       echo "$RPC_BASE" ;;
    bsc)        echo "$RPC_BSC" ;;
    polygon)    echo "$RPC_POLYGON" ;;
    arbitrum)   echo "$RPC_ARBITRUM" ;;
    optimism)   echo "$RPC_OPTIMISM" ;;
    avalanche)  echo "$RPC_AVALANCHE" ;;
    megaeth)    echo "$RPC_MEGAETH" ;;
    berachain)  echo "$RPC_BERACHAIN" ;;
    monad)      echo "$RPC_MONAD" ;;
    *)          echo "" ;;
  esac
}

# ── Extra forge flags per network ─────────────────────────────────────
get_extra_flags() {
  local net="$1"
  case "$net" in
    megaeth) echo "--skip-simulation" ;;
    *)       echo "" ;;
  esac
}

# ── Grant roles ──────────────────────────────────────────────────────
FAILED=()
OK=()
SKIPPED=()

for net in "${NETWORKS[@]}"; do
  rpc=$(get_rpc "$net")
  if [[ -z "$rpc" ]]; then
    echo "⏭  $net — RPC not set, skipping"
    SKIPPED+=("$net:no-rpc")
    continue
  fi

  if ! node -e "const c=JSON.parse(require('fs').readFileSync('script/config/networks.json','utf-8')); process.exit(c['$net']?.access ? 0 : 1)" 2>/dev/null; then
    echo "⏭  $net — no access config, skipping"
    SKIPPED+=("$net:no-config")
    continue
  fi

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  $net"
  echo "════════════════════════════════════════════════════════════"

  extra=$(get_extra_flags "$net")

  # Pick L1 vs L2 script
  if [[ "$net" == "ethereum" ]]; then
    ACCESS_SCRIPT="script/l1/GrantRoles.s.sol"
  else
    ACCESS_SCRIPT="script/l2/Factory.access.s.sol"
  fi

  echo "── Grant Roles ──"
  if NETWORK="$net" forge script "$ACCESS_SCRIPT" \
      --rpc-url "$rpc" $BROADCAST $extra; then
    echo "✓ Roles OK on $net"
    OK+=("$net")
  else
    echo "✗ Roles FAILED on $net"
    FAILED+=("$net")
  fi
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
if [[ -z "$BROADCAST" ]]; then
  echo "  Dry-run complete"
else
  echo "  Role grants complete"
fi
echo "════════════════════════════════════════════════════════════"

if [[ ${#OK[@]} -gt 0 ]]; then
  echo "OK: ${OK[*]}"
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "Skipped: ${SKIPPED[*]}"
fi

if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "All OK."
else
  echo "Failed:"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
