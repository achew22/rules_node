_js_filetype = FileType([".js"])
_modules_filetype = FileType(["node_modules"])

def _get_lib_name(ctx):
    name = ctx.label.name
    parts = ctx.label.package.split("/")
    if (len(parts) == 0) or (name != parts[-1]):
        parts.append(name)
    if ctx.attr.use_prefix:
        parts.insert(0, ctx.attr.prefix)
    return "-".join(parts)


def _copy_to_node_modules(ctx, node_modules, file):
    outfile = ctx.new_file(node_modules + "/" + file.short_path)
    ctx.action(
        command = "cp $1 $2",
        arguments = [file.path, outfile.path],
        inputs = [file],
        outputs = [outfile],
    )
    return outfile


def node_library_impl(ctx):

    modules = ctx.attr.modules
    lib_name = _get_lib_name(ctx)
    node_modules = "lib/node_modules/" + lib_name

    srcs = ctx.files.srcs
    script = ctx.file.main
    if not script and len(srcs) > 0:
        script = srcs[0]

    package_json_file = ctx.new_file(node_modules + "/package.json")

    transitive_srcs = []
    transitive_node_modules = []

    for dep in ctx.attr.deps:
        lib = dep.node_library
        transitive_srcs += lib.transitive_srcs
        transitive_node_modules += lib.transitive_node_modules

    json = {
        "name": lib_name,
        "main": script.short_path if script else "",
        "version": ctx.attr.version,
        "description": ctx.attr.d,
        "keywords": ctx.attr.keywords,
        "homepage": ctx.attr.homepage,
        "bugs": ctx.attr.bugs,
        "license": ctx.attr.license,
        "author": struct(**ctx.attr.author),
        "dependencies": struct(),
    }

    ctx.file_action(
        output = package_json_file,
        content = struct(**json).to_json(),
    )

    module_files = []
    data_files = [],
    if script:
        module_files.append(_copy_to_node_modules(ctx, node_modules, script))
    for src in srcs:
        module_files.append(_copy_to_node_modules(ctx, node_modules, src))
    for d in ctx.attr.data:
        for file in d.files:
            module_files.append(_copy_to_node_modules(ctx, node_modules, file))

    return struct(
        files = set(module_files),
        runfiles = ctx.runfiles(
            files = module_files,
            collect_default = False,
        ),
        node_library = struct(
            name = lib_name,
            label = ctx.label,
            srcs = module_files,
            transitive_srcs = module_files + transitive_srcs,
            transitive_node_modules = ctx.files.modules + transitive_node_modules,
            package_json = package_json_file,
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
        "keywords": attr.string_list(),
        "homepage": attr.string(),
        "bugs": attr.string(),
        "license": attr.string(),
        "author": attr.string_dict(),
        "bin": attr.string_dict(),
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
        "prefix": attr.string(default = "workspace"),
        "use_prefix": attr.bool(default = False),
    },
)
