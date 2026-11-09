#!/usr/bin/env bash
# env_cmds failures stop the run, and never print what the command printed:
# it may be a secret.
source "$(dirname "$0")/testlib.sh"

STACK="$BAD_LINE_STACK" setup
if output="$("$BAD_LINE_STACK" stack ls 2>&1)"; then
    fail "a line that is not KEY=VALUE was accepted"
fi
grep -q "printed a line that is not KEY=VALUE" <<<"$output" || fail "unexpected error: $output"
if grep -q "SECRET-LOOKING" <<<"$output"; then
    fail "the offending line was echoed: $output"
fi

STACK="$RESERVED_STACK" setup
if output="$("$RESERVED_STACK" stack ls 2>&1)"; then
    fail "an env_cmds line naming a launcher variable was accepted"
fi
grep -q "names starting with _ are reserved: _work" <<<"$output" || fail "unexpected error: $output"

STACK="$FAILING_STACK" setup
if output="$("$FAILING_STACK" stack ls 2>&1)"; then
    fail "a failing env_cmds command did not stop the run"
fi
grep -q "exited with status 3" <<<"$output" || fail "unexpected error: $output"
echo PASS
