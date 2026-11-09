"""pulumi_stack: `bazel run` the Pulumi CLI on one stack of a project."""

load(":project.bzl", "PulumiProjectInfo", "rlocation_path")

_TOOLCHAIN_TYPE = Label("//pulumi:toolchain_type")

def _sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _check_env_name(name, attr):
    if name.startswith("_"):
        fail("%s: %r: names starting with _ are reserved for the launcher" % (attr, name))
    ok = name != "" and not name[0].isdigit()
    for c in name.elems():
        if not (c.isalnum() or c == "_"):
            ok = False
    if not ok:
        fail("%s: %r is not a valid environment variable name" % (attr, name))

_OUTPUTS_TEMPLATE = """\
\"\"\"Outputs of the Pulumi stack {stack}, from {label}.

Written by rules_pulumi; do not edit. Regenerate with:

    bazel run {outputs_label}

Secret outputs are not in OUTPUTS: their names are in SECRET_OUTPUTS, and
their values are not in this file.
\"\"\"

_RAW = json.decode(r'''
@@OUTPUTS_JSON@@
''')

OUTPUTS = {{k: v for k, v in _RAW.items() if v != "[secret]"}}

SECRET_OUTPUTS = sorted([k for k, v in _RAW.items() if v == "[secret]"])
"""

def _env_substitutions(ctx):
    defaults = {}
    for k, v in ctx.attr.env.items():
        _check_env_name(k, "env")
        defaults[k] = v
    defaults.setdefault("PULUMI_SKIP_UPDATE_CHECK", "true")
    return {
        "@@ENV_DEFAULTS@@": "\n".join([
            "_default %s %s" % (_sh_quote(k), _sh_quote(defaults[k]))
            for k in sorted(defaults.keys())
        ]),
        "@@ENV_CMDS@@": "_env_cmds=(%s)" % " ".join([_sh_quote(c) for c in ctx.attr.env_cmds]),
    }

def _outputs_template(ctx, outputs_file, stack, label, outputs_label):
    """Declares the .bzl template the launcher fills with the stack's outputs."""
    if "/" in outputs_file or not outputs_file.endswith(".bzl"):
        fail("outputs_file: %r must be a file name ending in .bzl, in this package" % outputs_file)
    template = ctx.actions.declare_file(ctx.label.name + ".outputs.bzl.tmpl")
    ctx.actions.write(template, _OUTPUTS_TEMPLATE.format(
        stack = stack,
        label = label,
        outputs_label = outputs_label,
    ))
    return template

def _check_backend(backend):
    # Pulumi runs in a directory of the launcher's, not the workspace, so a
    # relative file:// backend would put state somewhere unexpected.
    if backend.startswith("file://"):
        path = backend[len("file://"):]
        if not (path.startswith("/") or path.startswith("~")):
            fail("backend: %r is relative; a file:// backend must be absolute (file:///...) or under ~ (file://~/...)" % backend)

def _launcher(ctx, stack, project, outputs_file, outputs_template, outputs_label, outputs_only):
    """Writes the launcher; returns its DefaultInfo.

    project is None for a stack reference: then only the outputs file can be
    written, and no project directory is set up.
    """
    toolchain = ctx.toolchains[_TOOLCHAIN_TYPE]
    work_name = "".join([c if c.isalnum() else "_" for c in (ctx.label.package + "_" + ctx.label.name).elems()])
    outputs_rel = ""
    if outputs_file:
        outputs_rel = ctx.label.package + "/" + outputs_file if ctx.label.package else outputs_file

    _check_backend(ctx.attr.backend)
    label = "//%s:%s" % (ctx.label.package, ctx.label.name)
    substitutions = {
        # In a comment only; stripped of newlines so it cannot end the comment.
        "@@LABEL@@": label.replace("\n", " "),
        "@@STACK_DISPLAY@@": stack.replace("\n", " "),
        "@@WORK_NAME@@": work_name,
        "@@HAS_PROJECT@@": "true" if project else "false",
        "@@OUTPUTS_ONLY@@": "true" if outputs_only else "false",
        "@@LABEL_Q@@": _sh_quote(label),
        "@@STACK_Q@@": _sh_quote(stack),
        "@@PULUMI_Q@@": _sh_quote(rlocation_path(ctx, toolchain.pulumi)),
        "@@TEMPLATE_Q@@": _sh_quote(rlocation_path(ctx, project.template) if project else ""),
        "@@CONFIG_DIR_Q@@": _sh_quote(project.config_dir if project else ""),
        "@@STACK_CONFIG_DIR_Q@@": _sh_quote(rlocation_path(ctx, project.stack_config_dir) if project else ""),
        "@@STACK_FILE_Q@@": _sh_quote(stack.split("/")[-1] if project else ""),
        "@@BACKEND_Q@@": _sh_quote(ctx.attr.backend),
        "@@OUTPUTS_PATH_Q@@": _sh_quote(outputs_rel),
        "@@OUTPUTS_LABEL_Q@@": _sh_quote(outputs_label),
        "@@OUTPUTS_TEMPLATE_Q@@": _sh_quote(rlocation_path(ctx, outputs_template) if outputs_template else ""),
    }
    substitutions.update(_env_substitutions(ctx))

    launcher = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = launcher,
        is_executable = True,
        substitutions = substitutions,
    )
    runfiles = ctx.runfiles(
        files = [outputs_template] if outputs_template else [],
        transitive_files = toolchain.files,
    )
    if project:
        runfiles = runfiles.merge(project.runfiles)
    return DefaultInfo(executable = launcher, runfiles = runfiles)

def _pulumi_stack_impl(ctx):
    project = ctx.attr.project[PulumiProjectInfo]
    if project.config_dir == None:
        fail("project %s: the project file must be a source file of the main repository, " % ctx.attr.project.label +
             "because stack configuration is written beside it")
    stack = ctx.attr.stack
    if not stack.split("/")[-1]:
        fail("stack: %r has no stack name" % stack)

    outputs_template = None
    outputs_label = ""
    if ctx.attr.outputs_file:
        base = ctx.label.name[:-len(".outputs")] if ctx.attr.outputs_only else ctx.label.name
        outputs_label = "//%s:%s.outputs" % (ctx.label.package, base)
        outputs_template = _outputs_template(
            ctx,
            ctx.attr.outputs_file,
            stack,
            "//%s:%s" % (ctx.label.package, base),
            outputs_label,
        )
    elif ctx.attr.outputs_only:
        fail("outputs_only needs outputs_file")

    return [_launcher(
        ctx,
        stack,
        project,
        ctx.attr.outputs_file,
        outputs_template,
        outputs_label,
        ctx.attr.outputs_only,
    )]

def _pulumi_stack_reference_impl(ctx):
    stack = ctx.attr.stack
    if len(stack.split("/")) != 3 or "" in stack.split("/"):
        fail("stack: %r must be fully qualified, as organization/project/stack: " % stack +
             "outside its project, Pulumi cannot tell which project a bare name belongs to")
    label = "//%s:%s" % (ctx.label.package, ctx.label.name)
    outputs_template = _outputs_template(ctx, ctx.attr.outputs_file, stack, label, label)
    return [_launcher(
        ctx,
        stack,
        None,
        ctx.attr.outputs_file,
        outputs_template,
        label,
        True,
    )]

_COMMON_ATTRS = {
    "backend": attr.string(
        doc = "The state backend URL (`s3://bucket`, `file:///abs/path`). When set, it is fixed: " +
              "a PULUMI_BACKEND_URL in the calling shell does not override it. When unset, " +
              "the backend comes from env, env_cmds, the shell, or `pulumi login`.",
    ),
    "env": attr.string_dict(
        doc = "Environment defaults for the run. Never put secrets here; " +
              "a variable the calling shell already exports wins. Paths must be absolute: " +
              "Pulumi runs in a directory of its own, not the workspace.",
    ),
    "env_cmds": attr.string_list(
        doc = "Shell commands run before Pulumi, in the workspace root, each printing KEY=VALUE lines. " +
              "Later lines win over earlier ones and over env; a variable the calling shell already exports " +
              "wins over all of them. Use them for secrets and short-lived tokens.",
    ),
    "_launcher": attr.label(
        default = Label("//pulumi/private:launcher.sh.tpl"),
        allow_single_file = True,
    ),
}

pulumi_stack_rule = rule(
    implementation = _pulumi_stack_impl,
    doc = """One stack of a Pulumi project, run with the hermetic Pulumi CLI.

    bazel run //infra:prod -- preview
    bazel run //infra:prod -- up
    bazel run //infra:prod -- config set aws:region us-west-2

Arguments after `--` go to `pulumi`. The stack's configuration file,
Pulumi.<stack>.yaml, is read from and written to the source tree beside the
project file. Plugins come only from the project's pinned providers.""",
    attrs = {
        "project": attr.label(
            mandatory = True,
            providers = [PulumiProjectInfo],
            doc = "The pulumi_project this stack belongs to.",
        ),
        "stack": attr.string(
            mandatory = True,
            doc = "The stack, as Pulumi names it (`prod`, or `organization/project/prod`). " +
                  "Its last component names the configuration file, Pulumi.<name>.yaml.",
        ),
    } | _COMMON_ATTRS | {
        "outputs_file": attr.string(
            doc = "A file name ending in .bzl, in this package, to keep the stack's outputs in. " +
                  "Written after every successful up and destroy, and by `bazel run :<name>.outputs`; " +
                  "`bazel run :<name>.outputs -- --check` fails when it is stale. " +
                  "Load it as `load(\"//pkg:<file>\", \"OUTPUTS\")`.",
        ),
        "outputs_only": attr.bool(
            doc = "Internal: set by the pulumi_stack macro on the <name>.outputs target.",
        ),
    },
    executable = True,
    toolchains = [_TOOLCHAIN_TYPE],
)

def pulumi_stack(name, outputs_file = None, **kwargs):
    """One stack of a Pulumi project; see pulumi_stack_rule for the attributes.

    With outputs_file, also creates `<name>.outputs`, which writes (or with
    `-- --check`, checks) the stack's outputs file.

    Args:
      name: the target name.
      outputs_file: optional .bzl file name for the stack's outputs.
      **kwargs: the attributes of pulumi_stack_rule.
    """
    pulumi_stack_rule(name = name, outputs_file = outputs_file, **kwargs)
    if outputs_file:
        pulumi_stack_rule(
            name = name + ".outputs",
            outputs_file = outputs_file,
            outputs_only = True,
            **kwargs
        )

pulumi_stack_reference = rule(
    implementation = _pulumi_stack_reference_impl,
    doc = """The outputs of a stack whose program is not in this repository.

    bazel run //shared:network             # write the outputs file
    bazel run //shared:network -- --check  # fail if it is stale

Pulumi reads a stack's outputs from the backend alone, so no project, program
or provider is involved: only the stack's name, its backend, and whatever
credentials the backend needs.""",
    attrs = {
        "stack": attr.string(
            mandatory = True,
            doc = "The stack, fully qualified: organization/project/stack.",
        ),
        "outputs_file": attr.string(
            mandatory = True,
            doc = "A file name ending in .bzl, in this package, to keep the stack's outputs in. " +
                  "Load it as `load(\"//pkg:<file>\", \"OUTPUTS\")`.",
        ),
    } | _COMMON_ATTRS,
    executable = True,
    toolchains = [_TOOLCHAIN_TYPE],
)
