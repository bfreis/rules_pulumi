#!/usr/bin/env bash
# A project file's stackConfigDir puts stack configuration in that directory of
# the source tree.
source "$(dirname "$0")/testlib.sh"
setup
mkdir -p "$BUILD_WORKSPACE_DIRECTORY/scd/config"

"$STACK" stack init dev
"$STACK" config set greeting hello
"$STACK" config set --secret token sekrit
config="$BUILD_WORKSPACE_DIRECTORY/scd/config/Pulumi.dev.yaml"
[[ -f "$config" ]] || fail "stack configuration is not in stackConfigDir ($config)"
grep -q 'integration:greeting: hello' "$config" || fail "config set did not write to $config"
[[ ! -e "$BUILD_WORKSPACE_DIRECTORY/scd/Pulumi.dev.yaml" ]] || fail "configuration also landed beside the project file"
"$STACK" up --yes --skip-preview --non-interactive
expect_eq greeting hello "$("$STACK" stack output greeting)"
echo PASS
