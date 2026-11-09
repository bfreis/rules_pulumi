#!/usr/bin/env bash
# A stack reference writes and checks the outputs of a stack it has no project
# for, given only the stack's name and backend.
source "$(dirname "$0")/testlib.sh"
setup
[[ -x "$REF" ]] || fail "harness: no launcher at $REF"

"$STACK" stack init dev
"$STACK" config set greeting hello
"$STACK" config set --secret token sekrit
"$STACK" up --yes --skip-preview --non-interactive

file="$BUILD_WORKSPACE_DIRECTORY/ref/dev_outputs.bzl"
mkdir -p "$(dirname "$file")"
"$REF"
[[ -f "$file" ]] || fail "the reference did not write $file"
grep -q '"greeting": "hello"' "$file" || fail "the outputs file lacks greeting: $(cat "$file")"
grep -q '"token": "\[secret\]"' "$file" || fail "the secret output is not a placeholder"
if grep -q sekrit "$file"; then
    fail "the secret's value is in the outputs file"
fi
grep -q 'bazel run //ref:integration_dev$' "$file" || fail "the header does not say how to regenerate: $(head -8 "$file")"

"$REF" --check || fail "--check failed on a fresh outputs file"
"$STACK" config set greeting changed
"$STACK" up --yes --skip-preview --non-interactive
if "$REF" --check 2>/dev/null; then
    fail "--check passed after the stack's outputs changed"
fi
"$REF"
grep -q '"greeting": "changed"' "$file" || fail "the reference did not rewrite the file"

if "$REF" preview 2>/dev/null; then
    fail "a stack reference ran a Pulumi command other than reading outputs"
fi

work="$(ls -d "$XDG_CACHE_HOME"/rules_pulumi/ref_integration_dev-*)"
[[ -z "$(ls -A "$work")" ]] || fail "the reference's directory is not empty: $(ls -A "$work")"
echo PASS
