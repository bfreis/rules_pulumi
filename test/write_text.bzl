"""A rule that writes a string to a file, to observe values computed when BUILD files load."""

def _write_text_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(out, ctx.attr.content + "\n")
    return [DefaultInfo(files = depset([out]))]

write_text = rule(
    implementation = _write_text_impl,
    attrs = {"content": attr.string()},
)
