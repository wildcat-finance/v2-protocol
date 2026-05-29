#!/usr/bin/env bash
# ============================================================================
# deploy-4626-factory-sepolia.sh
#
# All-in-one script: installs prerequisites if missing, then deploys
# Wildcat4626WrapperFactory.sol to Sepolia testnet.
#
# Required environment variables (set in .env or export before running):
#   SEPOLIA_RPC_URL       - Sepolia JSON-RPC endpoint (e.g. from Alchemy/Infura)
#   DEPLOYER_PRIVATE_KEY  - Private key of the deploying wallet (with Sepolia ETH)
#   ETHERSCAN_API_KEY     - (Optional) Etherscan API key for contract verification
#
# Usage (run from Git Bash on Windows):
#   bash script/deploy-4626-factory-sepolia.sh
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ARCH_CONTROLLER="0xC003f20F2642c76B81e5e1620c6D8cdEE826408f"
NETWORK_NAME="Sepolia"
CHAIN_ID=11155111
FOUNDRY_MIN_DATE="2024"  # Minimum acceptable forge build year

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "[*] $*"; }
warn()  { echo "[!] $*"; }
err()   { echo "[ERROR] $*" >&2; }
ask()   { read -r -p "[?] $* [y/N] " ans; [[ "$ans" =~ ^[Yy] ]]; }

# ---------------------------------------------------------------------------
# Resolve project root
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Load .env if present
# ---------------------------------------------------------------------------
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  info "Loading .env from project root..."
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo " Wildcat4626WrapperFactory — $NETWORK_NAME "
echo "============================================"
echo ""

# ============================= PREREQUISITES ==============================

# ---------------------------------------------------------------------------
# 1. Git
# ---------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  err "git is not installed."
  echo ""
  echo "  Git is required and must be installed manually:"
  echo "    https://git-scm.com/download/win"
  echo ""
  echo "  After installing, close and reopen Git Bash, then re-run this script."
  exit 1
fi
info "Git found: $(git --version)"

# ---------------------------------------------------------------------------
# 2. curl (needed for foundry installer)
# ---------------------------------------------------------------------------
if ! command -v curl &>/dev/null; then
  err "curl is not installed."
  echo "  curl is required to install Foundry. It ships with Git Bash by default."
  echo "  If you are not using Git Bash, install curl or switch to Git Bash."
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Foundry / forge — install or update if needed
# ---------------------------------------------------------------------------
FOUNDRY_BIN="${FOUNDRY_DIR:-$HOME/.foundry}/bin"

ensure_foundry_in_path() {
  # Add foundry bin to PATH for the current session if not already there
  if ! echo "$PATH" | tr ':' '\n' | grep -q "foundry"; then
    if [[ -d "$FOUNDRY_BIN" ]]; then
      export PATH="$FOUNDRY_BIN:$PATH"
      info "Added $FOUNDRY_BIN to PATH for this session."
    fi
  fi
}

install_foundry() {
  info "Installing Foundry..."
  echo ""

  # Download and run foundryup installer
  curl -L https://foundry.paradigm.xyz | bash

  # The installer script adds foundryup to FOUNDRY_BIN but does not run it.
  # We need to ensure PATH includes it, then run foundryup.
  ensure_foundry_in_path

  if ! command -v foundryup &>/dev/null; then
    # Fallback: check the default location directly
    if [[ -x "$FOUNDRY_BIN/foundryup" ]]; then
      export PATH="$FOUNDRY_BIN:$PATH"
    else
      err "foundryup was not found after installation."
      echo "  Try closing and reopening Git Bash, then re-run this script."
      exit 1
    fi
  fi

  info "Running foundryup to install forge, cast, anvil, chisel..."
  echo ""
  foundryup
  echo ""

  ensure_foundry_in_path
}

update_foundry() {
  info "Updating Foundry to latest version..."
  ensure_foundry_in_path

  if command -v foundryup &>/dev/null; then
    foundryup
  elif [[ -x "$FOUNDRY_BIN/foundryup" ]]; then
    "$FOUNDRY_BIN/foundryup"
  else
    warn "foundryup not found — reinstalling Foundry from scratch."
    install_foundry
    return
  fi

  echo ""
  ensure_foundry_in_path
}

# Check if forge is available
ensure_foundry_in_path

if ! command -v forge &>/dev/null; then
  warn "forge is not installed."
  echo ""
  if ask "Install Foundry now?"; then
    install_foundry
  else
    err "Cannot continue without forge. Install Foundry and re-run."
    exit 1
  fi

  # Final check after install
  if ! command -v forge &>/dev/null; then
    err "forge still not found after installation."
    echo "  Close and reopen Git Bash, then re-run this script."
    exit 1
  fi
fi

# Display version and check if it's recent enough
FORGE_VERSION_STR=$(forge --version 2>&1 | head -1)
info "Forge version: $FORGE_VERSION_STR"

# Check if the build is from 2024 or later (simple heuristic on the date in version string)
if ! echo "$FORGE_VERSION_STR" | grep -qE "20(2[4-9]|[3-9][0-9])"; then
  warn "Your forge version appears to be older than $FOUNDRY_MIN_DATE."
  echo ""
  if ask "Update Foundry to the latest version?"; then
    update_foundry
    FORGE_VERSION_STR=$(forge --version 2>&1 | head -1)
    info "Forge version (updated): $FORGE_VERSION_STR"
  else
    warn "Continuing with current version. Build or deploy may fail if too outdated."
  fi
fi

# ========================= ENVIRONMENT VARIABLES ==========================

MISSING=()
[[ -z "${SEPOLIA_RPC_URL:-}" ]]      && MISSING+=("SEPOLIA_RPC_URL")
[[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]  && MISSING+=("DEPLOYER_PRIVATE_KEY")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  err "Missing required environment variables:"
  for var in "${MISSING[@]}"; do
    echo "         - $var"
  done
  echo ""
  echo "  Create a .env file in the project root ($PROJECT_ROOT/.env) with:"
  echo ""
  echo "    SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY"
  echo "    DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY"
  echo "    ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY  (optional, for verification)"
  echo ""
  exit 1
fi

# Etherscan API key is optional — warn if missing
VERIFY=true
if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
  warn "ETHERSCAN_API_KEY is not set. Contract will be deployed but NOT verified."
  warn "You can verify manually later (see troubleshooting in the runsheet)."
  VERIFY=false
fi

# ============================ PRE-FLIGHT =================================

echo ""
info "Checking RPC connectivity..."
BLOCK=$(cast block-number --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null) || true
if [[ "$BLOCK" =~ ^[0-9]+$ ]]; then
  info "RPC is live — Sepolia block height: $BLOCK"
else
  err "Could not reach Sepolia RPC."
  echo "  Check your SEPOLIA_RPC_URL in .env (make sure there are no quotes around the value)."
  exit 1
fi

DEPLOYER_ADDR=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY" 2>/dev/null) || true
if [[ "$DEPLOYER_ADDR" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  info "Deployer address: $DEPLOYER_ADDR"
else
  err "Could not derive address from DEPLOYER_PRIVATE_KEY."
  echo "  Make sure the key starts with 0x and is a valid 64-hex-char private key."
  exit 1
fi

BALANCE_WEI=$(cast balance "$DEPLOYER_ADDR" --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null) || true
BALANCE_ETH=$(cast from-wei "$BALANCE_WEI" 2>/dev/null) || BALANCE_ETH="unknown"
info "Deployer balance: $BALANCE_ETH ETH"

if [[ "$BALANCE_WEI" =~ ^0$ ]] || [[ "$BALANCE_WEI" == "0" ]]; then
  err "Deployer wallet has 0 ETH on Sepolia. Fund it first."
  echo "  Faucets:"
  echo "    https://www.alchemy.com/faucets/ethereum-sepolia"
  echo "    https://sepoliafaucet.com"
  exit 1
fi

# ============================ DEPLOY =====================================

echo ""
echo "--------------------------------------------"
info "Deploying Wildcat4626WrapperFactory"
echo "    Network        : $NETWORK_NAME (chain $CHAIN_ID)"
echo "    ArchController : $ARCH_CONTROLLER"
echo "    Deployer       : $DEPLOYER_ADDR"
echo "--------------------------------------------"
echo ""

if [[ "$VERIFY" == true ]]; then
  forge create \
    src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --chain "$CHAIN_ID" \
    --verify \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --constructor-args "$ARCH_CONTROLLER"
else
  forge create \
    src/vault/Wildcat4626WrapperFactory.sol:Wildcat4626WrapperFactory \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --chain "$CHAIN_ID" \
    --broadcast \
    --constructor-args "$ARCH_CONTROLLER"
fi

echo ""
echo "============================================"
echo " Deployment complete on $NETWORK_NAME!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Note the 'Deployed to:' address printed above."
if [[ "$VERIFY" == true ]]; then
  echo "  2. Confirm verification on https://sepolia.etherscan.io"
else
  echo "  2. Verify the contract manually (see runsheet Section 14 — Troubleshooting)."
fi
echo "  3. Record the address in deployments/sepolia/deployments.json"
echo ""
