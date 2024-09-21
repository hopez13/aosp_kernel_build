# Copyright (C) 2024 The Android Open Source Project
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

"""Provides alternative declaration to kernel_images()"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":image/or_file.bzl", "OrFileInfo")

visibility("private")

def _quote_opt_str(s):
    """Quote an optional string.

    If None, return a quoted empty string. Otherwise quote.

    Args:
        s: str or None
    """
    if not s:
        s = ""
    return shell.quote(str(s))

def _sanitize_opt_label(label):
    """Sanitize an optional label.

    If None, return None. Otherwise, return sanitized string.

    Args:
        label: str or None
    """
    if not label:
        return None
    return str(label).replace("@@//", "//").replace("@//", "//")

def _kernel_images_replace_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    images_name = ctx.label.name.removesuffix("_replace")
    sanitized_images_name = ctx.label.name.removesuffix("_replace").removesuffix("_images")

    content = hermetic_tools.run_setup + """#!/bin/sh -e
        {bin} {query_output} \\
            --ban "generator_name" \\
            --ban "generator_function" \\
            --ban "generator_location" \\
            --replace "kleaf_internal_legacy_ext4_single" "ext4" \\
            --replace {selected_modules_list} {actual_modules_list} \\
            --replace {selected_modules_blocklist} {actual_modules_blocklist} \\
            --replace {images_name} {sanitized_images_name} \\
            --replace {mypackage_colon} ":" \\
    """.format(
        bin = _quote_opt_str(ctx.executable._bin.short_path),
        query_output = _quote_opt_str(ctx.file.query_output.short_path),
        # Use repr() to replace the quoted string as a whole with possibly the None repr.
        selected_modules_list = _quote_opt_str(repr(_sanitize_opt_label(ctx.attr.selected_modules_list.label))),
        actual_modules_list = _quote_opt_str(repr(_sanitize_opt_label(ctx.attr.selected_modules_list[OrFileInfo].selected_label))),
        selected_modules_blocklist = _quote_opt_str(repr(_sanitize_opt_label(ctx.attr.selected_modules_blocklist.label))),
        actual_modules_blocklist = _quote_opt_str(repr(_sanitize_opt_label(ctx.attr.selected_modules_blocklist[OrFileInfo].selected_label))),
        images_name = _quote_opt_str(_sanitize_opt_label(images_name)),
        sanitized_images_name = _quote_opt_str(_sanitize_opt_label(sanitized_images_name)),
        mypackage_colon = _quote_opt_str(_sanitize_opt_label(ctx.label).removesuffix(":" + ctx.label.name) + ":"),
    )
    file = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.write(file, content)
    runfiles = ctx.runfiles([ctx.file.query_output], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge(ctx.attr._bin[DefaultInfo].default_runfiles)

    return DefaultInfo(
        files = depset([file]),
        executable = file,
        runfiles = runfiles,
    )

kernel_images_replace = rule(
    implementation = _kernel_images_replace_impl,
    attrs = {
        "query_output": attr.label(allow_single_file = True),
        "selected_modules_list": attr.label(providers = [OrFileInfo]),
        "selected_modules_blocklist": attr.label(providers = [OrFileInfo]),
        "_bin": attr.label(
            default = ":image/kernel_images_replace",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    toolchains = [hermetic_toolchain.type],
)
