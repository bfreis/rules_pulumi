#!/usr/bin/env bash
# An outputs file loads in a BUILD file with every JSON type intact, and with
# secrets left out of OUTPUTS.
set -euo pipefail
expected='{"OUTPUTS":{"count":3,"enabled":true,"greeting":"hello","missing":null,"names":["a","b"],"nested":{"path":"C:\\dir","quote":"it'"'"'s \"quoted\""}},"SECRET_OUTPUTS":["token"]}'
actual="$(cat "$LOADED")"
if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: loaded outputs differ" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
fi
echo PASS
