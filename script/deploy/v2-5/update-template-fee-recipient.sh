#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${RPC_URL:?RPC_URL is required in .env or the shell}"

export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia

script='script/deploy/v2-5/update-template-fee-recipient.s.sol:UpdateTemplateFeeRecipientV25'

case "${1:-}" in
  --check)
    CHECK_ONLY=true forge script "$script" --rpc-url "$RPC_URL" --non-interactive
    ;;
  --broadcast)
    : "${PVT_KEY:?PVT_KEY is required in .env or the shell}"
    : "${DEPLOYER_ADDRESS:?DEPLOYER_ADDRESS is required in .env or the shell}"
    CHECK_ONLY=false forge script "$script" --rpc-url "$RPC_URL" --broadcast --non-interactive
    CHECK_ONLY=true forge script "$script" --rpc-url "$RPC_URL" --non-interactive
    ;;
  *)
    echo 'usage: update-template-fee-recipient.sh <--check|--broadcast>' >&2
    exit 1
    ;;
esac
