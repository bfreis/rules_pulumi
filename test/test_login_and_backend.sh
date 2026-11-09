#!/usr/bin/env bash
# The launcher's own Pulumi home still sees the user's login, and a backend
# named in the BUILD file is not overridden by the shell.
source "$(dirname "$0")/testlib.sh"
setup

# A login made with the plain Pulumi CLI, in the user's Pulumi home.
state="file://$TEST_TMPDIR/state"
mkdir -p "$PULUMI_HOME"
cat >"$PULUMI_HOME/credentials.json" <<JSON
{"current": "$state", "accessTokens": {"$state": ""}}
JSON
unset PULUMI_BACKEND_URL
"$STACK" stack init dev || fail "the user's login was not visible to the launcher"
"$STACK" stack ls | grep -q '^dev' || fail "the stack is not in the logged-in backend"

export PULUMI_BACKEND_URL="$state"
if output="$("$FIXED_STACK" stack ls 2>&1)"; then
    fail "the shell's PULUMI_BACKEND_URL overrode the BUILD file's backend"
fi
grep -q "nonexistent-fixed-backend" <<<"$output" || fail "unexpected error: $output"
echo PASS
