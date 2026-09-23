#!/usr/bin/env bash
# Backward-compatible alias: the canonical one-command entrypoint is
# ./run_tests.sh (kept as a separate name to satisfy the completion contract).
exec "$(dirname "$0")/run_tests.sh" "$@"
