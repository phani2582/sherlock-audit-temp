#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
  cat <<EOF
Deploy PythOracle.

── CLI mode ─────────────────────────────────────────────────────────
  $(basename "$0") \\
    --pyth-lazer            0x... \\
    --max-time-drift        60 \\
    --usd-feed-id           8 \\
    --rpc-url               http://...

── Config mode ──────────────────────────────────────────────────────
  $(basename "$0") --config script/config/base/oracle.json --rpc-url http://...

Options:
  --pyth-lazer             PythLazer proxy address
  --max-time-drift         Max timestamp drift in seconds
  --usd-feed-id            Pyth Lazer USDT feed id (uint32, typically 8)
  --config                 Path to oracle.json config file
  --rpc-url                RPC endpoint (required)
  --private-key            Deployer private key (or set PRIVATE_KEY env)
  --broadcast              Send transactions (default: dry-run)
  -h, --help               Show this help

EOF
  exit 0
}

# ── defaults ───────────────────────────────────────────────────────
PYTH_LAZER="" MAX_TIME_DRIFT="" USD_FEED_ID=""
CONFIG="" RPC_URL="" BROADCAST=""
PK="${PRIVATE_KEY:-}"

EXTRA_ARGS=()

# ── parse args ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pyth-lazer)            PYTH_LAZER="$2";            shift 2 ;;
    --max-time-drift)        MAX_TIME_DRIFT="$2";        shift 2 ;;
    --usd-feed-id)           USD_FEED_ID="$2";           shift 2 ;;
    --config)                CONFIG="$2";                shift 2 ;;
    --rpc-url)               RPC_URL="$2";               shift 2 ;;
    --private-key)           PK="$2";                   shift 2 ;;
    --broadcast)             BROADCAST="--broadcast";    shift ;;
    -h|--help)               usage ;;
    *)                       EXTRA_ARGS+=("$1");         shift ;;
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
  if [[ ! -f "$CONFIG" ]]; then
    echo "error: config file not found: $CONFIG" >&2; exit 1
  fi
else
  for var in PYTH_LAZER MAX_TIME_DRIFT USD_FEED_ID; do
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
  export PYTH_LAZER
  export MAX_TIME_DRIFT
  export USD_CONVERSION_FEED_ID="$USD_FEED_ID"
fi

forge script "$ROOT_DIR/script/l2/DeployPythOracle.s.sol" \
  --rpc-url "$RPC_URL" \
  $BROADCAST \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
