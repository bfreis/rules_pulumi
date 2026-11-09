"""A Pulumi resource provider plugin, pinned to one version."""

PulumiProviderInfo = provider(
    doc = "A provider plugin that a Pulumi program may load.",
    fields = {
        "name": "The provider's name, as in pulumi-resource-<name>.",
        "version": "The provider's version, without a leading v.",
        "plugin": "The pulumi-resource-<name> executable, alone in its directory.",
    },
)

def _pulumi_provider_impl(ctx):
    plugin = ctx.file.plugin
    expected = "pulumi-resource-" + ctx.attr.provider_name
    if plugin.basename != expected:
        fail("provider %s: the plugin must be named %s, not %s" % (ctx.label, expected, plugin.basename))
    return [
        PulumiProviderInfo(
            name = ctx.attr.provider_name,
            version = ctx.attr.version,
            plugin = plugin,
        ),
        DefaultInfo(files = depset([plugin])),
    ]

pulumi_provider = rule(
    implementation = _pulumi_provider_impl,
    doc = "Declares a provider plugin binary and the version it is. " +
          "The module extension creates these; write one by hand only for a plugin it cannot download.",
    attrs = {
        "provider_name": attr.string(
            mandatory = True,
            doc = "The provider's name, as in pulumi-resource-<name>.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "The version the plugin is. Pulumi matches it exactly against the version the program asks for.",
        ),
        "plugin": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The pulumi-resource-<name> executable.",
        ),
    },
)
