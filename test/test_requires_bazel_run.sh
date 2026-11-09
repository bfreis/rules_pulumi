#!/usr/bin/env bash
# Outside bazel run there is no source tree to write stack configuration to.
source "$(dirname "$0")/testlib.sh"
setup
unset BUILD_WORKSPACE_DIRECTORY

if output="$("$STACK" stack ls 2>&1)"; then
    fail "the launcher ran without BUILD_WORKSPACE_DIRECTORY"
fi
grep -q "BUILD_WORKSPACE_DIRECTORY is not set" <<<"$output" || fail "unexpected error: $output"
echo PASS
