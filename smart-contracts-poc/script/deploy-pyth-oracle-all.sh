#!/usr/bin/env bash
set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────────
# Deploys BOTH oracle providers per chain: PythOracle and ChainlinkOracle
# (Data Streams). Each is a separate CREATE3 deployment with its own address.
#
# Dry-run (simulate on all chains, no broadcast):
#   PRIVATE_KEY=0x... DEPLOY_VERSION=v1 bash script/deploy-pyth-oracle-all.sh
#
# Real deployment:
#   PRIVATE_KEY=0x... DEPLOY_VERSION=v1 bash script/deploy-pyth-oracle-all.sh --broadcast
#
# Per-provider auto-skip (handled by the Solidity scripts):
#   • PythOracle      — skipped where PYTH_LAZER (0xACeA761c27A909d4D3895128EBe6370FDE2dF481)
#                       has no deployed code.
#   • ChainlinkOracle — skipped where the chain has no Data Streams config
#                       (.{network}.oracle.chainlink.verifierProxy) or the configured
#                       verifierProxy has no code on-chain.

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

# ── Extra forge flags per network ─────────────────────────────────────
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
SKIPPED=()

for net in "${NETWORKS[@]}"; do
  rpc=$(get_rpc "$net")
  if [[ -z "$rpc" ]]; then
    echo "⏭  $net — RPC not set, skipping"
    SKIPPED+=("$net")
    continue
  fi

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  $net"
  echo "════════════════════════════════════════════════════════════"

  extra=$(get_extra_flags "$net")

  echo "── PythOracle ──"
  if NETWORK="$net" forge script script/l2/DeployPythOracle.s.sol \
      --rpc-url "$rpc" $BROADCAST $extra; then
    echo "✓ PythOracle OK on $net"
    OK+=("$net:pyth")
  else
    echo "✗ PythOracle FAILED on $net"
    FAILED+=("$net:pyth")
  fi

  echo "── ChainlinkOracle ──"
  if NETWORK="$net" forge script script/l2/DeployChainlinkOracle.s.sol \
      --rpc-url "$rpc" $BROADCAST $extra; then
    echo "✓ ChainlinkOracle OK on $net"
    OK+=("$net:cl")
  else
    echo "✗ ChainlinkOracle FAILED on $net"
    FAILED+=("$net:cl")
  fi
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
  echo "OK: ${OK[*]}"
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "Skipped (no RPC): ${SKIPPED[*]}"
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
