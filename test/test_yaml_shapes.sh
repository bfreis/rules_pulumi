#!/usr/bin/env bash
# The project file template for a CRLF Pulumi.yaml with a decoy name.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
grep -q $'\r' "$TEMPLATE" && fail "the template kept CR characters"
grep -q '^  name: go$' "$TEMPLATE" || fail "runtime not detected as go: $(cat "$TEMPLATE")"
grep -q 'name: decoy' "$TEMPLATE" && fail "the decoy runtime block was kept: $(cat "$TEMPLATE")"
grep -q '^stackConfigDir' "$TEMPLATE" && fail "stackConfigDir was kept in the template"
grep -q '^description: CRLF line endings' "$TEMPLATE" || fail "other keys were not kept"
[[ "$(cat "$SCD")" == config ]] || fail "stackConfigDir read as '$(cat "$SCD")', not 'config'"
echo PASS
