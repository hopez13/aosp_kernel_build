# Copyright (C) 2023 The Android Open Source Project
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

"""Update file with incompatibile ABI changes over KMI history."""

visibility("//build/kernel/kleaf/...")

def _update_known_abi_breaks_impl(ctx):
    # Can't use hermetic toolchain, because `update_known_abi_breaks`
    # depends on `git` and it updates the file in the source directory.
    script = """#!/bin/bash -e
        export STGDIFF={stgdiff}
        ABI_DEFINITION=$(readlink -m {abi_definition})
        KNOWN_ABI_BREAKS=$(readlink -m {known_abi_breaks})
        {update_known_abi_breaks} --abi "$ABI_DEFINITION" \
            --known-abi-breaks "$KNOWN_ABI_BREAKS"
    """.format(
        stgdiff = ctx.executable._stgdiff.short_path,
        update_known_abi_breaks = ctx.executable._update_known_abi_breaks.short_path,
        abi_definition = ctx.file.abi_definition_stg.short_path,
        known_abi_breaks = ctx.file.known_abi_breaks.short_path,
    )

    executable = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))
    ctx.actions.write(executable, script, is_executable = True)

    runfiles = ctx.runfiles(files = [
        ctx.file.abi_definition_stg,
        ctx.file.known_abi_breaks,
        ctx.executable._update_known_abi_breaks,
    ])
    runfiles = runfiles.merge_all([
        ctx.attr._update_known_abi_breaks[DefaultInfo].default_runfiles,
    ])

    return DefaultInfo(
        files = depset([executable]),
        executable = executable,
        runfiles = runfiles,
    )

update_known_abi_breaks = rule(
    implementation = _update_known_abi_breaks_impl,
    attrs = {
        "abi_definition_stg": attr.label(
            doc = "source ABI definition file",
            allow_single_file = True,
        ),
        "known_abi_breaks": attr.label(
            doc = "file containing ABI breaks",
            allow_single_file = True,
        ),
        "_stgdiff": attr.label(
            default = "//prebuilts/kernel-build-tools:linux-x86/bin/stgdiff",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
        "_update_known_abi_breaks": attr.label(
            default = "//build/kernel:update_known_abi_breaks",
            cfg = "exec",
            executable = True,
        ),
    },
    executable = True,
)
