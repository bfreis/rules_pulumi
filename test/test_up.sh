#!/usr/bin/env bash
# A full run: stack init, config, up, outputs. Covers the prebuilt program, the
# working directory, data files, pinned providers, stack configuration written
# to the source tree, and the precedence of env, env_cmds and the shell.
source "$(dirname "$0")/testlib.sh"
setup

export PROBE_SHELL_ENV=from-shell PROBE_SHELL_CMD=from-shell

"$STACK" stack init dev
"$STACK" config set greeting hello
"$STACK" config set pet true
"$STACK" config set --secret token sekrit

# Checked before up, so a broken write-through fails here, by name.
config="$BUILD_WORKSPACE_DIRECTORY/program/Pulumi.dev.yaml"
[[ -f "$config" ]] || fail "stack configuration was not written to the source tree ($config)"
grep -q '^encryptionsalt: ' "$config" || fail "stack init did not write its salt to $config"
grep -q 'integration:greeting: hello' "$config" || fail "config set did not write to $config"
grep -q 'secure: ' "$config" || fail "the secret is not in $config"

"$STACK" up --yes --skip-preview --non-interactive

out() { "$STACK" stack output --show-secrets "$1"; }

expect_eq greeting hello "$(out greeting)"
expect_eq "secret token" sekrit "$(out token)"
expect_eq "data file read by relative path" "hello from data" "$(out data)"
[[ -n "$(out pet)" ]] || fail "the random provider created no pet"
cwd="$(out cwd)"
[[ "$cwd" == */_main/program ]] || fail "program cwd should be its package in runfiles, got $cwd"

expect_eq "env alone" from-env "$(out PROBE_ENV)"
expect_eq "env_cmds over env" from-cmd-1 "$(out PROBE_CMD)"
expect_eq "later env_cmds over earlier" from-cmd-2 "$(out PROBE_CMDS)"
expect_eq "shell over env" from-shell "$(out PROBE_SHELL_ENV)"
expect_eq "shell over env_cmds" from-shell "$(out PROBE_SHELL_CMD)"

# As bazel run starts it: the launcher beside its own runfiles tree, with an
# unrelated RUNFILES_DIR inherited from the caller. The program must get the
# launcher's runfiles, not the inherited ones.
link="$TEST_TMPDIR/bin/dev"
mkdir -p "$(dirname "$link")"
ln -s "$PWD/$STACK" "$link"
ln -s "$RUNFILES_DIR" "$link.runfiles"
RUNFILES_DIR=/nonexistent-inherited "$link" up --yes --skip-preview --non-interactive >/dev/null
expect_eq "the program's RUNFILES_DIR" "$link.runfiles" "$(out RUNFILES_DIR)"

[[ ! -e "$PULUMI_HOME/plugins" ]] || fail "Pulumi installed plugins: $(ls "$PULUMI_HOME/plugins")"
echo PASS
