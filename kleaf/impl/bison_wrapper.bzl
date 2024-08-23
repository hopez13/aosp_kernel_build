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

"""`bison` wrapper."""

load("@bazel_skylib//lib:paths.bzl", "paths")

visibility("//build/kernel/...")

def _bison_wrapper_impl(ctx):
    file = ctx.actions.declare_file("{}/bison".format(ctx.attr.name))
    root_from_base = "/".join([".."] * len(paths.dirname(file.path).split("/")))

    content = """\
#!/bin/sh

KLEAF_REPO_DIR=${{0%/*}}/{root_from_base}
ACTUAL=${{KLEAF_REPO_DIR}}/{actual}
export BISON_PKGDATADIR=${{KLEAF_REPO_DIR}}/{pkgdata_dir}
export M4=$(which m4)

if [ -z "${{M4}}" ]; then
    echo "ERROR: m4 is not found!" >&2
    exit 1
fi

if [ ! -d "${{BISON_PKGDATADIR}}" ]; then
    echo "ERROR: BISON_PKGDATADIR ${{BISON_PKGDATADIR}} is empty!" >&2
    exit 1
fi

"${{ACTUAL}}" $*
""".format(
        pkgdata_dir = ctx.file.pkgdata_dir.path,
        actual = ctx.executable.actual.path,
        root_from_base = root_from_base,
    )
    ctx.actions.write(file, content, is_executable = True)

    return DefaultInfo(
        files = depset([file]),
        runfiles = ctx.runfiles(
            files = [ctx.executable.actual],
            transitive_files = ctx.attr.pkgdata_files.files,
        ).merge(ctx.attr.actual[DefaultInfo].default_runfiles),
        executable = file,
    )

bison_wrapper = rule(
    implementation = _bison_wrapper_impl,
    doc = "Creates a wrapper script over real `bison` binary.",
    attrs = {
        "actual": attr.label(
            allow_files = True,
            executable = True,
            # Don't apply transitions; let hermetic_tools handle it.
            cfg = "target",
        ),
        "pkgdata_dir": attr.label(allow_single_file = True),
        "pkgdata_files": attr.label(allow_files = True),
    },
    executable = True,
)
