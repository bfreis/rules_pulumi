"""Pulumi CLI releases the toolchain can download, with their sha256 sums.

Each entry comes from the release's own checksums file
(https://github.com/pulumi/pulumi/releases/download/v<VERSION>/pulumi-<VERSION>-checksums.txt).
Keys of the inner dicts are the platform names in the release asset names.
"""

DEFAULT_PULUMI_VERSION = "3.274.1"

PULUMI_VERSIONS = {
    "3.274.1": {
        "darwin-arm64": "053f2b243d09dfc2e83bacd9921f4a5d365bb8804cdc19fa09fb5a1240eb171b",
        "darwin-x64": "82be2e37c030737404b2ec6a5581ec76095c824c822b802a22579a95431ff376",
        "linux-arm64": "3deec71250f46c8f63e2b1f2078b08f5a8df4815d0e5e141420eb4e7f072f36e",
        "linux-x64": "32ae6d09d0df51637db7a0affb3ceb7d0511093b22d477aff5f20214d0b7e471",
    },
}

# Platforms the rules support, keyed by the name the CLI release uses. Each
# value gives the Bazel constraints that select it, and the name the same
# platform has in provider plugin releases (which spell x86-64 "amd64").
PLATFORMS = {
    "darwin-arm64": struct(
        constraints = ["@platforms//os:macos", "@platforms//cpu:aarch64"],
        plugin = "darwin-arm64",
    ),
    "darwin-x64": struct(
        constraints = ["@platforms//os:macos", "@platforms//cpu:x86_64"],
        plugin = "darwin-amd64",
    ),
    "linux-arm64": struct(
        constraints = ["@platforms//os:linux", "@platforms//cpu:aarch64"],
        plugin = "linux-arm64",
    ),
    "linux-x64": struct(
        constraints = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
        plugin = "linux-amd64",
    ),
}
