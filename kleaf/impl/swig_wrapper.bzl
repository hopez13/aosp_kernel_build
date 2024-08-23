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

"""`swig` wrapper."""

load("@bazel_skylib//lib:paths.bzl", "paths")

visibility("//build/kernel/...")

def _swig_wrapper_impl(ctx):
    file = ctx.actions.declare_file("{}/swig".format(ctx.attr.name))
    root_from_base = "/".join([".."] * len(paths.dirname(file.path).split("/")))
    short_root_from_base = "/".join([".."] * len(paths.dirname(file.short_path).split("/")))

    # We can't use .runfiles because $0 may be a symlink. We don't have hermetic tools to
    # resolve the symlink properly.
    # https://bazel.build/extending/rules#runfiles_location

    content = """\
#!/bin/sh

PATH=

KLEAF_REPO_DIR=${{0%/*}}/{root_from_base}
SWIG_LIB="${{KLEAF_REPO_DIR}}/{swig_lib}" exec "${{KLEAF_REPO_DIR}}/{src}" $*
""".format(
        src = ctx.executable.src.path,
        swig_lib = ctx.files.swig_lib[0].path,
        root_from_base = root_from_base,
    )
    ctx.actions.write(file, content, is_executable = True)

    runfiles = ctx.runfiles(
        files = [ctx.executable.src],
    )
    runfiles = runfiles.merge(ctx.attr.src[DefaultInfo].default_runfiles)

    return DefaultInfo(
        files = depset([file]),
        runfiles = runfiles,
        executable = file,
    )

swig_wrapper = rule(
    implementation = _swig_wrapper_impl,
    doc = "Creates a wrapper script over real `swig` binary.",
    attrs = {
        "src": attr.label(
            allow_files = True,
            executable = True,
            # Don't apply transitions; let hermetic_tools handle it.
            cfg = "target",
        ),
        "swig_lib": attr.label(
            allow_single_file = True,
            doc = "Contains a single File which is a directory for SWIG_LIB.",
        ),
    },
    executable = True,
)
