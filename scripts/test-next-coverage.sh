#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

spherex_source='src/spherex/SphereXProtectedRegisteredBase.sol'
coverage_patch='docs/coverage-spherex.patch'
patch_applied=false

restore_spherex_source() {
  if [[ "$patch_applied" == true ]]; then
    git apply -R "$coverage_patch"
    patch_applied=false
  fi
}

if ! git diff --quiet -- "$spherex_source" || \
  ! git diff --cached --quiet -- "$spherex_source"; then
  echo "error: $spherex_source already has uncommitted changes" >&2
  exit 1
fi

git apply --check "$coverage_patch"
git apply "$coverage_patch"
patch_applied=true
trap restore_spherex_source EXIT

set +e
FOUNDRY_PROFILE=test-next-coverage \
FOUNDRY_FUZZ_RUNS=32 \
FOUNDRY_INVARIANT_RUNS=8 \
FOUNDRY_INVARIANT_DEPTH=15 \
forge coverage \
  --block-timestamp 1724284800 \
  --fuzz-seed 0x5eed \
  --no-match-coverage '(^test-next/|^lib/)' \
  --report summary \
  "$@"
coverage_status=$?
set -e

restore_spherex_source
trap - EXIT

if ! git diff --quiet -- "$spherex_source" || \
  ! git diff --cached --quiet -- "$spherex_source"; then
  echo "error: failed to restore $spherex_source" >&2
  exit 1
fi

exit "$coverage_status"
