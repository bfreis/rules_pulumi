# Shared setup for the integration tests. Source it, then call setup.
set -euo pipefail

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# expect_eq NAME EXPECTED ACTUAL
expect_eq() {
    [[ "$3" == "$2" ]] || fail "$1: expected '$2', got '$3'"
}

# Runs the launcher under test with the environment a user's shell would give
# it, all of it inside the test's own temporary directory.
setup() {
    local t="$TEST_TMPDIR"
    export HOME="$t/home"
    export PULUMI_HOME="$t/pulumi-home"
    export XDG_CACHE_HOME="$t/cache"
    export PULUMI_BACKEND_URL="file://$t/state"
    export PULUMI_CONFIG_PASSPHRASE=integration-test
    # A dead proxy: any attempt to download a plugin fails loudly instead of
    # quietly succeeding.
    export HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 NO_PROXY=
    # What bazel run would set: where stack configuration is written.
    export BUILD_WORKSPACE_DIRECTORY="$t/workspace"
    mkdir -p "$HOME" "$t/state" "$BUILD_WORKSPACE_DIRECTORY/program"

    # Until a Pulumi release lets a prebuilt Go program run without the Go
    # toolchain (pulumi/pulumi#25585), the Go language host needs `go` on PATH.
    [[ -x "$GO_BIN" ]] || fail "harness: no go binary at $GO_BIN"
    PATH="$(cd "$(dirname "$GO_BIN")" && pwd):$PATH"
    export PATH

    [[ -x "$STACK" ]] || fail "harness: no launcher at $STACK"
}
