#!/usr/bin/env bash
set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────────
# Dry-run (simulate on all chains, no broadcast):
#   PRIVATE_KEY=0x... DEPLOY_VERSION=v1 bash script/deploy-l2-all.sh
#
# Real deployment:
#   PRIVATE_KEY=0x... DEPLOY_VERSION=v1 bash script/deploy-l2-all.sh --broadcast

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
: "${DEPLOY_VERSION:?Set DEPLOY_VERSION env var (e.g. v1)}"

# ── Broadcast flag ────────────────────────────────────────────────────
BROADCAST=""
if [[ "${1:-}" == "--broadcast" ]]; then
  BROADCAST="--broadcast"
  echo "MODE: broadcast (real deployment)"
else
  echo "MODE: dry-run (simulation only, pass --broadcast to deploy)"
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

# ── Extra forge flags per network (e.g. higher gas estimate for EIP-7623 chains) ──
get_extra_flags() {
  local net="$1"
  case "$net" in
    megaeth) echo "--skip-simulation" ;;
    *)       echo "" ;;
  esac
}

# ── Deploy ────────────────────────────────────────────────────────────
FAILED=()
OK=()

for net in "${NETWORKS[@]}"; do
  rpc=$(get_rpc "$net")
  if [[ -z "$rpc" ]]; then
    echo "⏭  $net — RPC not set, skipping"
    continue
  fi

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  $net"
  echo "════════════════════════════════════════════════════════════"

  extra=$(get_extra_flags "$net")

  # ── CompressedOracleV1 ──
  echo "── CompressedOracleV1 ──"
  if NETWORK="$net" forge script script/l2/DeployCompressedOracle.s.sol \
      --rpc-url "$rpc" $BROADCAST $extra; then
    echo "✓ CompressedOracle OK on $net"
  else
    echo "✗ CompressedOracle FAILED on $net"
    FAILED+=("$net:compressed")
  fi

  OK+=("$net")
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
if [[ -z "$BROADCAST" ]]; then
  echo "  Dry-run complete"
else
  echo "  Deployment complete"
fi
echo "════════════════════════════════════════════════════════════"

if [[ ${#OK[@]} -gt 0 ]]; then
  echo "Networks processed: ${OK[*]}"
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
