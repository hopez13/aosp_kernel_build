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

"""Helper for `kernel_env` to get toolchains for different platforms."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@kernel_toolchain_info//:dict.bzl", "VARS")
load("//prebuilts/clang/host/linux-x86/kleaf:versions.bzl", _CLANG_VERSIONS = "VERSIONS")
load(
    ":common_providers.bzl",
    "KernelEnvToolchainsInfo",
    "KernelPlatformToolchainInfo",
)
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _quote_prepend_cwd(value):
    """Prepends $PWD to value.

    Returns:
        quoted shell value
    """
    if not value.startswith("/"):
        return "${PWD}/" + shell.quote(value)
    return shell.quote(value)

def _get_declared_toolchain_version(ctx):
    declared_toolchain_version = None
    for version in _CLANG_VERSIONS:
        attr = getattr(ctx.attr, "_clang_version_{}".format(version))
        if ctx.target_platform_has_constraint(attr[platform_common.ConstraintValueInfo]):
            declared_toolchain_version = version
    return declared_toolchain_version

def _check_toolchain_version(ctx, resolved_toolchain_info, declared_toolchain_version, platform_name):
    if declared_toolchain_version == None:
        # kernel_build does not declare toolchain_version. Use default CLANG_VERSION from toolchain
        # resolution.
        return

    if resolved_toolchain_info.compiler_version != declared_toolchain_version:
        if resolved_toolchain_info.compiler_version == "kleaf_user_clang_toolchain_skip_version_check":
            # buildifier: disable=print
            print("\nWARNING: kernel_build.toolchain_version = {}, but overriding with --user_clang_toolchain".format(
                declared_toolchain_version,
            ))
        else:
            fail("{}: Resolved to incorrect toolchain for {} platform. Expected: {}, actual: {}".format(
                ctx.label,
                platform_name,
                declared_toolchain_version,
                resolved_toolchain_info.compiler_version,
            ))

def _get_target_arch(ctx):
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_arm[platform_common.ConstraintValueInfo]):
        return "arm"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_arm64[platform_common.ConstraintValueInfo]):
        return "arm64"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_i386[platform_common.ConstraintValueInfo]):
        return "i386"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_riscv64[platform_common.ConstraintValueInfo]):
        return "riscv64"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_x86_64[platform_common.ConstraintValueInfo]):
        return "x86_64"
    fail("{}: Cannot determine target platform.".format(ctx.label))

def _quote_sanitize_flags(flags):
    """Turns paths into ones relative to $PWD for each flag.

    Kbuild executes the compiler in subdirectories, hence an absolute path is needed.

    Returns:
        quoted shell value
    """

    result_quoted_flags = []

    long_flags = [
        "--sysroot",
        "-iquote",
        "-isystem",
    ]

    short_flags = [
        "-I",
        "-L",
    ]

    prev = None
    for _index, flag in enumerate(flags):
        if prev in long_flags or prev in short_flags:
            result_quoted_flags.append(_quote_prepend_cwd(flag))
        elif any([flag.startswith(long_flag + "=") for long_flag in long_flags]):
            key, value = flag.split("=", 2)
            result_quoted_flags.append("{}={}".format(key, _quote_prepend_cwd(value)))
        elif any([flag.startswith(short_flag) for short_flag in short_flags]):
            key, value = flag[:2], flag[2:]
            result_quoted_flags.append("{}{}".format(key, _quote_prepend_cwd(value)))
        else:
            result_quoted_flags.append(shell.quote(flag))

        prev = flag

    return "' '".join(result_quoted_flags)

def _kernel_toolchains_impl(ctx):
    exec = ctx.attr.exec_toolchain[KernelPlatformToolchainInfo]
    target = ctx.attr.target_toolchain[KernelPlatformToolchainInfo]

    # The toolchain_version declared in kernel_build. May be None to use
    # default toolchain version.
    declared_toolchain_version = _get_declared_toolchain_version(ctx)

    # Check that
    #  declared_toolchain_version == None or exec.compiler_version == declared_toolchain_version
    _check_toolchain_version(ctx, exec, declared_toolchain_version, "exec")

    # Check that
    #  declared_toolchain_version == None or target.compiler_version == declared_toolchain_version
    _check_toolchain_version(ctx, target, declared_toolchain_version, "target")

    # If declared_toolchain_version == None, ensures that the resolved toolchain
    # for the two platforms equal.
    if target.compiler_version != exec.compiler_version:
        fail("{}: Target platform has compiler version {} but exec platform has {}".format(
            ctx.label,
            target.compiler_version,
            exec.compiler_version,
        ))
    actual_toolchain_version = target.compiler_version

    all_files_transitive = [exec.all_files, target.all_files]
    target_arch = _get_target_arch(ctx)

    quoted_bin_paths = [
        _quote_prepend_cwd(exec.bin_path),
        _quote_prepend_cwd(target.bin_path),
    ]

    setup_env_var_cmd = """
        export PATH={quoted_bin_paths}:${{PATH}}
    """.format(
        quoted_bin_paths = ":".join(quoted_bin_paths),
    )

    kernel_setup_env_var_cmd = setup_env_var_cmd

    if ctx.attr._kernel_use_resolved_toolchains[BuildSettingInfo].value:
        # RUNPATH_EXECROOT: A heuristic path to execroot expressed relative to $ORIGIN.
        # RUNPATH_EXECROOT assumes that all binaries built by Kbuild are 1~3 levels
        #   below OUT_DIR,
        #   e.g. $OUT_DIR/scripts/sign-file, $OUT_DIR/tools/bpf/resolve_btfids/resolve_btfids
        # If this ever changes, edit kleaf_internal_eval_ldflags and add more levels.
        kernel_setup_env_var_cmd += """
            export HOSTCFLAGS={quoted_hostcflags}
            export USERCFLAGS={quoted_usercflags}
            export HOSTLDFLAGS={quoted_hostldflags}
            export USERLDFLAGS={quoted_userldflags}

            mkdir -p ${{OUT_DIR}}
            # Append to *LDFLAGS based on the current settings of $OUT_DIR.
            function kleaf_internal_append_one_ldflags() {{
                local backtrack_relative=$1
                local RUNPATH_EXECROOT='$$$$\\{{ORIGIN\\}}/'"${{backtrack_relative}}$(realpath ${{ROOT_DIR}} --relative-to ${{OUT_DIR}})"
                export HOSTLDFLAGS="${{HOSTLDFLAGS}} "{hostldexpr}
                export USERLDFLAGS="${{USERLDFLAGS}} "{userldexpr}
            }}
            export -f kleaf_internal_append_one_ldflags

            function kleaf_internal_eval_ldflags() {{
                kleaf_internal_append_one_ldflags ../
                kleaf_internal_append_one_ldflags ../../
                kleaf_internal_append_one_ldflags ../../../
                kleaf_internal_append_one_ldflags ../../../../
                kleaf_internal_append_one_ldflags ../../../../../
                kleaf_internal_append_one_ldflags ../../../../../../
            }}
            export -f kleaf_internal_eval_ldflags

            kleaf_internal_eval_ldflags
        """.format(
            quoted_hostcflags = _quote_sanitize_flags(exec.cflags),
            quoted_usercflags = _quote_sanitize_flags(target.cflags),
            quoted_hostldflags = _quote_sanitize_flags(exec.ldflags),
            hostldexpr = exec.ldexpr,
            quoted_userldflags = _quote_sanitize_flags(target.ldflags),
            userldexpr = target.ldexpr,
        )

        if ctx.attr._rust_tools:
            kernel_setup_env_var_cmd += _get_rust_env_setup(ctx.files._rust_tools)
            all_files_transitive += [target.files for target in ctx.attr._rust_tools]

    # Kleaf clang bins are under kleaf/parent, so CLANG_PREBUILT_BIN in
    # build.config.common is incorrect. Manually set additional PATH's.

    return KernelEnvToolchainsInfo(
        all_files = depset(transitive = all_files_transitive),
        target_arch = target_arch,
        setup_env_var_cmd = setup_env_var_cmd,
        kernel_setup_env_var_cmd = kernel_setup_env_var_cmd,
        compiler_version = actual_toolchain_version,
        host_runpaths = exec.runpaths,
        host_sysroot = exec.sysroot,
    )

def _get_rust_env_setup_impl(_subrule_ctx, rust_files):
    rustc = utils.find_file("rustc", rust_files, "rust tools", required = True)
    bindgen = utils.find_file("bindgen", rust_files, "rust tools", required = True)

    # RUNPATH_EXECROOT: A heuristic path to execroot expressed relative to $ORIGIN.
    # RUNPATH_EXECROOT assumes that all binaries built by Kbuild are several levels
    #   below OUT_DIR,
    #   e.g. $OUT_DIR/scripts/generate_rust_targets
    # If this ever changes, edit kleaf_internal_eval_rust_flags and add more levels.
    return """
        export PATH="${{PATH}}:${{ROOT_DIR}}/"{quoted_rust_bin}":${{ROOT_DIR}}/"{quoted_clangtools_bin}

        function kleaf_internal_append_one_rust_flags() {{
            local backtrack_relative=$1
            local RUNPATH_EXECROOT='$$$$\\{{ORIGIN\\}}/'"${{backtrack_relative}}$(realpath ${{ROOT_DIR}} --relative-to ${{OUT_DIR}})"
            export HOSTRUSTFLAGS="${{HOSTRUSTFLAGS}} "-Clink-args=-Wl,-rpath,${{RUNPATH_EXECROOT}}/{quoted_rust_bin}/../lib64
        }}
        export -f kleaf_internal_append_one_rust_flags
        function kleaf_internal_eval_rust_flags() {{
            kleaf_internal_append_one_rust_flags ../
        }}
        export -f kleaf_internal_eval_rust_flags

        kleaf_internal_eval_rust_flags
    """.format(
        quoted_rust_bin = shell.quote(rustc.dirname),
        quoted_clangtools_bin = shell.quote(bindgen.dirname),
    )

_get_rust_env_setup = subrule(
    implementation = _get_rust_env_setup_impl,
)

def _get_rust_tools(rust_toolchain_version):
    if not rust_toolchain_version:
        return []
    rust_binaries = "//prebuilts/rust/linux-x86/%s:binaries" % rust_toolchain_version

    bindgen = "//prebuilts/clang-tools:linux-x86/bin/bindgen"

    return [Label(rust_binaries), Label(bindgen)]

kernel_toolchains = rule(
    doc = """Helper for `kernel_env` to get toolchains for different platforms.""",
    implementation = _kernel_toolchains_impl,
    attrs = {
        "exec_toolchain": attr.label(
            cfg = "exec",
            providers = [KernelPlatformToolchainInfo],
        ),
        "target_toolchain": attr.label(
            providers = [KernelPlatformToolchainInfo],
        ),
        # TODO(b/284390729): Use toolchain resolution
        "rust_toolchain_version": attr.string(
            doc = "the version of the rust toolchain to use for this environment",
            default = VARS.get("RUSTC_VERSION", ""),
        ),
        "_rust_tools": attr.label_list(default = _get_rust_tools, allow_files = True),
        "_kernel_use_resolved_toolchains": attr.label(
            default = "//build/kernel/kleaf:incompatible_kernel_use_resolved_toolchains",
        ),
        "_platform_cpu_arm": attr.label(default = "@platforms//cpu:arm"),
        "_platform_cpu_arm64": attr.label(default = "@platforms//cpu:arm64"),
        "_platform_cpu_i386": attr.label(default = "@platforms//cpu:i386"),
        "_platform_cpu_riscv64": attr.label(default = "@platforms//cpu:riscv64"),
        "_platform_cpu_x86_64": attr.label(default = "@platforms//cpu:x86_64"),
    } | {
        "_clang_version_{}".format(version): attr.label(default = "//prebuilts/clang/host/linux-x86/kleaf:{}".format(version))
        for version in _CLANG_VERSIONS
    },
    subrules = [_get_rust_env_setup],
)
