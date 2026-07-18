#!/usr/bin/env bash
# Configure the production oracles on a network (idempotent — safe to re-run):
#   reconcile BOTH oracles' approved-factory allow-list to the configured desired set — removing
#   factories no longer listed and adding new ones
#   (networks.json <net>.access.approvedFactories, or APPROVED_FACTORIES="0x..,0x.." to override).
# The oracles are registrationless — there is no REGISTRAR_ROLE and no feed registration step.
#
#   PRIVATE_KEY=0x... NETWORK=base ./script/configure-oracles.sh              # dry-run (no broadcast)
#   PRIVATE_KEY=0x... NETWORK=base BROADCAST=1 ./script/configure-oracles.sh  # broadcast
#
# The broadcaster MUST hold ADMIN_ROLE on both oracles (the original deployer/owner does).
set -euo pipefail
: "${PRIVATE_KEY:?set PRIVATE_KEY}"
export NETWORK="${NETWORK:-base}"

BROADCAST_FLAG=""
[ "${BROADCAST:-0}" = "1" ] && BROADCAST_FLAG="--broadcast"

echo "════════════════════ configure oracles: $NETWORK ════════════════════"
forge script script/l2/ConfigureOracles.s.sol \
  --rpc-url "$NETWORK" $BROADCAST_FLAG

echo "done — $NETWORK: factories reconciled."
