"""The Pulumi CLI toolchain."""

def _pulumi_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        pulumi = ctx.file.pulumi,
        # The language hosts ship beside the CLI, and the CLI looks for them
        # next to itself, so they have to travel with it in runfiles.
        files = depset([ctx.file.pulumi] + ctx.files.files),
        version = ctx.attr.version,
    )]

pulumi_toolchain = rule(
    implementation = _pulumi_toolchain_impl,
    doc = "A Pulumi CLI, with the language hosts and plugins of its release.",
    attrs = {
        "pulumi": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The `pulumi` executable.",
        ),
        "files": attr.label_list(
            allow_files = True,
            doc = "The other executables of the release (language hosts, bundled plugins).",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "The version of the release, without a leading v.",
        ),
    },
)
