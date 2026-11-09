#!/usr/bin/env bash
# A program that needs a provider nobody pinned must fail: Pulumi may not
# fetch one on its own.
source "$(dirname "$0")/testlib.sh"
setup

# A user who has run Pulumi before has plugins cached in their Pulumi home.
# Pulumi would load them; the launcher must keep them out of reach.
cached="$PULUMI_HOME/plugins/resource-random-v4.21.6"
mkdir -p "$cached"
cp "$CACHED_PLUGIN" "$cached/pulumi-resource-random"

"$STACK" stack init organization/integration/noprov
"$STACK" config set greeting hello
"$STACK" config set pet true
"$STACK" config set --secret token sekrit
[[ -f "$BUILD_WORKSPACE_DIRECTORY/program/Pulumi.noprov.yaml" ]] ||
    fail "a fully qualified stack should use its last component for the config file"

if output="$("$STACK" up --yes --skip-preview --non-interactive 2>&1)"; then
    fail "up succeeded without the provider pinned"
fi
grep -q "no resource plugin 'pulumi-resource-random' found" <<<"$output" ||
    fail "up failed for another reason: $output"
for home in "$XDG_CACHE_HOME"/rules_pulumi/*.pulumi-home; do
    [[ ! -e "$home/plugins" ]] || fail "a plugin landed in the launcher's Pulumi home: $(ls "$home/plugins")"
done
echo PASS
