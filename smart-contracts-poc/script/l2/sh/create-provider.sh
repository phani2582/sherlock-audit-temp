#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
  cat <<EOF
Create PriceProvider(s) via the factory.

── Single provider mode ─────────────────────────────────────────────
  $(basename "$0") \\
    --factory  0x... \\
    --oracle   0x... \\
    --feed-id  631 \\
    --cex-step 400000000000000 \\
    --max-time-delta   10 \\
    --future-tolerance 5 \\
    --rpc-url  http://...

── Batch mode (config file) ─────────────────────────────────────────
  $(basename "$0") --config script/config/base/providers.json --rpc-url http://...

Options:
  --factory           PriceProviderFactory address
  --oracle            Offchain oracle (PythOracle) address
  --feed-id           Pyth Lazer feed id (uint256)
  --cex-step          CEX step in 1e18-based BPS
  --max-time-delta    Max staleness in seconds
  --future-tolerance  L2 sequencer skew tolerance in seconds
  --config            Path to JSON config file (batch mode)
  --rpc-url           RPC endpoint (required)
  --private-key       Deployer private key (or set PRIVATE_KEY env)
  --broadcast         Send transactions (default: dry-run)
  -h, --help          Show this help

EOF
  exit 0
}

# ── defaults ───────────────────────────────────────────────────────
FACTORY="" ORACLE="" FEED_ID="" CEX_STEP="" MAX_TIME_DELTA="" FUTURE_TOLERANCE=""
CONFIG="" RPC_URL="" BROADCAST=""
PK="${PRIVATE_KEY:-}"

EXTRA_ARGS=()

# ── parse args ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --factory)           FACTORY="$2";          shift 2 ;;
    --oracle)            ORACLE="$2";           shift 2 ;;
    --feed-id)           FEED_ID="$2";          shift 2 ;;
    --cex-step)          CEX_STEP="$2";         shift 2 ;;
    --max-time-delta)    MAX_TIME_DELTA="$2";   shift 2 ;;
    --future-tolerance)  FUTURE_TOLERANCE="$2"; shift 2 ;;
    --config)            CONFIG="$2";           shift 2 ;;
    --rpc-url)           RPC_URL="$2";          shift 2 ;;
    --private-key)       PK="$2";              shift 2 ;;
    --broadcast)         BROADCAST="--broadcast"; shift ;;
    -h|--help)           usage ;;
    *)                   EXTRA_ARGS+=("$1");    shift ;;
  esac
done

# ── validate ───────────────────────────────────────────────────────
if [[ -z "$RPC_URL" ]]; then
  echo "error: --rpc-url is required" >&2; exit 1
fi
if [[ -z "$PK" ]]; then
  echo "error: --private-key or PRIVATE_KEY env is required" >&2; exit 1
fi

if [[ -n "$CONFIG" ]]; then
  # batch mode
  if [[ ! -f "$CONFIG" ]]; then
    echo "error: config file not found: $CONFIG" >&2; exit 1
  fi
else
  # single mode — all fields required
  for var in FACTORY ORACLE FEED_ID CEX_STEP MAX_TIME_DELTA FUTURE_TOLERANCE; do
    if [[ -z "${!var}" ]]; then
      echo "error: --$(echo "$var" | tr '_' '-' | tr '[:upper:]' '[:lower:]') is required (or use --config)" >&2
      exit 1
    fi
  done
fi

# ── run ────────────────────────────────────────────────────────────
export PRIVATE_KEY="$PK"

if [[ -n "$CONFIG" ]]; then
  export CONFIG
else
  export FACTORY ORACLE FEED_ID CEX_STEP MAX_TIME_DELTA FUTURE_TOLERANCE
fi

forge script "$ROOT_DIR/script/l2/CreatePriceProvider.s.sol" \
  --rpc-url "$RPC_URL" \
  $BROADCAST \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
