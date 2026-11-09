"""Module extension that downloads the Pulumi CLI and pinned provider plugins.

    pulumi = use_extension("@rules_pulumi//pulumi:extensions.bzl", "pulumi")
    pulumi.toolchain(version = "3.274.1")              # optional; root module wins
    pulumi.provider(name = "aws", version = "7.21.0")  # one per provider
    use_repo(pulumi, "pulumi_provider_aws")
"""

load(
    "//pulumi/private:repositories.bzl",
    "pulumi_cli_repository",
    "pulumi_provider_platform_repository",
    "pulumi_provider_repository",
    "pulumi_toolchains_repository",
)
load("//pulumi/private:versions.bzl", "DEFAULT_PULUMI_VERSION", "PLATFORMS", "PULUMI_VERSIONS")

_CLI_REPO_PREFIX = "pulumi_cli_"

def _version_key(v):
    return [int(p) for p in v.split(".")]

def _pick_cli_version(mctx):
    root = []
    others = []
    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            (root if mod.is_root else others).append(tag.version)
    if len(root) > 1:
        fail("pulumi.toolchain: the root module sets the version %d times; set it once" % len(root))
    candidates = root or others or [DEFAULT_PULUMI_VERSION]
    for version in candidates:
        if version not in PULUMI_VERSIONS:
            fail("pulumi.toolchain: rules_pulumi does not know Pulumi %s. Known versions: %s" % (
                version,
                ", ".join(sorted(PULUMI_VERSIONS.keys(), key = _version_key)),
            ))
    return sorted(candidates, key = _version_key)[-1]

def _provider_hub_name(name):
    return "pulumi_provider_" + name.replace("-", "_")

def _collect_providers(mctx):
    """Returns {name: tag}. The root module's pin wins; other conflicts are errors."""
    chosen = {}
    origin = {}
    for mod in mctx.modules:
        mine = {}
        for tag in mod.tags.provider:
            if tag.name in mine and mine[tag.name].version != tag.version:
                fail("pulumi.provider: %s pins %s twice, to %s and to %s" % (
                    mod.name,
                    tag.name,
                    mine[tag.name].version,
                    tag.version,
                ))
            mine[tag.name] = tag
        for name, tag in mine.items():
            prev = chosen.get(name)
            if prev == None:
                chosen[name] = tag
                origin[name] = mod
            elif prev.version != tag.version and not origin[name].is_root:
                fail("pulumi.provider: %s is pinned to %s by %s and to %s by %s; pin it in the root module to choose" % (
                    name,
                    prev.version,
                    origin[name].name,
                    tag.version,
                    mod.name,
                ))
    return chosen

def _asset_name(name, version, platform):
    return "pulumi-resource-{n}-v{v}-{p}.tar.gz".format(n = name, v = version, p = PLATFORMS[platform].plugin)

def _published_sha256s(mctx, repository, name, version):
    """Reads the sha256 of each platform's archive from the GitHub release.

    The providers' own checksums files hold SHA-1 sums, which Bazel cannot pin
    a download to. GitHub computes a sha256 digest of every release asset it
    stores, and the releases API reports it.
    """
    url = "https://api.github.com/repos/{r}/releases/tags/v{v}".format(r = repository, v = version)
    out = "releases/%s-%s.json" % (repository.replace("/", "_"), version)
    mctx.download(url = url, output = out)
    digests = {}
    for asset in json.decode(mctx.read(out)).get("assets", []):
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            digests[asset["name"]] = digest[len("sha256:"):]
    result = {}
    for platform in PLATFORMS.keys():
        asset = _asset_name(name, version, platform)
        if asset not in digests:
            fail(("pulumi.provider %s: GitHub reports no sha256 digest for %s in %s (assets uploaded " +
                  "before GitHub computed digests have none); pass sha256s instead") % (name, asset, url))
        result[platform] = digests[asset]
    return result

def _pulumi_impl(mctx):
    version = _pick_cli_version(mctx)
    for platform in PLATFORMS.keys():
        pulumi_cli_repository(
            name = _CLI_REPO_PREFIX + platform.replace("-", "_"),
            version = version,
            platform = platform,
            sha256 = PULUMI_VERSIONS[version][platform],
        )
    pulumi_toolchains_repository(
        name = "pulumi_toolchains",
        cli_repo_prefix = _CLI_REPO_PREFIX,
    )

    # Digests read from GitHub are kept as facts in MODULE.bazel.lock, so each
    # release is looked up once rather than on every evaluation (the releases
    # API allows few unauthenticated calls). Older Bazel versions have no facts.
    has_facts = hasattr(mctx, "facts")
    facts = {}
    for name, tag in _collect_providers(mctx).items():
        repository = tag.repository or "pulumi/pulumi-" + name
        if tag.sha256s:
            missing = [p for p in PLATFORMS.keys() if p not in tag.sha256s]
            if missing:
                fail("pulumi.provider %s: sha256s has no entry for %s" % (name, ", ".join(missing)))
            sha256s = tag.sha256s
        else:
            key = "provider/%s/%s" % (repository, tag.version)
            sha256s = mctx.facts.get(key) if has_facts else None
            if not sha256s:
                sha256s = _published_sha256s(mctx, repository, name, tag.version)
            facts[key] = sha256s
        hub = _provider_hub_name(name)
        for platform, info in PLATFORMS.items():
            pulumi_provider_platform_repository(
                name = hub + "_" + platform.replace("-", "_"),
                provider_name = name,
                version = tag.version,
                repository = repository,
                plugin_platform = info.plugin,
                sha256 = sha256s[platform],
            )
        pulumi_provider_repository(
            name = hub,
            hub_name = hub,
            provider_name = name,
            version = tag.version,
            platform_repo_prefix = hub + "_",
        )

    if has_facts:
        return mctx.extension_metadata(reproducible = False, facts = facts)
    return mctx.extension_metadata(reproducible = False)

_toolchain = tag_class(
    doc = "Chooses the Pulumi CLI version. The root module's choice wins; otherwise the highest asked for.",
    attrs = {
        "version": attr.string(
            default = DEFAULT_PULUMI_VERSION,
            doc = "A version listed in rules_pulumi's version table, without a leading v.",
        ),
    },
)

_provider = tag_class(
    doc = """Pins a resource provider plugin. Creates the repository `pulumi_provider_<name>`
(dashes become underscores), whose default target goes in `pulumi_project.providers`.""",
    attrs = {
        "name": attr.string(
            mandatory = True,
            doc = "The provider's name, as in pulumi-resource-<name> (aws, random, ...).",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "The version, without a leading v. It must equal the version of the provider SDK the program is built against.",
        ),
        "repository": attr.string(
            doc = "The GitHub repository that publishes the plugin, as owner/name. Defaults to pulumi/pulumi-<name>.",
        ),
        "sha256s": attr.string_dict(
            doc = "The sha256 of the archive for each platform (darwin-arm64, darwin-x64, linux-arm64, linux-x64). " +
                  "Leave empty to read them from the GitHub release (kept in MODULE.bazel.lock where Bazel supports extension facts).",
        ),
    },
)

pulumi = module_extension(
    implementation = _pulumi_impl,
    doc = "Downloads the Pulumi CLI and pinned provider plugins.",
    tag_classes = {
        "toolchain": _toolchain,
        "provider": _provider,
    },
)
