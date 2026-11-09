"""Repository rules that download Pulumi releases and expose them to Bazel."""

load(":versions.bzl", "PLATFORMS")

_TOOLCHAIN_BZL = Label("//pulumi/private:toolchain.bzl")
_PROVIDER_BZL = Label("//pulumi/private:provider.bzl")
_TOOLCHAIN_TYPE = Label("//pulumi:toolchain_type")

def _platform_setting(platform):
    return str(Label("//pulumi/private:platform_" + platform))

def _pulumi_cli_repository_impl(rctx):
    v = rctx.attr.version
    rctx.download_and_extract(
        url = "https://github.com/pulumi/pulumi/releases/download/v{v}/pulumi-v{v}-{p}.tar.gz".format(
            v = v,
            p = rctx.attr.platform,
        ),
        sha256 = rctx.attr.sha256,
        stripPrefix = "pulumi",
    )
    rctx.file("BUILD.bazel", """\
load("{bzl}", "pulumi_toolchain")

pulumi_toolchain(
    name = "toolchain_impl",
    pulumi = "pulumi",
    files = glob(["pulumi-*"]),
    version = "{v}",
    visibility = ["//visibility:public"],
)
""".format(bzl = str(_TOOLCHAIN_BZL), v = v))

pulumi_cli_repository = repository_rule(
    implementation = _pulumi_cli_repository_impl,
    doc = "Downloads one Pulumi CLI release for one platform.",
    attrs = {
        "version": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
        "sha256": attr.string(mandatory = True),
    },
)

def _pulumi_toolchains_repository_impl(rctx):
    out = []
    for platform in sorted(PLATFORMS.keys()):
        out.append("""\
toolchain(
    name = "{p}",
    target_compatible_with = {c},
    toolchain = "@{repo}//:toolchain_impl",
    toolchain_type = "{tt}",
)
""".format(
            p = platform,
            c = repr(PLATFORMS[platform].constraints),
            repo = rctx.attr.cli_repo_prefix + platform.replace("-", "_"),
            tt = str(_TOOLCHAIN_TYPE),
        ))
    rctx.file("BUILD.bazel", "\n".join(out))

pulumi_toolchains_repository = repository_rule(
    implementation = _pulumi_toolchains_repository_impl,
    doc = "Declares one Pulumi toolchain per platform; register them with `@<name>//:all`.",
    attrs = {
        "cli_repo_prefix": attr.string(mandatory = True),
    },
)

def _pulumi_provider_platform_repository_impl(rctx):
    name, v = rctx.attr.provider_name, rctx.attr.version
    rctx.download_and_extract(
        url = "https://github.com/{r}/releases/download/v{v}/pulumi-resource-{n}-v{v}-{p}.tar.gz".format(
            r = rctx.attr.repository,
            n = name,
            v = v,
            p = rctx.attr.plugin_platform,
        ),
        sha256 = rctx.attr.sha256,
        # The archive also holds a README and a LICENSE. Only the executable is
        # exported: Pulumi is handed the directory it sits in, and that
        # directory (in runfiles) should hold the plugin and nothing else.
        output = "archive",
    )
    binary = "pulumi-resource-" + name
    if not rctx.path("archive/" + binary).exists:
        fail("the {r} release v{v} for {p} has no {b} at the top of its archive".format(
            r = rctx.attr.repository,
            v = v,
            p = rctx.attr.plugin_platform,
            b = binary,
        ))
    rctx.symlink("archive/" + binary, "plugin/" + binary)
    rctx.file("BUILD.bazel", """\
filegroup(
    name = "plugin",
    srcs = ["plugin/{b}"],
    visibility = ["//visibility:public"],
)
""".format(b = binary))

pulumi_provider_platform_repository = repository_rule(
    implementation = _pulumi_provider_platform_repository_impl,
    doc = "Downloads one provider plugin release for one platform.",
    attrs = {
        "provider_name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "repository": attr.string(mandatory = True),
        "plugin_platform": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
    },
)

def _pulumi_provider_repository_impl(rctx):
    branches = {}
    for platform in sorted(PLATFORMS.keys()):
        branches[_platform_setting(platform)] = "@{prefix}{p}//:plugin".format(
            prefix = rctx.attr.platform_repo_prefix,
            p = platform.replace("-", "_"),
        )
    rctx.file("BUILD.bazel", """\
load("{bzl}", "pulumi_provider")

pulumi_provider(
    name = "{repo}",
    provider_name = "{n}",
    version = "{v}",
    plugin = select({branches}),
    visibility = ["//visibility:public"],
)

alias(
    name = "provider",
    actual = ":{repo}",
    visibility = ["//visibility:public"],
)
""".format(
        bzl = str(_PROVIDER_BZL),
        repo = rctx.attr.hub_name,
        n = rctx.attr.provider_name,
        v = rctx.attr.version,
        branches = repr(branches),
    ))

pulumi_provider_repository = repository_rule(
    implementation = _pulumi_provider_repository_impl,
    doc = "Exposes one pinned provider as `@<name>`, picking the plugin for the target platform.",
    attrs = {
        "hub_name": attr.string(mandatory = True),
        "provider_name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "platform_repo_prefix": attr.string(mandatory = True),
    },
)
