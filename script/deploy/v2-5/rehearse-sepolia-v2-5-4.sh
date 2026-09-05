#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
export SEPOLIA_REPLACEMENT_CONFIG='deployments/sepolia/v2-5-4.json'
exec bash script/deploy/v2-5/rehearse-sepolia-fix-1.sh "$@"
