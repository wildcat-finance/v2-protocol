#!/usr/bin/env bash
# compatibility entrypoint for pre-generalization rehearsal commands.
set -euo pipefail

exec bash "$(dirname "$0")/ceremony-stage.sh" "$@"
