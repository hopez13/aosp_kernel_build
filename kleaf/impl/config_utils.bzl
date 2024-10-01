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

"""Utilities for *_config.bzl."""

load(
    ":common_providers.bzl",
    "StepInfo",
)

visibility("//build/kernel/kleaf/...")

def _create_merge_dot_config_cmd(defconfig_fragments_paths_expr):
    """Returns a command that merges defconfig fragments into `$OUT_DIR/.config`

    Args:
        defconfig_fragments_paths_expr: A shell expression that evaluates
            to a list of paths to the defconfig fragments.

    Returns:
        the command that merges defconfig fragments into `$OUT_DIR/.config`
    """
    cmd = """
        # Merge target defconfig into .config from kernel_build
        KCONFIG_CONFIG=${{OUT_DIR}}/.config.tmp \\
            ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh \\
                -m -r \\
                ${{OUT_DIR}}/.config \\
                {defconfig_fragments_paths_expr} > /dev/null
        mv ${{OUT_DIR}}/.config.tmp ${{OUT_DIR}}/.config
    """.format(
        defconfig_fragments_paths_expr = defconfig_fragments_paths_expr,
    )
    return cmd

def _create_check_defconfig_step_impl(
        _subrule_ctx,
        post_defconfig_fragments,
        *,
        _check_config):
    """Checks $OUT_DIR/.config against a given list of defconfig and fragments.

    Args:
        _subrule_ctx: subrule_ctx
        post_defconfig_fragments: List of **post** defconfig fragments applied
            at the end.

            All requirements in each fragment is enforced, so order does not
            matter.
        _check_config: FilesToRunProvider for `check_config.py`.
    """
    cmd = """
        {check_config} \\
            --dot_config ${{OUT_DIR}}/.config \\
            --post_defconfig_fragments {post_defconfig_fragments_paths_expr}
    """.format(
        check_config = _check_config.executable.path,
        post_defconfig_fragments_paths_expr = " ".join([fragment.path for fragment in post_defconfig_fragments]),
    )
    return StepInfo(
        inputs = depset(post_defconfig_fragments),
        outputs = [],
        tools = [_check_config],
        cmd = cmd,
    )

_create_check_defconfig_step = subrule(
    implementation = _create_check_defconfig_step_impl,
    attrs = {
        "_check_config": attr.label(
            default = ":check_config",
            executable = True,
            cfg = "exec",
        ),
    },
)

config_utils = struct(
    create_merge_dot_config_cmd = _create_merge_dot_config_cmd,
    create_check_defconfig_step = _create_check_defconfig_step,
)
