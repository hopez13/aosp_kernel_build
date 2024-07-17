# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Headers target for DDK."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")

visibility("//build/kernel/kleaf/...")

DdkHeadersInfo = provider(
    "Information for a target that provides DDK headers to a dependent target.",
    fields = {
        "files": "A [depset](https://bazel.build/rules/lib/depset) including all header files",
        "includes": "A [depset](https://bazel.build/rules/lib/depset) containing the `includes` attribute of the rule",
        "linux_includes": "Like `includes` but added to `LINUXINCLUDE`.",
    },
)

def get_extra_include_roots(headers):
    """Given a list of headers, return a list of include roots.

    For each header in headers, drop short_path from path to get an include_root.
    Then return all include_roots.

    Args:
        headers: A list of headers.
    Returns:
        include roots to be prepended to include_dirs.
    """

    return sets.to_list(sets.make([header.root.path for header in headers]))

def get_include_depset(label, deps, includes, include_roots, info_attr_name):
    """Returns a depset containing include directories from the list of dependencies and direct includes.

    Args:
        label: Label of this target
        deps: A list of depended targets. If [`DdkHeadersInfo`](#DdkHeadersInfo) is in the target,
          their `includes` are included in the returned depset.
        includes: A list of local include directories included in the returned depset.
        include_roots: prepended to includes (cross product).
          If empty, `includes` are useless because the cross product is empty.
        info_attr_name: corresponding field name in `DdkHeadersInfo`.
    Returns:
        A depset containing include directories from the list of dependencies and direct includes.
    """
    file_deps = []
    transitive_includes = []
    for dep in deps:
        if DdkHeadersInfo in dep:
            transitive_includes.append(getattr(dep[DdkHeadersInfo], info_attr_name))
        else:
            file_deps.append(dep.files)

    # Generated files in hdrs results in extra include bases
    # TODO(b/353811700): avoid depset expansion
    extra_include_roots = get_extra_include_roots(depset(transitive = file_deps).to_list())

    direct_includes = []
    for include_root in include_roots + extra_include_roots:
        for rel_include_dir in includes:
            # Do not prepend "." because we check for path normalization below.
            include_dir = paths.join(include_root, rel_include_dir) if include_root != "." else rel_include_dir

            if paths.normalize(include_dir) != include_dir:
                fail(
                    "{}: include directory {} is not normalized to {}".format(
                        label,
                        include_dir,
                        paths.normalize(include_dir),
                    ),
                )
            if paths.is_absolute(include_dir):
                fail("{}: Absolute directories not allowed in includes: {}".format(label, include_dir))
            if include_dir == ".." or include_dir.startswith("../"):
                fail("{}: Invalid include directory: {}".format(label, include_dir))
            direct_includes.append(paths.normalize(paths.join(include_root, label.workspace_root, label.package, rel_include_dir)))

    return depset(
        direct_includes,
        transitive = transitive_includes,
        # At this time of writing (2022-11-01), this is what cc_library does;
        # includes of this target, then includes of deps
        order = "preorder",
    )

def get_headers_depset(deps):
    """Returns a depset containing headers from the list of dependencies

    Args:
        deps: A list of depended targets. If [`DdkHeadersInfo`](#DdkHeadersInfo) is in the target,
          `target[DdkHeadersInfo].files` are included in the returned depset. Otherwise
          the default output files are included in the returned depset.
    Returns:
        A depset containing headers from the list of dependencies.
    """
    transitive_deps = []

    for dep in deps:
        if DdkHeadersInfo in dep:
            transitive_deps.append(dep[DdkHeadersInfo].files)
        else:
            transitive_deps.append(dep.files)

    return depset(transitive = transitive_deps)

def ddk_headers_common_impl(label, hdrs, includes, linux_includes):
    """Common implementation for rules that returns `DdkHeadersInfo`.

    Args:
        label: Label of this target.
        hdrs: The list of exported headers, e.g. [`ddk_headers.hdrs`](#ddk_headers-hdrs)
        includes: The list of exported include directories, e.g. [`ddk_headers.includes`](#ddk_headers-includes)
        linux_includes: Like `includes` but added to `LINUXINCLUDE`.
    """

    return DdkHeadersInfo(
        files = get_headers_depset(hdrs),
        includes = get_include_depset(label, hdrs, includes, ["."], "includes"),
        linux_includes = get_include_depset(label, hdrs, linux_includes, ["."], "linux_includes"),
    )

def _ddk_headers_impl(ctx):
    ddk_headers_info = ddk_headers_common_impl(
        ctx.label,
        ctx.attr.hdrs + ctx.attr.textual_hdrs,
        ctx.attr.includes,
        ctx.attr.linux_includes,
    )
    return [
        DefaultInfo(files = ddk_headers_info.files),
        ddk_headers_info,
    ]

ddk_headers = rule(
    implementation = _ddk_headers_impl,
    doc = """A rule that exports a list of header files to be used in DDK.

Example:

```
ddk_headers(
   name = "headers",
   hdrs = ["include/module.h"],
   textual_hdrs = ["template.c"],
   includes = ["include"],
)
```

`ddk_headers` can be chained; that is, a `ddk_headers` target can re-export
another `ddk_headers` target. For example:

```
ddk_headers(
   name = "foo",
   hdrs = ["include_foo/foo.h"],
   includes = ["include_foo"],
)
ddk_headers(
   name = "headers",
   hdrs = [":foo", "include/module.h"],
   includes = ["include"],
)
```
""",
    attrs = {
        "hdrs": attr.label_list(allow_files = [".h"], doc = """One of the following:

- Local header files to be exported. You may also need to set the `includes` attribute.
- Other `ddk_headers` targets to be re-exported.
"""),
        "textual_hdrs": attr.label_list(
            allow_files = True,
            doc = """The list of header files to be textually included by sources.

This is the location for declaring header files that cannot be compiled on their own;
that is, they always need to be textually included by other source files to build valid code.
""",
        ),
        "includes": attr.string_list(
            doc = """A list of directories, relative to the current package, that are re-exported as include directories.

[`ddk_module`](#ddk_module) with `deps` including this target automatically
adds the given include directory in the generated `Kbuild` files.

You still need to add the actual header files to `hdrs`.
""",
        ),
        "linux_includes": attr.string_list(
            doc = """Like `includes` but specified in `LINUXINCLUDES` instead.

Setting this attribute allows you to override headers from `${KERNEL_DIR}`. See "Order of includes"
in [`ddk_module`](#ddk_module) for details.
""",
        ),
    },
)
