#!/usr/bin/env bash
# wt test runner. Sandboxed (own fixture + herdr stub on PATH); never touches user's real repos/herdr.
#
# Timing on M-class macOS (85 tests):
#   sequential:    ~3-4 min
#   --jobs 2:      ~1m27s
#   --jobs 4:      ~45s    (default)
#   --jobs 8:      ~26s   (fastest, occasionally flaky under sustained load)
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$*" == *--jobs* ]]; then exec bats "$@" test_*.bats; else exec bats --jobs 4 "$@" test_*.bats; fi
