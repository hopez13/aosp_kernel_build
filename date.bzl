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

"""`bison` wrapper.

Caveat: Do not use native_binary or ctx.actions.symlink() to wrap this binary
due to the use of $0.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

visibility("//build/kernel/...")

def _bison_wrapper_impl(ctx):
    file = ctx.actions.declare_file("{}/bison".format(ctx.attr.name))
    root_from_base = "/".join([".."] * len(paths.dirname(file.path).split("/")))

    content = """\
#!/bin/sh

if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ]; then
    export RUNFILES_DIR=${{RUNFILES_DIR:-${{0}}.runfiles}}
    ACTUAL=${{RUNFILES_DIR}}/{workspace_name}/{actual_short}
    WRAPPER=${{RUNFILES_DIR}}/{workspace_name}/{wrapper_short}
else
    KLEAF_REPO_DIR=${{0%/*}}/{root_from_base}
    export RUNFILES_DIR="${{KLEAF_REPO_DIR}}/../"
    echo RUNFILES_DIR="${{RUNFILES_DIR}}" >&2
    ACTUAL=${{KLEAF_REPO_DIR}}/{actual}
    WRAPPER=${{KLEAF_REPO_DIR}}/{wrapper}
fi

export LC_ALL=C
export TZ=UTC
"${{WRAPPER}}" "${{ACTUAL}}" "$@"
""".format(
        # https://bazel.build/extending/rules#runfiles_location
        # The recommended way to detect launcher_path is use $0.
        # From man sh: If bash is invoked with a file of commands, $0 is set to the name of that
        # file.
        workspace_name = ctx.workspace_name,
        root_from_base = root_from_base,
        actual = ctx.executable.actual.path,
        actual_short = ctx.executable.actual.short_path,
        wrapper = ctx.executable.wrapper.path,
        wrapper_short = ctx.executable.wrapper.short_path,
    )
    ctx.actions.write(file, content, is_executable = True)

    return DefaultInfo(
        files = depset([file]),
        runfiles = ctx.runfiles(
            files = [ctx.executable.actual, ctx.executable.wrapper],
        ).merge_all([
            ctx.attr.actual[DefaultInfo].default_runfiles,
            ctx.attr.wrapper[DefaultInfo].default_runfiles,
        ]),
        executable = file,
    )

date = rule(
    implementation = _bison_wrapper_impl,
    doc = """Creates a wrapper script over real `bison` binary.

        Caveat: Do not use native_binary or ctx.actions.symlink() to wrap this binary
        due to the use of $0.
    """,
    attrs = {
        "actual": attr.label(
            allow_files = True,
            executable = True,
            # Don't apply transitions; let hermetic_tools handle it.
            cfg = "target",
        ),
        "wrapper": attr.label(
            allow_files = True,
            executable = True,
            # Don't apply transitions; let hermetic_tools handle it.
            cfg = "target",
        ),
    },
    executable = True,
)
