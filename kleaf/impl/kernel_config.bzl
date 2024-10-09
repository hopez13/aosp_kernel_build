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

"""Creates proper .config and others for kernel_build."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")
load(":cache_dir.bzl", "cache_dir")
load(
    ":common_providers.bzl",
    "DefconfigInfo",
    "KernelBuildOriginalEnvInfo",
    "KernelConfigInfo",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
    "KernelEnvMakeGoalsInfo",
    "KernelSerializedEnvInfo",
    "KernelToolchainInfo",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")
load(":debug.bzl", "debug")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":kernel_config_settings.bzl", "kernel_config_settings")
load(":kgdb.bzl", "kgdb")
load(":scripts_config_arg_builder.bzl", _config = "scripts_config_arg_builder")
load(":stamp.bzl", "stamp")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

# Name of raw symbol list under $OUT_DIR
_RAW_KMI_SYMBOL_LIST_BELOW_OUT_DIR = "abi_symbollist.raw"

def _config_lto_impl(_subrule_ctx, lto_config_flag):
    """Return configs for LTO.

    Args:
        _subrule_ctx: subrule_ctx
        lto_config_flag: value of lto attr
    Returns:
        a list of arguments to `scripts/config`
    """

    lto_configs = []

    if lto_config_flag == "fast":
        # buildifier: disable=print
        print("\nWARNING: --lto=fast is deprecated. Falling back to none.")
        lto_config_flag = "none"

    if lto_config_flag == "none":
        lto_configs += [
            _config.disable("LTO_CLANG"),
            _config.enable("LTO_NONE"),
            _config.disable("LTO_CLANG_THIN"),
            _config.disable("LTO_CLANG_FULL"),
            _config.disable("THINLTO"),
            _config.set_val("FRAME_WARN", 0),
        ]
    elif lto_config_flag == "thin":
        lto_configs += [
            _config.enable("LTO_CLANG"),
            _config.disable("LTO_NONE"),
            _config.enable("LTO_CLANG_THIN"),
            _config.disable("LTO_CLANG_FULL"),
            _config.enable("THINLTO"),
        ]
    elif lto_config_flag == "full":
        lto_configs += [
            _config.enable("LTO_CLANG"),
            _config.disable("LTO_NONE"),
            _config.disable("LTO_CLANG_THIN"),
            _config.enable("LTO_CLANG_FULL"),
            _config.disable("THINLTO"),
        ]

    return lto_configs

_config_lto = subrule(implementation = _config_lto_impl)

def _config_trim_impl(subrule_ctx, trim_attr_value, raw_kmi_symbol_list_file, *, _debug, _kgdb):
    """Return configs for trimming.

    Args:
        subrule_ctx: subrule_ctx
        trim_attr_value: value of trim_nonlisted_kmi_utils.get_value(ctx)
        raw_kmi_symbol_list_file: the raw_kmi_symbol_list file
        _debug: --debug
        _kgdb: --kgdb
    Returns:
        a list of arguments to `scripts/config`
    """
    if trim_attr_value and not raw_kmi_symbol_list_file:
        fail("{}: trim_nonlisted_kmi is set but raw_kmi_symbol_list is empty.".format(subrule_ctx.label))

    if not trim_attr_value:
        return []

    if _kgdb[BuildSettingInfo].value:
        # buildifier: disable=print
        print("\nWARNING: {this_label}: Symbol trimming \
              IGNORED because --kgdb is set!".format(this_label = subrule_ctx.label))
        return []

    if _debug[BuildSettingInfo].value:
        # buildifier: disable=print
        print("\nWARNING: {this_label}: Symbol trimming \
              IGNORED because --debug is set!".format(this_label = subrule_ctx.label))
        return []

    return [
        _config.enable("TRIM_UNUSED_KSYMS"),
    ]

_config_trim = subrule(
    implementation = _config_trim_impl,
    attrs = {
        "_debug": attr.label(default = "//build/kernel/kleaf:debug"),
        "_kgdb": attr.label(default = "//build/kernel/kleaf:kgdb"),
    },
)

def _config_symbol_list_impl(_subrule_ctx, raw_kmi_symbol_list_file):
    """Return configs for `raw_symbol_list`.

    Args:
        _subrule_ctx: subrule_ctx
        raw_kmi_symbol_list_file: the raw_kmi_symbol_list file
    Returns:
        a list of arguments to `scripts/config`
    """
    if not raw_kmi_symbol_list_file:
        return []

    return [
        _config.set_str(
            "UNUSED_KSYMS_WHITELIST",
            _RAW_KMI_SYMBOL_LIST_BELOW_OUT_DIR,
        ),
    ]

_config_symbol_list = subrule(implementation = _config_symbol_list_impl)

def _config_keys_impl(_subrule_ctx, module_signing_key_file, system_trusted_key_file):
    """Return configs for module signing keys and system trusted keys.

    Note: by embedding the system path into the binary, the resulting build
    becomes non-deterministic and the path leaks into the binary. It can be
    discovered with `strings` or even by inspecting the kernel config from the
    binary.

    Args:
        _subrule_ctx: subrule_ctx
        module_signing_key_file: file of module_signing_key
        system_trusted_key_file: file of system_trusted_key
    Returns:
        a list of arguments to `scripts/config`
    """
    configs = []
    if module_signing_key_file:
        configs.append(_config.set_str(
            "MODULE_SIG_KEY",
            module_signing_key_file.basename,
        ))

    if system_trusted_key_file:
        configs.append(_config.set_str(
            "SYSTEM_TRUSTED_KEYS",
            system_trusted_key_file.basename,
        ))

    return configs

_config_keys = subrule(implementation = _config_keys_impl)

def _check_trimming_disabled_impl(subrule_ctx, trim_attr_value, **kwargs):
    """Checks that trimming is disabled if --k*san is set

    Args:
        subrule_ctx: subrule_ctx
        trim_attr_value: value of trim_nonlisted_kmi_utils.get_value(ctx)
        **kwargs: must contain all k*san attrs
    """
    if not trim_attr_value:
        return

    for attr_name in (
        "_kasan",
        "_kasan_sw_tags",
        "_kasan_generic",
        "_kcsan",
    ):
        if kwargs[attr_name][BuildSettingInfo].value:
            fail("{}: --{} requires trimming to be disabled".format(subrule_ctx.label, attr_name))

_check_trimming_disabled = subrule(
    implementation = _check_trimming_disabled_impl,
    attrs = {
        "_kasan": attr.label(default = "//build/kernel/kleaf:kasan"),
        "_kasan_sw_tags": attr.label(default = "//build/kernel/kleaf:kasan_sw_tags"),
        "_kasan_generic": attr.label(default = "//build/kernel/kleaf:kasan_generic"),
        "_kcsan": attr.label(default = "//build/kernel/kleaf:kcsan"),
    },
)

def _reconfig_impl(
        _subrule_ctx,
        lto_config_flag,
        trim_attr_value,
        raw_kmi_symbol_list_file,
        module_signing_key_file,
        system_trusted_key_file,
        post_defconfig_fragment_files):
    """Return a command and extra inputs to re-configure `.config` file.

    Args:
        _subrule_ctx: subrule_ctx
        lto_config_flag: value of lto attr
        trim_attr_value: value of trim_nonlisted_kmi_utils.get_value(ctx)
        raw_kmi_symbol_list_file: the raw_kmi_symbol_list file
        module_signing_key_file: file of module_signing_key
        system_trusted_key_file: file of system_trusted_key
        post_defconfig_fragment_files: files of post_defconfig_fragments
    """

    _check_trimming_disabled(trim_attr_value = trim_attr_value)

    configs = []
    apply_post_defconfig_fragments_cmd = ""

    configs += _config_lto(
        lto_config_flag = lto_config_flag,
    )
    configs += _config_trim(
        trim_attr_value = trim_attr_value,
        raw_kmi_symbol_list_file = raw_kmi_symbol_list_file,
    )
    configs += _config_symbol_list(
        raw_kmi_symbol_list_file = raw_kmi_symbol_list_file,
    )
    configs += _config_keys(
        module_signing_key_file = module_signing_key_file,
        system_trusted_key_file = system_trusted_key_file,
    )
    configs += kgdb.get_scripts_config_args()

    if post_defconfig_fragment_files:
        post_defconfig_fragments_paths = [f.path for f in post_defconfig_fragment_files]

        apply_post_defconfig_fragments_cmd = config_utils.create_merge_config_cmd(
            base_expr = "${OUT_DIR}/.config",
            defconfig_fragments_paths_expr = " ".join(post_defconfig_fragments_paths),
        )
        apply_post_defconfig_fragments_cmd += """
            need_olddefconfig=1
        """

    cmd = """
        (
            need_olddefconfig=
            configs_to_apply=$(echo {configs})
            # There could be reconfigurations based on configs which can lead to
            #  an empty `configs_to_apply` even when `configs` is not empty,
            #  for that reason it is better to check it is not empty before using it.
            if [ -n "${{configs_to_apply}}" ]; then
                ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config ${{configs_to_apply}}
                need_olddefconfig=1
            fi

            {apply_post_defconfig_fragments_cmd}

            if [[ -n "${{need_olddefconfig}}" ]]; then
                make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
            fi
        )
    """.format(
        configs = " ".join(configs),
        apply_post_defconfig_fragments_cmd = apply_post_defconfig_fragments_cmd,
    )

    return StepInfo(
        cmd = cmd,
        inputs = depset(post_defconfig_fragment_files),
        outputs = [],
        tools = [],
    )

_reconfig = subrule(
    implementation = _reconfig_impl,
    subrules = [
        _check_trimming_disabled,
        _config_lto,
        _config_trim,
        _config_symbol_list,
        _config_keys,
        kgdb.get_scripts_config_args,
    ],
)

def _set_up_defconfig_impl(subrule_ctx, defconfig_info, is_run_env):
    """Puts defconfig in $OUT_DIR."""
    if not defconfig_info:
        return StepInfo(inputs = depset(), cmd = "", outputs = [], tools = [])
    if not defconfig_info.file:
        # TODO(b/368119551): handle allmodconfig
        return StepInfo(inputs = depset(), cmd = "", outputs = [], tools = [])

    cmd = """
        if [[ -n "${{DEFCONFIG}}" ]]; then
            echo "ERROR: DEFCONFIG cannot be set in build configs if kernel_build.defconfig is set." >&2
            echo "  DEFCONFIG=${{DEFCONFIG}}" >&2
            echo "  kernel_build.defconfig={defconfig_file}" >&2
            exit 1
        fi

        DEFCONFIG=kleaf_internal_{kernel_build_name}_defconfig
        (
            {set_src_arch_cmd}
            if [[ -f "${{KERNEL_DIR}}/arch/${{SRCARCH}}/configs/${{DEFCONFIG}}" ]]; then
                echo "ERROR: Please delete ${{KERNEL_DIR}}/arch/${{SRCARCH}}/configs/${{DEFCONFIG}} and try again." >&2
                exit 1
            fi
            mkdir -p "${{OUT_DIR}}/arch/${{SRCARCH}}/configs/"
            cp -L {defconfig_file} "${{OUT_DIR}}/arch/${{SRCARCH}}/configs/${{DEFCONFIG}}"
        )
    """.format(
        set_src_arch_cmd = kernel_utils.set_src_arch_cmd(),
        kernel_build_name = subrule_ctx.label.name.removesuffix("_config"),
        defconfig_file = defconfig_info.file.short_path if is_run_env else defconfig_info.file.path,
    )
    return StepInfo(
        inputs = depset([defconfig_info.file]),
        cmd = cmd,
        outputs = [],
        tools = [],
    )

_set_up_defconfig = subrule(
    implementation = _set_up_defconfig_impl,
)

def _pre_defconfig_impl(_subrule_ctx, pre_defconfig_fragment_files, is_run_env):
    cmd = ""
    if pre_defconfig_fragment_files:
        cmd += """
            if [[ -n "${{PRE_DEFCONFIG_CMDS}}" ]]; then
                echo "ERROR: PRE_DEFCONFIG_CMDS must not be set if kernel_build.pre_defconfig_fragments is set!" >&2
                echo "  PRE_DEFCONFIG_CMDS=${{PRE_DEFCONFIG_CMDS}}" >&2
                echo "  kernel_build.pre_defconfig_fragments={fragments}" >&2
                exit 1
            fi
        """.format(
            fragments = " ".join([(file.short_path if is_run_env else file.path) for file in pre_defconfig_fragment_files]),
        )
    cmd += """
        # Pre-defconfig commands
        eval ${PRE_DEFCONFIG_CMDS}
    """
    if pre_defconfig_fragment_files:
        apply_pre_defconfig_fragments_cmd = config_utils.create_merge_config_cmd(
            base_expr = "${OUT_DIR}/arch/${SRCARCH}/configs/${DEFCONFIG}",
            defconfig_fragments_paths_expr = " ".join([(file.short_path if is_run_env else file.path) for file in pre_defconfig_fragment_files]),
            quiet = True,
        )
        cmd += """
            (
                {set_src_arch_cmd}
                if ! [[ -f ${{OUT_DIR}}/arch/${{SRCARCH}}/configs/${{DEFCONFIG}} ]]; then
                    echo "ERROR: No base defconfig to apply pre defconfig fragment on!" >&2
                    exit 1
                fi
                # Apply pre_defconfig_fragments
                {apply_pre_defconfig_fragments_cmd}
            )
        """.format(
            set_src_arch_cmd = kernel_utils.set_src_arch_cmd(),
            apply_pre_defconfig_fragments_cmd = apply_pre_defconfig_fragments_cmd,
        )
    return StepInfo(
        inputs = depset(pre_defconfig_fragment_files),
        cmd = cmd,
        outputs = [],
        tools = [],
    )

_pre_defconfig = subrule(
    implementation = _pre_defconfig_impl,
)

def _make_defconfig_impl(_subrule_ctx):
    cmd = """
        # Actual defconfig
        make -C ${KERNEL_DIR} ${TOOL_ARGS} O=${OUT_DIR} ${DEFCONFIG}
    """
    return StepInfo(
        inputs = depset(),
        cmd = cmd,
        outputs = [],
        tools = [],
    )

_make_defconfig = subrule(
    implementation = _make_defconfig_impl,
)

def _post_defconfig_impl(
        _subrule_ctx,
        lto_config_flag,
        trim_attr_value,
        raw_kmi_symbol_list_file,
        module_signing_key_file,
        system_trusted_key_file,
        post_defconfig_fragment_files):
    """Handle post defconfig step

    Args:
        _subrule_ctx: subrule_ctx
        lto_config_flag: value of lto attr
        trim_attr_value: value of trim_nonlisted_kmi_utils.get_value(ctx)
        raw_kmi_symbol_list_file: the raw_kmi_symbol_list file
        module_signing_key_file: file of module_signing_key
        system_trusted_key_file: file of system_trusted_key
        post_defconfig_fragment_files: files of post_defconfig_fragments
    """
    cmd = """
        # Post-defconfig commands
        eval ${POST_DEFCONFIG_CMDS}
    """

    reconfig_ret = _reconfig(
        lto_config_flag = lto_config_flag,
        trim_attr_value = trim_attr_value,
        raw_kmi_symbol_list_file = raw_kmi_symbol_list_file,
        module_signing_key_file = module_signing_key_file,
        system_trusted_key_file = system_trusted_key_file,
        post_defconfig_fragment_files = post_defconfig_fragment_files,
    )
    cmd += reconfig_ret.cmd

    return StepInfo(
        inputs = reconfig_ret.inputs,
        cmd = cmd,
        outputs = reconfig_ret.outputs,
        tools = reconfig_ret.tools,
    )

_post_defconfig = subrule(
    implementation = _post_defconfig_impl,
    subrules = [_reconfig],
)

def _check_dot_config_against_defconfig_impl(
        _subrule_ctx,
        defconfig_info,
        pre_defconfig_fragment_files,
        post_defconfig_fragment_files):
    """Checks .config against defconfig and fragments."""

    check_defconfig_step = None
    transitive_inputs = []
    tools = []
    outputs = []

    if (defconfig_info and defconfig_info.file) or pre_defconfig_fragment_files or post_defconfig_fragment_files:
        check_defconfig_step = config_utils.create_check_defconfig_step(
            defconfig = defconfig_info.file if defconfig_info else None,
            pre_defconfig_fragments = pre_defconfig_fragment_files,
            post_defconfig_fragments = post_defconfig_fragment_files,
        )
        transitive_inputs.append(check_defconfig_step.inputs)
        tools += check_defconfig_step.tools
        outputs += check_defconfig_step.outputs

    return StepInfo(
        cmd = check_defconfig_step.cmd if check_defconfig_step else "",
        inputs = depset(post_defconfig_fragment_files, transitive = transitive_inputs),
        outputs = outputs,
        tools = tools,
    )

_check_dot_config_against_defconfig = subrule(
    implementation = _check_dot_config_against_defconfig_impl,
    subrules = [config_utils.create_check_defconfig_step],
)

def _kernel_config_impl(ctx):
    localversion_file = stamp.write_localversion(ctx)

    inputs = [
        s
        for s in ctx.files.srcs
        if any([token in s.path for token in [
            "Kbuild",
            "Kconfig",
            "Makefile",
            "configs/",
            "scripts/",
            ".fragment",
        ]])
    ]
    transitive_inputs = []
    tools = []

    out_dir = ctx.actions.declare_directory(ctx.attr.name + "/out_dir")
    outputs = [out_dir]

    defconfig_info = None
    if ctx.attr.defconfig:
        if DefconfigInfo in ctx.attr.defconfig:
            defconfig_info = ctx.attr.defconfig[DefconfigInfo]
        elif len(ctx.files.defconfig) == 1:
            defconfig_info = DefconfigInfo(file = ctx.files.defconfig[0])
        else:
            fail("{}: defconfig {} must provide exactly one file".format(ctx.label, ctx.attr.defconfig.label))

    if ctx.attr.pre_defconfig_fragments and not ctx.attr.defconfig:
        fail("{}: Must also set defconfig if using pre_defconfig_fragments".format(ctx.label.name.removesuffix("_config")))

    step_returns = [
        _set_up_defconfig(
            is_run_env = False,
            defconfig_info = defconfig_info,
        ),
        _pre_defconfig(
            is_run_env = False,
            pre_defconfig_fragment_files = ctx.files.pre_defconfig_fragments,
        ),
        _make_defconfig(),
    ]
    step_returns.append(
        _check_dot_config_against_defconfig(
            defconfig_info = defconfig_info,
            pre_defconfig_fragment_files = ctx.files.pre_defconfig_fragments,
            post_defconfig_fragment_files = [],
        ),
    )
    step_returns += [
        _post_defconfig(
            lto_config_flag = ctx.attr.lto,
            trim_attr_value = trim_nonlisted_kmi_utils.get_value(ctx),
            raw_kmi_symbol_list_file = utils.optional_file(ctx.files.raw_kmi_symbol_list),
            module_signing_key_file = ctx.file.module_signing_key,
            system_trusted_key_file = ctx.file.system_trusted_key,
            post_defconfig_fragment_files = ctx.files.post_defconfig_fragments,
        ),
        _check_dot_config_against_defconfig(
            defconfig_info = DefconfigInfo(file = None),
            pre_defconfig_fragment_files = [],
            post_defconfig_fragment_files = ctx.files.post_defconfig_fragments,
        ),
    ]
    transitive_inputs += [step_return.inputs for step_return in step_returns]
    outputs += [out for step_return in step_returns for out in step_return.outputs]
    tools += [tool for step_return in step_returns for tool in step_return.tools]

    transitive_inputs.append(ctx.attr.env[KernelEnvInfo].inputs)
    transitive_tools = [ctx.attr.env[KernelEnvInfo].tools]

    cache_dir_step = cache_dir.get_step(
        ctx = ctx,
        common_config_tags = ctx.attr.env[KernelEnvAttrInfo].common_config_tags,
        symlink_name = "config",
    )
    inputs += cache_dir_step.inputs
    outputs += cache_dir_step.outputs
    tools += cache_dir_step.tools

    inputs.append(localversion_file)

    sync_raw_kmi_symbol_list_cmd = ""
    if ctx.files.raw_kmi_symbol_list:
        sync_raw_kmi_symbol_list_cmd = """
            rsync -aL {raw_kmi_symbol_list} {out_dir}/{raw_kmi_symbol_list_below_out_dir}
        """.format(
            out_dir = out_dir.path,
            raw_kmi_symbol_list = ctx.files.raw_kmi_symbol_list[0].path,
            raw_kmi_symbol_list_below_out_dir = _RAW_KMI_SYMBOL_LIST_BELOW_OUT_DIR,
        )
        inputs += ctx.files.raw_kmi_symbol_list

    # exclude keys in out_dir to avoid accidentally including them
    # in the distribution.

    command = ctx.attr.env[KernelEnvInfo].setup + """
          {cache_dir_cmd}
          {defconfig_cmd}
        # HACK: run syncconfig to avoid re-triggerring kernel_build
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} syncconfig
        # Grab outputs
          rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
          rsync -aL ${{OUT_DIR}}/include/ {out_dir}/include/
          rsync -aL {localversion_file} {out_dir}/localversion
          {sync_raw_kmi_symbol_list_cmd}

        # Ensure reproducibility. The value of the real $ROOT_DIR is replaced in the setup script.
          sed -i'' -e 's:'"${{ROOT_DIR}}"':${{ROOT_DIR}}:g' {out_dir}/include/config/auto.conf.cmd

        # HACK: Ensure we always SYNC auto.conf. This ensures binaries like fixdep are always
        # re-built. See b/263415662
          echo "include/config/auto.conf: FORCE" >> {out_dir}/include/config/auto.conf.cmd

          {cache_dir_post_cmd}
        """.format(
        out_dir = out_dir.path,
        cache_dir_cmd = cache_dir_step.cmd,
        cache_dir_post_cmd = cache_dir_step.post_cmd,
        defconfig_cmd = "\n".join([step_return.cmd for step_return in step_returns]),
        localversion_file = localversion_file.path,
        sync_raw_kmi_symbol_list_cmd = sync_raw_kmi_symbol_list_cmd,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelConfig",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = outputs,
        tools = tools + [depset(transitive = transitive_tools)],
        progress_message = "Creating kernel config{} %{{label}}".format(
            ctx.attr.env[KernelEnvAttrInfo].progress_message_note,
        ),
        command = command,
        execution_requirements = kernel_utils.local_exec_requirements(ctx),
    )

    post_setup_deps = [out_dir]

    extra_restore_outputs_cmd = ""
    for file in (ctx.file.module_signing_key, ctx.file.system_trusted_key):
        if not file:
            continue
        extra_restore_outputs_cmd += """
            rsync -aL {file} ${{OUT_DIR}}/{basename}
        """.format(
            file = file.path,
            basename = file.basename,
        )
        post_setup_deps.append(file)

    # <kernel_build>_config_setup.sh
    serialized_env_info_setup_script = ctx.actions.declare_file("{name}/{name}_setup.sh".format(name = ctx.attr.name))
    ctx.actions.write(
        output = serialized_env_info_setup_script,
        content = get_config_setup_command(
            env_setup_command = ctx.attr.env[KernelEnvInfo].setup,
            out_dir = out_dir,
            extra_restore_outputs_cmd = extra_restore_outputs_cmd,
        ),
    )

    serialized_env_info = KernelSerializedEnvInfo(
        setup_script = serialized_env_info_setup_script,
        tools = ctx.attr.env[KernelEnvInfo].tools,
        inputs = depset(post_setup_deps + [
            serialized_env_info_setup_script,
        ], transitive = transitive_inputs),
    )

    config_script_ret = _get_config_script(
        run_env = ctx.attr.env[KernelEnvInfo].run_env,
        defconfig_info = defconfig_info,
        pre_defconfig_fragment_files = ctx.files.pre_defconfig_fragments,
    )
    config_script_runfiles = ctx.runfiles(
        files = inputs,
        transitive_files = depset(transitive = transitive_inputs + [
            ctx.attr.env[KernelEnvInfo].run_env.inputs,
            ctx.attr.env[KernelEnvInfo].run_env.tools,
            config_script_ret.inputs,
        ]),
    )

    return [
        serialized_env_info,
        ctx.attr.env[KernelEnvAttrInfo],
        ctx.attr.env[KernelEnvMakeGoalsInfo],
        ctx.attr.env[KernelToolchainInfo],
        KernelBuildOriginalEnvInfo(
            env_info = ctx.attr.env[KernelEnvInfo],
        ),
        DefaultInfo(
            files = depset([out_dir]),
            executable = config_script_ret.executable,
            runfiles = config_script_runfiles,
        ),
        KernelConfigInfo(
            env_setup_script = ctx.file.env,
        ),
    ]

def _get_config_script_impl(
        subrule_ctx,
        run_env,
        defconfig_info,
        pre_defconfig_fragment_files):
    """Handles config.sh.

    Args:
        subrule_ctx: subrule_ctx
        run_env: from kernel_env[KernelEnvInfo].run_env
        defconfig_info: the DefconfigInfo from attr defconfig
        pre_defconfig_fragment_files: list of files of pre_defconfig_fragments
    """
    executable = subrule_ctx.actions.declare_file("{}/config.sh".format(subrule_ctx.label.name))

    step_returns = [
        _set_up_defconfig(
            is_run_env = True,
            defconfig_info = defconfig_info,
        ),
        _pre_defconfig(
            is_run_env = True,
            pre_defconfig_fragment_files = pre_defconfig_fragment_files,
        ),
        _make_defconfig(),
    ]

    # We can't handle outputs because this is a `run` command not a `build` command.
    if [out for step_return in step_returns for out in step_return.outputs]:
        fail("ERROR: None of the defconfig steps should produce outputs! {}".format(
            [step_return.outputs for step_return in step_returns],
        ))

    # We can't handle tools yet because it may contain FilesToRunProvider, which can't be placed
    # in runfiles directly.
    if [tool for step_return in step_returns for tool in step_return.tools]:
        fail("ERROR: None of the defconfig steps should require tools! {}".format(
            [step_return.tools for step_return in step_returns],
        ))

    script = run_env.setup

    # TODO(b/254348147): Support ncurses for hermetic tools
    script += """
        export HOSTCFLAGS="${HOSTCFLAGS} --sysroot="
        export HOSTLDFLAGS="${HOSTLDFLAGS} --sysroot="
    """
    script += kernel_utils.set_src_arch_cmd()
    script += """
        menucommand="${1:-savedefconfig}"
        if ! [[ "${menucommand}" =~ .*config ]]; then
            echo "Invalid command $menucommand. Must be *config." >&2
            exit 1
        fi
    """
    script += "\n".join([step_return.cmd for step_return in step_returns])

    inputs = []

    if not defconfig_info or not defconfig_info.file:
        # Legacy code path.
        # TODO(b/368119551): Clean up once kernel_build.defconfig is required.
        script += """
            # Show UI
            menuconfig ${menucommand}
        """
    else:
        inputs.append(defconfig_info.file)
        script += """
            (
                orig_config=$(mktemp)
                changed_config=$(mktemp)
                new_fragment=$(mktemp)
                trap "rm -f ${orig_config} ${changed_config} ${new_fragment}" EXIT
                new_config="${OUT_DIR}/.config"
                cp "${OUT_DIR}/.config" ${orig_config}
                make -C ${KERNEL_DIR} ${TOOL_ARGS} O=${OUT_DIR} ${MAKE_ARGS} ${menucommand}
        """

        if pre_defconfig_fragment_files:
            script += """
                ${{KERNEL_DIR}}/scripts/diffconfig -m ${{orig_config}} ${{new_config}} > ${{changed_config}}
                KCONFIG_CONFIG=${{new_fragment}} ${{ROOT_DIR}}/${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh -m {fragments} ${{changed_config}}
            """.format(
                fragments = " ".join([file.short_path for file in pre_defconfig_fragment_files]),
            )
            if len(pre_defconfig_fragment_files) == 1:
                script += """
                    sort_config ${{new_fragment}} > $(realpath {fragment})
                    echo "Updated $(realpath {fragment})"
                """.format(
                    fragment = pre_defconfig_fragment_files[0].short_path,
                )
            else:
                script += """
                    sorted_new_fragment=$(mktemp)
                    sort_config ${{new_fragment}} > ${{sorted_new_fragment}}
                    echo "ERROR: Unable to update any file because there are multiple pre_defconfig_fragments." >&2
                    echo "  Please manually update the following files:" >&2
                    echo "    "{quoted_indented_fragments} >&2
                    echo "  ... with the content of ..." >&2
                    echo "    ${{sorted_new_fragment}}" >&2
                    # Intentionally not delete sorted_new_fragment
                    exit 1
                """.format(
                    quoted_indented_fragments = shell.quote("\n    ".join([file.short_path for file in pre_defconfig_fragment_files])),
                )
        else:
            script += """
                make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{MAKE_ARGS}} savedefconfig
                mv ${{OUT_DIR}}/defconfig $(realpath {defconfig})
                echo "Updated $(realpath {defconfig})"
            """.format(
                defconfig = defconfig_info.file.short_path,
            )

        script += """
            )
        """

    script += """
        # Post-defconfig commands
        eval ${POST_DEFCONFIG_CMDS}
    """
    # Do not apply any post_defconfig_fragments because:
    # - They have no effect; we already saved necessary defconfig and fragments.
    # - They usually refer to variants of the build, controlled by attributes, flag values, etc.
    #   See kernel_build.defconfig_fragments for details.

    subrule_ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )
    return struct(
        executable = executable,
        inputs = depset(inputs, transitive = [step_return.inputs for step_return in step_returns]),
    )

_get_config_script = subrule(
    implementation = _get_config_script_impl,
    subrules = [
        _set_up_defconfig,
        _pre_defconfig,
        _make_defconfig,
    ],
)

def get_config_setup_command(
        env_setup_command,
        out_dir,
        extra_restore_outputs_cmd):
    """Returns the content of `<kernel_build>_config_setup.sh`, given the parameters.

    Args:
        env_setup_command: command to set up environment from `kernel_env`
        out_dir: output directory from `kernel_config`
        extra_restore_outputs_cmd: Extra CMD to restore outputs
    Returns:
        the command to setup the environment like after `make defconfig`.
    """

    cmd = """
        {env_setup_command}
        {eval_restore_out_dir_cmd}

        [ -z ${{OUT_DIR}} ] && echo "FATAL: configs post_env_info setup run without OUT_DIR set!" >&2 && exit 1
        # Restore kernel config inputs
        mkdir -p ${{OUT_DIR}}/include/
        rsync -aL {out_dir}/.config ${{OUT_DIR}}/.config
        rsync -aL --chmod=D+w {out_dir}/include/ ${{OUT_DIR}}/include/
        rsync -aL --chmod=F+w {out_dir}/localversion ${{OUT_DIR}}/localversion
        if [[ -f {out_dir}/{raw_kmi_symbol_list_below_out_dir} ]]; then
            rsync -aL --chmod=F+w \\
                {out_dir}/{raw_kmi_symbol_list_below_out_dir} ${{OUT_DIR}}/
        fi

        # Restore real value of $ROOT_DIR in auto.conf.cmd
        sed -i'' -e 's:${{ROOT_DIR}}:'"${{ROOT_DIR}}"':g' ${{OUT_DIR}}/include/config/auto.conf.cmd
    """.format(
        env_setup_command = env_setup_command,
        eval_restore_out_dir_cmd = kernel_utils.eval_restore_out_dir_cmd(),
        out_dir = out_dir.path,
        raw_kmi_symbol_list_below_out_dir = _RAW_KMI_SYMBOL_LIST_BELOW_OUT_DIR,
    )
    cmd += extra_restore_outputs_cmd
    return cmd

def _kernel_config_additional_attrs():
    return dicts.add(
        kernel_config_settings.of_kernel_config(),
        cache_dir.attrs(),
    )

kernel_config = rule(
    implementation = _kernel_config_impl,
    doc = """Defines a kernel config target.

- When `bazel build <target>`, this target runs `make defconfig` etc. during the build.
- When `bazel run <target> -- Xconfig`, this target runs `make Xconfig`.
""",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [
                KernelEnvInfo,
                KernelEnvAttrInfo,
                KernelEnvMakeGoalsInfo,
                KernelToolchainInfo,
            ],
            doc = "environment target that defines the kernel build environment",
            allow_single_file = True,
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "raw_kmi_symbol_list": attr.label(
            doc = "Label to abi_symbollist.raw. Must be 0 or 1 file.",
            allow_files = True,
        ),
        "module_signing_key": attr.label(
            doc = "Label to module signing key.",
            allow_single_file = True,
        ),
        "system_trusted_key": attr.label(
            doc = "Label to trusted system key.",
            allow_single_file = True,
        ),
        "defconfig": attr.label(allow_files = True),
        "pre_defconfig_fragments": attr.label_list(
            doc = "**pre** defconfig fragments",
            allow_files = True,
        ),
        "post_defconfig_fragments": attr.label_list(
            doc = "**post** defconfig fragments",
            allow_files = True,
        ),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    } | _kernel_config_additional_attrs(),
    executable = True,
    toolchains = [hermetic_toolchain.type],
    subrules = [
        _set_up_defconfig,
        _pre_defconfig,
        _make_defconfig,
        _check_defconfig_minimized,
        _post_defconfig,
        _check_dot_config_against_defconfig,
        _get_config_script,
    ],
)
