_js_filetype = FileType([".js"])
_modules_filetype = FileType(["node_modules"])

def _get_path_relative(base, file):
    prefix = "../" * len(base.split('/'))
    return prefix + file.path


def _get_lib_name(ctx):
    name = ctx.label.name
    parts = ctx.label.package.split("/")
    if (len(parts) == 0) or (name != parts[-1]):
        parts.append(name)
    if ctx.attr.use_prefix:
        parts.insert(0, ctx.attr.prefix)
    return "-".join(parts)


def _copy_to_stage(ctx, stage, file):
    outfile = ctx.new_file(stage + "/" + file.short_path)
    ctx.action(
        command = "cp $1 $2",
        arguments = [file.path, outfile.path],
        inputs = [file],
        outputs = [outfile],
    )
    return outfile


def node_library_impl(ctx):
    node = ctx.executable._node
    npm = ctx.executable._npm
    modules = ctx.attr.modules

    lib_name = _get_lib_name(ctx)
    stage = lib_name + ".stage"

    srcs = ctx.files.srcs
    script = ctx.file.main
    if not script and len(srcs) > 0:
        script = srcs[0]

    package_json_template_file = ctx.file.package_json_template_file
    package_json_file = ctx.new_file(stage + "/package.json")
    npm_package_json_file = ctx.new_file("lib/node_modules/%s/package.json" % lib_name)

    transitive_srcs = []
    transitive_node_modules = []

    for dep in ctx.attr.deps:
        lib = dep.node_library
        transitive_srcs += lib.transitive_srcs
        transitive_node_modules += lib.transitive_node_modules

    ctx.template_action(
        template = package_json_template_file,
        output = package_json_file,
        substitutions = {
            "%{name}": lib_name,
            "%{main}": script.short_path if script else "",
            "%{version}": ctx.attr.version,
            "%{description}": ctx.attr.d,
        },
    )

    staged = []
    if script:
        staged.append(_copy_to_stage(ctx, stage, script))
    for src in srcs:
        staged.append(_copy_to_stage(ctx, stage, src))
    for d in ctx.attr.data:
        for file in d.files:
            staged.append(_copy_to_stage(ctx, stage, file))

    cmds = []
    cmds.append("cd %s" % package_json_file.dirname)
    cmds.append(" ".join([
        _get_path_relative(package_json_file.dirname, node),
        _get_path_relative(package_json_file.dirname, npm),
        "install",
        "--global",
        "--prefix",
        "..",
        #npm_package_json_file.dirname,
    ]))
    cmds.append("rm -rf %s" % package_json_file.dirname)

    inputs = [node, npm, package_json_file] + staged

    ctx.action(
        mnemonic = "NpmInstallLocal",
        inputs = inputs,
        outputs = [npm_package_json_file],
        command = " && ".join(cmds),
    )

    return struct(
        files = set(srcs),
        runfiles = ctx.runfiles(
            files = srcs,
            collect_default = True,
        ),
        node_library = struct(
            name = lib_name,
            label = ctx.label,
            srcs = srcs,
            transitive_srcs = srcs + transitive_srcs,
            transitive_node_modules = ctx.files.modules + transitive_node_modules,
            package_json = npm_package_json_file,
            npm_package_json = npm_package_json_file,
        ),
    )

node_library = rule(
    node_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = _js_filetype,
        ),
        "version": attr.string(
            default = "0.0.0",
        ),
        "main": attr.label(
            mandatory = False,
            single_file = True,
            allow_files = _js_filetype,
        ),
        "d": attr.string(
            default = "No description provided.",
        ),
        "data": attr.label_list(
            allow_files = True,
            cfg = "data",
        ),
        "deps": attr.label_list(
            providers = ["node_library"],
        ),
        "modules": attr.label_list(
            allow_files = _modules_filetype,
        ),
        "package_json_template_file": attr.label(
            single_file = True,
            allow_files = True,
            default = Label("//node:package.json.tpl"),
        ),
        "prefix": attr.string(default = "workspace"),
        "use_prefix": attr.bool(default = False),
        "_node": attr.label(
            default = Label("@org_pubref_rules_node_toolchain//:node_tool"),
            single_file = True,
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
        "_npm": attr.label(
            default = Label("@org_pubref_rules_node_toolchain//:npm_tool"),
            single_file = True,
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
    },
)
