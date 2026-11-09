# rules_pulumi

[![CI](https://github.com/bfreis/rules_pulumi/actions/workflows/ci.yml/badge.svg)](https://github.com/bfreis/rules_pulumi/actions/workflows/ci.yml)

Bazel rules for running [Pulumi](https://www.pulumi.com/) stacks whose program
Bazel builds.

Bazel builds the program, and `bazel run` deploys it with a Pulumi CLI and
provider plugins that are downloaded and checked like any other dependency:

```
bazel run //infra:prod -- preview
bazel run //infra:prod -- up
bazel run //infra:prod -- config set aws:region us-west-2
```

Nothing is installed by hand and nothing is fetched while Pulumi runs: the CLI
comes from a pinned release, providers come only from the versions you pin, and
Pulumi's own plugin downloads are switched off.

## Setup

rules_pulumi has no release on the Bazel Central Registry yet. Until it does,
depend on a commit of this repository from your root module:

```starlark
bazel_dep(name = "rules_pulumi", version = "0.0.0")
git_override(
    module_name = "rules_pulumi",
    remote = "https://github.com/bfreis/rules_pulumi.git",
    commit = "...",  # a commit of the main branch
)

pulumi = use_extension("@rules_pulumi//pulumi:extensions.bzl", "pulumi")
pulumi.provider(name = "aws", version = "7.21.0")
use_repo(pulumi, "pulumi_provider_aws")
```

The CLI toolchain is registered by rules_pulumi itself. To choose its version:

```starlark
pulumi.toolchain(version = "3.274.1")
```

## Usage

```starlark
load("@rules_go//go:def.bzl", "go_binary")
load("@rules_pulumi//pulumi:defs.bzl", "pulumi_project", "pulumi_stack")

go_binary(
    name = "program",
    srcs = ["main.go"],
    data = glob(["dashboards/*.json"]),
    deps = [
        "@com_github_pulumi_pulumi_aws_sdk_v7//go/aws/s3",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

pulumi_project(
    name = "project",
    program = ":program",
    providers = ["@pulumi_provider_aws"],
)

pulumi_stack(
    name = "prod",
    project = ":project",
    stack = "prod",
    backend = "s3://my-state-bucket?region=us-west-2",
    env = {"AWS_PROFILE": "deploy"},
)
```

Everything after `--` goes to `pulumi`, for that stack. The stack's
configuration, `Pulumi.prod.yaml`, stays where it is: beside the checked-in
`Pulumi.yaml` (or in its `stackConfigDir`), and every command, `stack init` and
`config set` included, reads and writes that file. Pulumi itself runs in a
directory of the launcher's, where that file is linked in; `stack rm` and
`stack rename` therefore leave the checked-in file alone.

## Rules

### `pulumi_project`

A Pulumi project whose program Bazel builds.

| Attribute | Description |
|-----------|-------------|
| `program` | The program, as an executable target (`go_binary`, for one). Required. |
| `project_file` | The checked-in `Pulumi.yaml`. Defaults to the one in the package. |
| `providers` | The provider plugins the program may load, usually `@pulumi_provider_<name>`. Pulumi will not load any other. |
| `data` | More files the program reads at run time, besides its own `data`. |

The program runs with its own package, inside runfiles, as working directory,
the way a test does. A program that opens `dashboards/app.json` by relative
path finds it there as long as the file is in the program's `data`.

### `pulumi_stack`

One stack of a project. `bazel run` it with Pulumi arguments after `--`.

| Attribute | Description |
|-----------|-------------|
| `project` | The `pulumi_project`. Required. |
| `stack` | The stack name: `prod`, or `organization/project/prod`. Its last component names the configuration file. Required. |
| `backend` | The state backend URL. When set, it is fixed: a `PULUMI_BACKEND_URL` in the shell does not override it. When unset, the backend comes from the environment or `pulumi login`. A `file://` backend must be absolute. |
| `env` | Environment defaults for the run. Not for secrets: BUILD files are not secret. Paths must be absolute. |
| `env_cmds` | Shell commands run before Pulumi, from the workspace root, each printing `KEY=VALUE` lines. |
| `outputs_file` | A `.bzl` file name, in the package, to keep the stack's outputs in. See [Outputs](#outputs). |

#### Environment

From lowest precedence to highest:

1. `env`,
2. the output of `env_cmds`, in order, so a later command wins,
3. whatever the calling shell already exports.

Secrets belong in the shell or in `env_cmds`. A passphrase, for instance:

```starlark
env_cmds = ["p=$(op read op://Vault/pulumi/passphrase) && echo PULUMI_CONFIG_PASSPHRASE=$p"],
```

or `PULUMI_CONFIG_PASSPHRASE_FILE`, or a KMS secrets provider in the stack
configuration, which needs no passphrase at all. A short-lived token:

```starlark
env_cmds = ["t=$(aws rds generate-db-auth-token --hostname db.example.com --port 5432 --username admin) && echo DB_TOKEN=$t"],
```

Write them so that a failure of the inner command fails the whole command, as
above: `echo X=$(cmd)` succeeds even when `cmd` fails, and would hand Pulumi an
empty value. A failing command stops the run. The launcher never prints what a
command printed, so a malformed line does not end up in a terminal or a CI log.
Values are a single line each. Names starting with `_` are reserved.

Paths in the environment must be absolute: `env_cmds` run in the workspace
root, but Pulumi and the program run in a directory of their own.

Some variables are set by the launcher whatever the shell says:

- `PULUMI_STACK`: the target is the stack.
- `PULUMI_BACKEND_URL`, when `backend` is set.
- `PULUMI_HOME`: a directory of the target's own, with no plugins in it and
  your `credentials.json` linked in, so `pulumi login` still applies. Pulumi
  would otherwise load any plugin cached in your Pulumi home.
- `PULUMI_DISABLE_AUTOMATIC_PLUGIN_ACQUISITION` and
  `PULUMI_IGNORE_AMBIENT_PLUGINS`: together with the above, plugins come from
  the pinned providers only.
- `RUNFILES_DIR`: the run's runfiles, for programs that use a runfiles library.

## Outputs

Other targets often need a stack's outputs: a role ARN in a Kubernetes
manifest, a bucket name in an app's configuration. With `outputs_file`, the
stack keeps them in a `.bzl` file in the source tree, and BUILD files use them
like any other constant, without credentials and without running Pulumi:

```starlark
pulumi_stack(
    name = "prod",
    project = ":project",
    stack = "prod",
    outputs_file = "prod_outputs.bzl",
)
```

```starlark
# k8s/BUILD.bazel
load("//infra:prod_outputs.bzl", "OUTPUTS")

genrule(
    name = "serviceaccount",
    srcs = ["serviceaccount.yaml"],
    outs = ["rendered/serviceaccount.yaml"],
    cmd = "sed 's|ROLE_ARN_PLACEHOLDER|%s|' $< > $@" % OUTPUTS["appRoleArn"],
)
```

The file is written after every successful `up` and `destroy`, and on demand:

```
bazel run //infra:prod.outputs             # write it
bazel run //infra:prod.outputs -- --check  # fail if it is stale, for CI
```

Commit it, like a lockfile. It holds what `pulumi stack output --json` prints,
so a secret output appears only as `"[secret]"`, never as its value: such
outputs are left out of `OUTPUTS`, and their names are listed in
`SECRET_OUTPUTS`.

Load it from other packages, not the stack's own: a package cannot load a file
that does not exist yet, which it does not before the first write.

### Stacks from other repositories

A stack whose program lives elsewhere (shared infrastructure, managed in
another repository) can still have its outputs in a file here. Pulumi reads a
stack's outputs from the backend alone, so `pulumi_stack_reference` needs no
program and no providers: only the stack's fully qualified name, the backend,
and what the backend needs to be read.

```starlark
load("@rules_pulumi//pulumi:defs.bzl", "pulumi_stack_reference")

pulumi_stack_reference(
    name = "shared",
    stack = "organization/shared-infra/prod",
    backend = "s3://my-state-bucket?region=us-west-2",
    env = {"AWS_PROFILE": "deploy"},
    outputs_file = "shared_outputs.bzl",
)
```

```
bazel run //network:shared             # write shared_outputs.bzl
bazel run //network:shared -- --check  # fail if it is stale
```

It takes `backend`, `env` and `env_cmds` as `pulumi_stack` does, and runs no
other Pulumi command.

## Providers

```starlark
pulumi.provider(name = "random", version = "4.21.6")
use_repo(pulumi, "pulumi_provider_random")
```

The version must equal the version of the provider's SDK the program is built
against (`github.com/pulumi/pulumi-random/sdk/v4 v4.21.6` in `go.mod`): a Pulumi
program asks for exactly the provider version its SDK was generated for. On a
mismatch, the run stops before touching any resource with
`no resource plugin 'pulumi-resource-random' found in the workspace at version v...`.

The archives are checked against sha256 digests. By default these come from the
GitHub release (the providers' own checksums files list SHA-1 sums only), and
are recorded in `MODULE.bazel.lock` on Bazel versions with module extension
facts (8.8 and 9 have them), so each release is looked up once. To pin them yourself, or for a provider whose release assets have no
digest:

```starlark
pulumi.provider(
    name = "random",
    version = "4.21.6",
    sha256s = {
        "darwin-arm64": "...",
        "darwin-x64": "...",
        "linux-arm64": "...",
        "linux-x64": "...",
    },
)
```

A provider published outside the `pulumi` organization takes
`repository = "owner/name"`.

## How it works

Pulumi's Go, .NET and Java hosts can run a prebuilt executable through the
`binary` runtime option. `pulumi_project` copies the checked-in `Pulumi.yaml`,
replaces its `runtime`, `main` and `plugins` keys, and keeps everything else.
At run time, the launcher writes that project file into a directory of its own,
links `Pulumi.<stack>.yaml` there to the file in the source tree, and runs the
CLI on it.

## Go dependencies

A Pulumi program in the same Bazel module as the rest of the code shares one
set of Go dependency versions with it: gazelle's `go_deps` picks, for each Go
module, the highest version anything in the build graph asks for. That is
usually fine. Put the program's `go.mod` in a `go.work` beside the main one and
read the workspace with `go_deps.from_file(go_work = ...)`.

When the Pulumi SDK's dependencies must not move the rest of the code's, give
the program a separate, isolated set:

```starlark
go_deps_infra = use_extension("@gazelle//:extensions.bzl", "go_deps", isolate = True)
go_deps_infra.from_file(go_mod = "//infra:go.mod")
use_repo(
    go_deps_infra,
    infra_pulumi_sdk = "com_github_pulumi_pulumi_sdk_v3",
)
```

This needs `--experimental_isolated_extension_usages`, and the program cannot
then import Go packages from the main set. A separate Bazel module for the
program does not help: as soon as either module depends on the other, the two
sets are merged again.

`gazelle:proto disable` in `go_deps.gazelle_default_attributes` keeps gazelle
from generating proto rules for the SDKs, which ship their generated code
already, and spares a build of `protoc`.

## Requirements and limitations

- Bazel 8 or later.
- macOS and Linux, on arm64 and x86-64. The launcher is a bash script.
- Programs in Go, .NET or Java: the runtimes whose hosts can run a prebuilt
  executable.
- Pulumi 3.274.1 and earlier still need a `go` executable on `PATH` to run a
  prebuilt Go program, though nothing compiles it
  ([pulumi/pulumi#25585](https://github.com/pulumi/pulumi/pull/25585) lifts
  this). `bazel run` passes the shell's `PATH` through.

## License

Apache License 2.0. See [LICENSE](LICENSE).
