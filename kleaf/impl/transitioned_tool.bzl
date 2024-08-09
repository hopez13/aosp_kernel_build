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

"""Helper macro to wrap prebuilt tools before adding to hermetic_tools."""

load(":platform_transition.bzl", "platform_transition")

visibility("//build/kernel/...")

def _transitioned_tool_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.symlink(
        target_file = ctx.executable.src,
        output = out,
        is_executable = True,
    )
    runfiles = ctx.runfiles().merge(
        ctx.attr.src[0][DefaultInfo].default_runfiles,
    )
    return DefaultInfo(
        executable = out,
        files = depset([out]),
        runfiles = runfiles,
    )

_transitioned_tool = rule(
    implementation = _transitioned_tool_impl,
    attrs = {
        "src": attr.label(
            executable = True,
            allow_files = True,
            mandatory = True,
            cfg = platform_transition,
        ),
        "target_platform": attr.label(),
    },
)

def prebuilt_transitioned_tool(name, src, **kwargs):
    """Helper macro to wrap prebuilt tools before adding to hermetic_tools.

    Args:
        name: name of target
        src: Label to prebuilt tool that selects between different platforms.
        **kwargs: common kwargs
    """
    _transitioned_tool(
        name = name,
        src = src,
        target_platform = select({
            "//conditions:default": None,
        }),
        **kwargs
    )

def _transitioned_files_impl(ctx):
    runfiles = ctx.runfiles().merge_all([
        src[DefaultInfo].default_runfiles
        for src in ctx.attr.srcs
    ])
    return DefaultInfo(
        files = depset(transitive = [target.files for target in ctx.attr.srcs]),
        runfiles = runfiles,
    )

_transitioned_files = rule(
    implementation = _transitioned_files_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            cfg = platform_transition,
        ),
        "target_platform": attr.label(),
    },
)

def prebuilt_transitioned_files(name, srcs, **kwargs):
    """Transition to the platform selected for prebuilts.

    Args:
        name: name of target
        srcs: list of filegroup of prebuilts
        **kwargs: common kwargs
    """
    _transitioned_files(
        name = name,
        srcs = srcs,
        target_platform = select({
            "//conditions:default": None,
        }),
        **kwargs
    )
