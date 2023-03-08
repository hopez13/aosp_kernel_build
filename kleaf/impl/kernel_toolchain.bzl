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

"""Helper to resolve toolchain for a single platform."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "CPP_TOOLCHAIN_TYPE", "find_cpp_toolchain", "use_cpp_toolchain")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "C_COMPILE_ACTION_NAME")  # or our fake rules_cc
load(":common_providers.bzl", "KernelResolvedToolchainInfo")

def _kernel_toolchain_impl(ctx):
    cc_info = cc_common.merge_cc_infos(
        cc_infos = [src[CcInfo] for src in ctx.attr.deps],
    )

    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = [
            # -no-canonical-prefixes is added to work around
            # https://github.com/bazelbuild/bazel/issues/4605
            # "cxx_builtin_include_directory doesn't work with non-absolute path"
            # Disable it.
            "kleaf-no-canonical-prefixes",
        ],
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = [],  #copts
        include_directories = cc_info.compilation_context.includes,
        quote_include_directories = cc_info.compilation_context.quote_includes,
        system_include_directories = cc_info.compilation_context.system_includes,
    )
    compile_command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = C_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )

    all_files = depset(cc_info.compilation_context.direct_headers, transitive = [
        cc_info.compilation_context.headers,
        cc_toolchain.all_files,
    ])

    return KernelResolvedToolchainInfo(
        toolchain_id = cc_toolchain.toolchain_id,
        all_files = all_files,
        cflags = compile_command_line,
    )

kernel_toolchain = rule(
    doc = """Helper to resolve toolchain for a single platform.""",
    implementation = _kernel_toolchain_impl,
    attrs = {
        "deps": attr.label_list(providers = [CcInfo]),
    },
    toolchains = use_cpp_toolchain(mandatory = True),
    fragments = ["cpp"],
)
