"""pulumi_project: a Pulumi program built by Bazel, with its project file and providers."""

load(":provider.bzl", "PulumiProviderInfo")

PulumiProjectInfo = provider(
    doc = "A Pulumi project ready to run: the program, the project file template and the providers.",
    fields = {
        "template": "File: the project file, with runtime, main and plugins rewritten to point into runfiles " +
                    "(the runfiles root written as @@RUNFILES@@).",
        "config_dir": "The workspace-relative directory of the project file.",
        "stack_config_dir": "File: the project file's stackConfigDir, relative to config_dir, or empty.",
        "runfiles": "runfiles: everything the program and the CLI need at run time.",
    },
)

# Language runtimes whose Pulumi host can run a prebuilt executable through the
# `binary` runtime option. The others always build or interpret their sources.
_BINARY_RUNTIMES = ["go", "dotnet", "java"]

# Placeholder for the absolute runfiles root, filled in by the launcher.
RUNFILES_PLACEHOLDER = "@@RUNFILES@@"

def rlocation_path(ctx, f):
    """The path of a File relative to the runfiles root."""
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return ctx.workspace_name + "/" + f.short_path

def _package_rlocation(ctx, label):
    repo = label.repo_name or ctx.workspace_name
    return repo + "/" + label.package if label.package else repo

def _yaml_quote(s):
    return "'" + s.replace("'", "''") + "'"

# Each script starts by dropping a trailing \r, so CRLF files read like LF ones.

# Reads the top-level `runtime` of a project file and prints its name. Handles
# the scalar form (`runtime: go`), the block mapping and the flow mapping. In
# the block form only `name:` at the first level below `runtime:` counts.
_RUNTIME_AWK = r"""
{ sub(/\r$/, "") }
function emit(v) { gsub(/["']/, "", v); print v; exit }
/^runtime:/ {
    v = $0; sub(/^runtime:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v)
    if (v ~ /^\{/) {
        if (match(v, /name:[ \t]*["']?[A-Za-z0-9_-]+/)) {
            v = substr(v, RSTART, RLENGTH); sub(/^name:[ \t]*/, "", v); emit(v)
        }
        exit
    }
    if (v != "") emit(v)
    inrt = 1; next
}
inrt && /^[ \t]*(#.*)?$/ { next }
inrt && /^[^ \t]/ { exit }
inrt {
    match($0, /^[ \t]+/)
    if (!level) level = RLENGTH
    if (RLENGTH == level && $0 ~ /^[ \t]+name:/) {
        v = $0; sub(/^[ \t]+name:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); emit(v)
    }
}
"""

# Prints the top-level `stackConfigDir` of a project file, or nothing.
_STACK_CONFIG_DIR_AWK = r"""
{ sub(/\r$/, "") }
/^stackConfigDir:/ {
    v = $0; sub(/^stackConfigDir:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); gsub(/["']/, "", v)
    print v; exit
}
"""

# Copies a project file without the top-level keys the launcher replaces:
# runtime, main and plugins, and stackConfigDir, whose directory the launcher
# links instead. A top-level key starts in column 0; its value runs until the
# next one.
_STRIP_AWK = r"""
{ sub(/\r$/, "") }
/^[^ \t#]/ {
    key = $0; sub(/:.*$/, "", key)
    skip = (key == "runtime" || key == "main" || key == "plugins" || key == "stackConfigDir")
}
!skip { print }
"""

def _pulumi_project_impl(ctx):
    program = ctx.attr.program
    exe = ctx.executable.program

    names = {}
    providers = []
    for p in ctx.attr.providers:
        info = p[PulumiProviderInfo]
        if info.name in names:
            fail("providers: %s and %s are both the provider %s" % (names[info.name], p.label, info.name))
        names[info.name] = p.label
        providers.append(info)

    suffix_lines = [
        "runtime:",
        "  name: @@RUNTIME@@",
        "  options:",
        "    binary: " + _yaml_quote(RUNFILES_PLACEHOLDER + "/" + rlocation_path(ctx, exe)),
        "main: " + _yaml_quote(RUNFILES_PLACEHOLDER + "/" + _package_rlocation(ctx, program.label)),
    ]
    if providers:
        suffix_lines.append("plugins:")
        suffix_lines.append("  providers:")
        for info in sorted(providers, key = lambda i: i.name):
            plugin_dir = rlocation_path(ctx, info.plugin).rpartition("/")[0]
            suffix_lines.append("    - name: " + info.name)
            suffix_lines.append("      version: " + _yaml_quote(info.version))
            suffix_lines.append("      path: " + _yaml_quote(RUNFILES_PLACEHOLDER + "/" + plugin_dir))
    suffix = ctx.actions.declare_file(ctx.label.name + ".pulumi_suffix.yaml")
    ctx.actions.write(suffix, "\n".join(suffix_lines) + "\n")

    template = ctx.actions.declare_file(ctx.label.name + ".Pulumi.yaml.tmpl")
    stack_config_dir = ctx.actions.declare_file(ctx.label.name + ".stack_config_dir")
    ctx.actions.run_shell(
        inputs = [ctx.file.project_file, suffix],
        outputs = [template, stack_config_dir],
        command = """
set -eu
rt=$(awk '{runtime_awk}' "$1")
case "$rt" in
    {allowed}) ;;
    "") echo "$1: no top-level runtime found" >&2; exit 1 ;;
    *) echo "$1: runtime '$rt' cannot run a prebuilt program; pulumi_project supports {allowed_list}" >&2; exit 1 ;;
esac
{{ awk '{strip_awk}' "$1"; sed "s/@@RUNTIME@@/$rt/" "$2"; }} > "$3"
scd=$(awk '{scd_awk}' "$1")
scd=${{scd%/}}
case "/$scd/" in
    *//* | */../* | */./*) [ -z "$scd" ] || {{ echo "$1: stackConfigDir '$scd' must be a relative path below the project, without . or .." >&2; exit 1; }} ;;
esac
printf '%s' "$scd" > "$4"
""".format(
            runtime_awk = _RUNTIME_AWK.replace("'", "'\\''"),
            strip_awk = _STRIP_AWK.replace("'", "'\\''"),
            scd_awk = _STACK_CONFIG_DIR_AWK.replace("'", "'\\''"),
            allowed = "|".join(_BINARY_RUNTIMES),
            allowed_list = ", ".join(_BINARY_RUNTIMES),
        ),
        arguments = [ctx.file.project_file.path, suffix.path, template.path, stack_config_dir.path],
        mnemonic = "PulumiProjectFile",
        progress_message = "Writing the Pulumi project file for %{label}",
    )

    runfiles = ctx.runfiles(files = [template, stack_config_dir] + [p.plugin for p in providers] + ctx.files.data)
    runfiles = runfiles.merge(program[DefaultInfo].default_runfiles)
    for d in ctx.attr.data:
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)

    return [
        PulumiProjectInfo(
            template = template,
            stack_config_dir = stack_config_dir,
            # Stack configuration is written next to the project file, in the
            # source tree, so it must be a source file of the main repository.
            config_dir = ctx.file.project_file.dirname if (
                ctx.file.project_file.is_source and ctx.file.project_file.owner.repo_name == ""
            ) else None,
            runfiles = runfiles,
        ),
        DefaultInfo(files = depset([template])),
        OutputGroupInfo(stack_config_dir = depset([stack_config_dir])),
    ]

pulumi_project_rule = rule(
    implementation = _pulumi_project_impl,
    doc = "A Pulumi project whose program Bazel builds.",
    attrs = {
        "program": attr.label(
            mandatory = True,
            executable = True,
            cfg = "target",
            doc = "The program Pulumi runs, as an executable (a go_binary, for one). " +
                  "It runs with its own package in runfiles as working directory, " +
                  "so files it opens by relative path belong in its data.",
        ),
        "project_file": attr.label(
            mandatory = True,
            allow_single_file = ["Pulumi.yaml", "Pulumi.yml"],
            doc = "The checked-in Pulumi.yaml. Its runtime, main and plugins are replaced, and stackConfigDir " +
                  "is honoured by the launcher; everything else is kept.",
        ),
        "providers": attr.label_list(
            providers = [PulumiProviderInfo],
            doc = "The provider plugins the program may load, usually `@pulumi_provider_<name>`. " +
                  "Pulumi will not load any other.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "More files the program reads at run time, besides its own data.",
        ),
    },
)

def pulumi_project(name, project_file = "Pulumi.yaml", **kwargs):
    """A Pulumi project whose program Bazel builds.

    Args:
      name: the target name.
      project_file: the checked-in Pulumi.yaml; defaults to the one in this package.
      **kwargs: program, providers, data, and the common attributes.
    """
    pulumi_project_rule(name = name, project_file = project_file, **kwargs)
