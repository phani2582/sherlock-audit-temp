#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
  cat <<EOF
Register feeds in PythOracle from a JSON config or XScanTokens file.

── CLI mode ─────────────────────────────────────────────────────────
  $(basename "$0") \\
    --oracle      0x... \\
    --tokens-file XScanTokens/base.tokens.json \\
    --rpc-url     http://...

── Config mode ──────────────────────────────────────────────────────
  $(basename "$0") --config script/config/base/feeds.json --rpc-url http://...

Options:
  --oracle        PythOracle address
  --tokens-file   Path to XScanTokens JSON
  --config        Path to feeds.json (contains oracle + tokens)
  --rpc-url       RPC endpoint (required)
  --private-key   Oracle owner private key (or set PRIVATE_KEY env)
  --broadcast     Send transactions (default: dry-run)
  --verify        Verify contracts on explorer
  -h, --help      Show this help

EOF
  exit 0
}

# ── defaults ───────────────────────────────────────────────────────
ORACLE="" TOKENS_FILE="" CONFIG="" RPC_URL="" BROADCAST="" VERIFY=""
PK="${PRIVATE_KEY:-}"

EXTRA_ARGS=()

# ── parse args ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --oracle)       ORACLE="$2";      shift 2 ;;
    --tokens-file)  TOKENS_FILE="$2"; shift 2 ;;
    --config)       CONFIG="$2";      shift 2 ;;
    --rpc-url)      RPC_URL="$2";     shift 2 ;;
    --private-key)  PK="$2";         shift 2 ;;
    --broadcast)    BROADCAST="--broadcast"; shift ;;
    --verify)       VERIFY="--verify";       shift ;;
    -h|--help)      usage ;;
    *)              EXTRA_ARGS+=("$1"); shift ;;
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
  if [[ -z "$ORACLE" ]]; then
    echo "error: --oracle is required (or use --config)" >&2; exit 1
  fi
  if [[ -z "$TOKENS_FILE" ]]; then
    echo "error: --tokens-file is required (or use --config)" >&2; exit 1
  fi
  if [[ ! -f "$TOKENS_FILE" ]]; then
    echo "error: tokens file not found: $TOKENS_FILE" >&2; exit 1
  fi
fi

# ── run ────────────────────────────────────────────────────────────
export PRIVATE_KEY="$PK"

if [[ -n "$CONFIG" ]]; then
  export CONFIG
else
  export ORACLE
  export TOKENS_FILE
fi

forge script "$ROOT_DIR/script/l2/RegisterFeeds.s.sol" \
  --rpc-url "$RPC_URL" \
  $BROADCAST $VERIFY \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
