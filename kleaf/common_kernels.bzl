# Copyright (C) 2021 The Android Open Source Project
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

"""Functions that are useful in the common kernel package (usually `//common`)."""

load("@bazel_skylib//lib:selects.bzl", "selects")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load("//build/kernel/kleaf/artifact_tests:device_modules_test.bzl", "device_modules_test")
load("//build/kernel/kleaf/artifact_tests:kernel_test.bzl", "initramfs_modules_options_test")
load("//build/kernel/kleaf/impl:gki_artifacts.bzl", "gki_artifacts", "gki_artifacts_prebuilts")
load("//build/kernel/kleaf/impl:image/initramfs.bzl", "initramfs")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", "kernel_images_filegroup")
load("//build/kernel/kleaf/impl:kernel_filegroup_declaration.bzl", "kernel_filegroup_declaration")
load(
    "//build/kernel/kleaf/impl:kernel_prebuilt_utils.bzl",
    "CI_TARGET_MAPPING",
)
load("//build/kernel/kleaf/impl:kernel_sbom.bzl", "kernel_sbom")
load("//build/kernel/kleaf/impl:out_headers_allowlist_archive.bzl", "out_headers_allowlist_archive")
load(
    ":kernel.bzl",
    "kernel_abi",
    "kernel_abi_dist",
    "kernel_build",
    "kernel_build_config",
    "kernel_modules_install",
    "kernel_unstripped_modules_archive",
    "system_dlkm_image",
)
load(":print_debug.bzl", "print_debug")

# Always collect_unstripped_modules for common kernels.
_COLLECT_UNSTRIPPED_MODULES = True

# Always strip modules for common kernels.
_STRIP_MODULES = True

# Always keep a copy of Module.symvers for common kernels.
_KEEP_MODULE_SYMVERS = True

# This transition is not needed for GKI
_GKI_ADD_VMLINUX = False

def common_kernel(
        name,
        outs,
        build_config,
        makefile = None,
        arch = None,
        visibility = None,
        toolchain_version = None,
        enable_interceptor = None,
        kmi_symbol_list = None,
        additional_kmi_symbol_lists = None,
        trim_nonlisted_kmi = None,
        kmi_symbol_list_strict_mode = None,
        kmi_symbol_list_add_only = None,
        module_implicit_outs = None,
        protected_exports_list = None,
        protected_modules_list = None,
        gki_system_dlkm_modules = None,
        make_goals = None,
        abi_definition_stg = None,
        kmi_enforced = None,
        build_gki_artifacts = None,
        gki_boot_img_sizes = None,
        page_size = None,
        deprecation = None,
        ddk_headers_archive = None,
        ddk_module_headers = None,
        extra_dist = None):
    """Macro for an Android Common Kernel.

    The following targets are declared as public API:
    -   `<name>_sources` (e.g. `kernel_aarch64_sources`)
        -   Convenience filegroups that refers to all sources required to
            build `<name>` and related targets.
    -   `<name>` (e.g. `kernel_aarch64`): [`kernel_build()`](kernel.md#kernel_build)
        -   This build the main kernel build artifacts, e.g. `vmlinux`, etc.
    -   `<name>_uapi_headers` (e.g. `kernel_aarch64_uapi_headers`)
        -   build `kernel-uapi-headers.tar.gz`.
    -   `<name>_modules` (e.g. `kernel_aarch64_modules`)
    -   `<name>_additional_artifacts` (e.g. `kernel_aarch64_additional_artifacts`)
        -   contains additional artifacts that may be added to
            a distribution. This includes:
            -   Images, including `system_dlkm`, etc.
            -   `kernel-headers.tar.gz`
    -   `<name>_dist` (e.g. `kernel_aarch64_dist`)
        -   can be run to obtain a distribution outside the workspace.

    **ABI monitoring**
    If `kmi_symbol_list` is set, ABI monitoring is turned on.

    -    `<name>_abi` (e.g. `kernel_aarch64_abi`): [`kernel_abi()`](kernel.md#kernel_abi)
    -    `<name>_abi_dist` (e.g. `kernel_aarch64_abi_dist`)

    Usually, for ABI monitoring to be fully turned on, you should set:
    -   `kmi_symbol_list`
    -   `additional_kmi_symbol_lists`
    -   `protected_exports_list`
    -   `protected_modules_list`
    -   `trim_nonlisted_kmi` to True
    -   `kmi_symbol_list_strict_mode` to True
    -   `abi_definition_stg` to the ABI definition
    -   `kmi_enforced` to True

    Args:
        name: name of the kernel_build().
        outs: See [kernel_build.outs](kernel.md#kernel_build-outs)
        arch: See [kernel_build.arch](kernel.md#kernel_build-arch)
        build_config: See [kernel_build.build_config](kernel.md#kernel_build-build_config)
        makefile: See [kernel_build.makefile](kernel.md#kernel_build-makefile)
        toolchain_version: See [kernel_build.toolchain_version](kernel.md#kernel_build-toolchain_version)
        enable_interceptor: See [kernel_build.enable_interceptor](kernel.md#kernel_build-enable_interceptor)
        kmi_symbol_list: See [kernel_build.kmi_symbol_list](kernel.md#kernel_build-kmi_symbol_list)
        additional_kmi_symbol_lists: See [kernel_build.additional_kmi_symbol_lists](kernel.md#kernel_build-additional_kmi_symbol_lists)
        trim_nonlisted_kmi: See [kernel_build.trim_nonlisted_kmi](kernel.md#kernel_build-trim_nonlisted_kmi)
        kmi_symbol_list_strict_mode: See [kernel_build.kmi_symbol_list_strict_mode](kernel.md#kernel_build-kmi_symbol_list_strict_mode)
        module_implicit_outs: See [kernel_build.module_implicit_outs](kernel.md#kernel_build-module_implicit_outs)
        kmi_symbol_list_add_only: See [kernel_abi.kmi_symbol_list_add_only](kernel.md#kernel_abi-kmi_symbol_list_add_only)
        protected_exports_list: See [kernel_build.protected_exports_list](kernel.md#kernel_build-protected_exports_list)
        protected_modules_list: See [kernel_build.protected_modules_list](kernel.md#kernel_build-protected_modules_list)
        make_goals: See [kernel_build.make_goals](kernel.md#kernel_build-make_goals)
        abi_definition_stg: See [kernel_abi.abi_definition_stg](kernel.md#kernel_abi-abi_definition_stg)
        kmi_enforced: See [kernel_abi.kmi_enforced](kernel.md#kernel_abi-kmi_enforced)
        page_size: See [kernel_build.page_size](kernel.md#kernel_build-page_size)
        ddk_module_headers: See [kernel_build.ddk_module_headers](kernel.md#kernel_build-ddk_module_headers)
        gki_system_dlkm_modules: system_dlkm module_list
        build_gki_artifacts: nonconfigurable. If true, build GKI artifacts under
            target name `<name>_gki_artifacts`.
        gki_boot_img_sizes: gki_artifacts.boot_img_sizes
        visibility: default visibility for some targets instantiated with this macro
        deprecation: If set, mark target deprecated with given message.
        ddk_headers_archive: nonconfigurable. Target to the archive packing DDK headers
        extra_dist: extra targets added to `<name>_dist`
    """
    json_target_config = dict(
        name = name,
        outs = outs,
        arch = arch,
        build_config = build_config,
        makefile = makefile,
        toolchain_version = toolchain_version,
        visibility = visibility,
        enable_interceptor = enable_interceptor,
        kmi_symbol_list = kmi_symbol_list,
        additional_kmi_symbol_lists = additional_kmi_symbol_lists,
        trim_nonlisted_kmi = trim_nonlisted_kmi,
        kmi_symbol_list_strict_mode = kmi_symbol_list_strict_mode,
        module_implicit_outs = module_implicit_outs,
        protected_exports_list = protected_exports_list,
        protected_modules_list = protected_modules_list,
        gki_system_dlkm_modules = gki_system_dlkm_modules,
        make_goals = make_goals,
        abi_definition_stg = abi_definition_stg,
        kmi_enforced = kmi_enforced,
        build_gki_artifacts = build_gki_artifacts,
        gki_boot_img_sizes = gki_boot_img_sizes,
        page_size = page_size,
        deprecation = deprecation,
        ddk_headers_archive = ddk_headers_archive,
        ddk_module_headers = ddk_module_headers,
        extra_dist = extra_dist,
    )

    print_debug(
        name = name + "_print_configs",
        content = "common_kernel({})".format("".join([
            "    {} = {},\n".format(k, repr(v))
            for k, v in json_target_config.items()
        ])),
        tags = ["manual"],
    )

    native.alias(
        name = name + "_sources",
        actual = ":common_kernel_sources",
    )

    all_kmi_symbol_lists = additional_kmi_symbol_lists
    all_kmi_symbol_lists = [] if all_kmi_symbol_lists == None else list(all_kmi_symbol_lists)

    # Add user KMI symbol lists to additional lists
    additional_kmi_symbol_lists = all_kmi_symbol_lists + [
        "//build/kernel/kleaf:user_kmi_symbol_lists",
    ]

    if kmi_symbol_list:
        all_kmi_symbol_lists.append(kmi_symbol_list)

    native.filegroup(
        name = name + "_all_kmi_symbol_lists",
        srcs = all_kmi_symbol_lists,
    )

    kernel_build_config(
        name = name + "_build_config",
        srcs = [
            # do not sort
            build_config,
            Label("//build/kernel/kleaf:gki_build_config_fragment"),
        ],
    )

    kernel_build(
        name = name,
        srcs = [name + "_sources"],
        outs = outs,
        arch = arch,
        implicit_outs = [
            # Kernel build time module signing utility and keys
            # Only available during GKI builds
            # Device fragments need to add: '# CONFIG_MODULE_SIG_ALL is not set'
            "scripts/sign-file",
            "certs/signing_key.pem",
            "certs/signing_key.x509",
        ],
        build_config = name + "_build_config",
        makefile = makefile,
        enable_interceptor = enable_interceptor,
        visibility = visibility,
        collect_unstripped_modules = _COLLECT_UNSTRIPPED_MODULES,
        strip_modules = _STRIP_MODULES,
        toolchain_version = toolchain_version,
        keep_module_symvers = _KEEP_MODULE_SYMVERS,
        kmi_symbol_list = kmi_symbol_list,
        additional_kmi_symbol_lists = additional_kmi_symbol_lists,
        trim_nonlisted_kmi = trim_nonlisted_kmi,
        kmi_symbol_list_strict_mode = kmi_symbol_list_strict_mode,
        module_implicit_outs = module_implicit_outs,
        protected_exports_list = protected_exports_list,
        protected_modules_list = protected_modules_list,
        make_goals = make_goals,
        page_size = page_size,
        deprecation = deprecation,
        pack_module_env = True,
        ddk_module_defconfig_fragments = [
            Label("//build/kernel/kleaf/impl/defconfig:signing_modules_disabled"),
        ],
        ddk_module_headers = ddk_module_headers,
    )

    kernel_abi(
        name = name + "_abi",
        kernel_build = name,
        visibility = visibility,
        define_abi_targets = bool(kmi_symbol_list),
        # Sync with KMI_SYMBOL_LIST_MODULE_GROUPING
        module_grouping = None,
        abi_definition_stg = abi_definition_stg,
        kmi_enforced = kmi_enforced,
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        deprecation = deprecation,
        enable_add_vmlinux = _GKI_ADD_VMLINUX,
    )

    if enable_interceptor:
        return

    # A subset of headers in OUT_DIR that only contains scripts/. This is useful
    # for DDK headers interpolation.
    out_headers_allowlist_archive(
        name = name + "_script_headers",
        kernel_build = name,
        subdirs = ["scripts"],
    )

    native.filegroup(
        name = name + "_ddk_allowlist_headers",
        srcs = [
            name + "_script_headers",
            name + "_uapi_headers",
        ],
        visibility = [
            Label("//build/kernel/kleaf:__pkg__"),
        ],
    )

    kernel_modules_install(
        name = name + "_modules_install",
        # The GKI target does not have external modules. GKI modules goes
        # into the in-tree kernel module list, aka kernel_build.module_implicit_outs.
        # Hence, this is empty.
        kernel_modules = [],
        kernel_build = name,
    )

    kernel_unstripped_modules_archive(
        name = name + "_unstripped_modules_archive",
        kernel_build = name,
    )

    system_dlkm_image(
        name = name + "_system_dlkm_image",
        kernel_modules_install = name + "_modules_install",
        build_flatten = True,
        modules_list = gki_system_dlkm_modules,
        fs_types = ["erofs", "ext4"],
    )

    kernel_images_filegroup(
        name = name + "_images",
        srcs = [name + "_system_dlkm_image"],
        deprecation = "Use {} instead".format(native.package_relative_label(name + "_system_dlkm_image")),
    )

    if build_gki_artifacts:
        gki_artifacts(
            name = name + "_gki_artifacts",
            kernel_build = name,
            boot_img_sizes = gki_boot_img_sizes,
            arch = arch,
        )
    else:
        native.filegroup(
            name = name + "_gki_artifacts",
            srcs = [],
        )

    # modules_staging_archive from <name>
    native.filegroup(
        name = name + "_modules_staging_archive",
        srcs = [name],
        output_group = "modules_staging_archive",
    )

    # All GKI modules
    native.filegroup(
        name = name + "_modules",
        srcs = [
            "{}/{}".format(name, module)
            for module in (module_implicit_outs or [])
        ],
    )

    # The purpose of this target is to allow device kernel build to include reasonable
    # defaults of artifacts from GKI. Hence, this target includes everything in name + "_dist",
    # excluding the following:
    # - UAPI headers, because device-specific external kernel modules may install different
    #   headers.
    # - DDK; see _ddk_artifacts below.
    native.filegroup(
        name = name + "_additional_artifacts",
        srcs = [
            # Sync with additional_artifacts_items
            name + "_headers",
            name + "_system_dlkm_image",
            name + "_kmi_symbol_list",
            name + "_raw_kmi_symbol_list",
            name + "_gki_artifacts",
        ],
    )

    filegroup_extra_deps = [
        name + "_unstripped_modules_archive",
    ]
    kernel_filegroup_declaration(
        name = name + "_filegroup_declaration",
        kernel_build = name,
        extra_deps = filegroup_extra_deps,
        images = name + "_system_dlkm_image",
        visibility = ["//visibility:private"],
    )
    target_mapping = CI_TARGET_MAPPING.get(name, {})
    write_file(
        name = name + "_download_configs",
        content = [
            json.encode_indent(target_mapping.get("download_configs", {})),
        ],
        # / is needed to distinguish between variants as 16k (and avoid conflicts).
        out = name + "/download_configs.json",
    )

    # Everything in name + "_dist" for the DDK.
    # These are necessary for driver development. Hence they are also added to
    # kernel_*_dist so they can be downloaded.
    ddk_artifacts = [
        name + "_download_configs",
        name + "_filegroup_declaration",
        name + "_unstripped_modules_archive",
    ]
    if ddk_headers_archive:
        ddk_artifacts.append(ddk_headers_archive)
    native.filegroup(
        name = name + "_ddk_artifacts",
        srcs = ddk_artifacts,
    )

    dist_targets = (extra_dist or []) + [
        name,
        name + "_uapi_headers",
        name + "_additional_artifacts",
        name + "_ddk_artifacts",
        name + "_modules",
        name + "_modules_install",
        # BUILD_GKI_CERTIFICATION_TOOLS=1 for all kernel_build defined here.
        Label("//build/kernel:gki_certification_tools"),
        "build.config.constants",
        Label("//build/kernel:init_ddk_zip"),
    ]

    kernel_sbom(
        name = name + "_sbom",
        srcs = dist_targets,
        kernel_build = name,
    )

    dist_targets.append(name + "_sbom")

    copy_to_dist_dir(
        name = name + "_dist",
        data = dist_targets,
        flat = True,
        dist_dir = "out/{name}/dist".format(name = name),
        log = "info",
    )

    kernel_abi_dist_name = name + "_abi_dist"
    kernel_abi_dist(
        name = kernel_abi_dist_name,
        kernel_abi = name + "_abi",
        kernel_build_add_vmlinux = _GKI_ADD_VMLINUX,
        data = dist_targets,
        flat = True,
        dist_dir = "out_abi/{name}/dist".format(name = name),
        log = "info",
    )

    kernel_abi_dist(
        name = name + "_abi_ignore_diff_dist",
        kernel_abi = name + "_abi",
        kernel_build_add_vmlinux = _GKI_ADD_VMLINUX,
        data = dist_targets,
        flat = True,
        dist_dir = "out_abi/{name}/dist".format(name = name),
        log = "info",
        ignore_diff = True,
        no_ignore_diff_target = kernel_abi_dist_name,
    )

    _define_common_kernels_additional_tests(
        name = name + "_additional_tests",
        kernel_build_name = name,
        kernel_modules_install = name + "_modules_install",
        modules = (module_implicit_outs or []),
        arch = arch,
    )

    native.test_suite(
        name = name + "_tests",
        tests = [
            name + "_additional_tests",
            name + "_test",
            name + "_modules_test",
        ],
    )

# TODO(b/291918087): Delete once users have migrated to @gki_prebuilts
# buildifier: disable=unnamed-macro
def define_prebuilts(**kwargs):
    """Define --use_prebuilt_gki and relevant targets.

    You may set the argument `--use_prebuilt_gki` to a GKI prebuilt build number
    on [ci.android.com](http://ci.android.com) or your custom CI host. The format is:

    ```
    bazel <command> --use_prebuilt_gki=<build_number> <targets>
    ```

    For example, the following downloads GKI artifacts of build number 8077484 (assuming
    the current package is `//common`):

    ```
    bazel build --use_prebuilt_gki=8077484 //common:kernel_aarch64_download_or_build
    ```

    If you leave out the `--use_prebuilt_gki` argument, the command is equivalent to
    `bazel build //common:kernel_aarch64`, which builds kernel from source.

    `<name>_download_or_build` targets builds `<name>` from source if the `use_prebuilt_gki`
    is not set, and downloads artifacts of the build number from
    [ci.android.com](http://ci.android.com) (or your custom CI host) if it is set.

    - `kernel_aarch64_download_or_build`
      - `kernel_aarch64_additional_artifacts_download_or_build`
      - `kernel_aarch64_uapi_headers_download_or_build`

    Note: If a device should build against downloaded prebuilts unconditionally, set
    `--use_prebuilt_gki` and a fixed build number in `device.bazelrc`. For example:
    ```
    # device.bazelrc
    build --use_prebuilt_gki
    build --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER_MAP="gki_prebuilts=8077484"
    ```

    This is equivalent to specifying `--use_prebuilt_gki=8077484` for all Bazel commands.

    You may set `--use_signed_prebuilts` to download the signed boot images instead
    of the unsigned one. This requires `--use_prebuilt_gki` to be set to a signed build.

    Args:
        **kwargs: common kwargs to internal targets.

    Deprecated:
        See build/kernel/kleaf/docs/ddk/workspace.md for new ways to define prebuilts.
    """

    # Legacy flag for backwards compatibility
    # TODO(https://github.com/bazelbuild/bazel/issues/13463): alias to bool_flag does not
    # work. Hence we use a composite flag here.
    bool_flag(
        name = "use_prebuilt_gki",
        build_setting_default = False,
        # emit a warning if the legacy flag is used.
        deprecation = "Use {} or {} instead, respectively.".format(
            Label("//build/kernel/kleaf:use_prebuilt_gki"),
            Label("//build/kernel/kleaf:use_prebuilt_gki_is_true"),
        ),
    )
    native.config_setting(
        name = "local_use_prebuilt_gki_set",
        flag_values = {
            ":use_prebuilt_gki": "true",
        },
        visibility = ["//visibility:private"],
    )

    # Matches when --use_prebuilt_gki or --//<common_package>:use_prebuilt_gki is set
    selects.config_setting_group(
        name = "use_prebuilt_gki_set",
        match_any = [
            Label("//build/kernel/kleaf:use_prebuilt_gki_is_true"),
            ":local_use_prebuilt_gki_set",
        ],
    )

    for name, value in CI_TARGET_MAPPING.items():
        repo_name = value["repo_name"]
        deprecate_msg = "Use @{}//{} directly".format(repo_name, name)
        not_available_msg = "This will no longer be available. File a bug if you rely on this target."

        native.alias(
            name = name + "_downloaded",
            actual = name + "_files_downloaded",
            deprecation = deprecate_msg,
        )

        # A kernel_filegroup that:
        # - If --use_prebuilt_gki_num is set, use downloaded prebuilt of kernel_aarch64
        # - Otherwise build kernel_aarch64 from sources.
        native.alias(
            name = name + "_download_or_build",
            actual = select({
                ":use_prebuilt_gki_set": "@{}//{}".format(repo_name, name),
                "//conditions:default": name,
            }),
            deprecation = deprecate_msg,
            **kwargs
        )

        gki_artifacts_prebuilts(
            name = name + "_gki_artifacts_downloaded",
            srcs = select({
                Label("//build/kernel/kleaf:use_signed_prebuilts_is_true"): [name + "_boot_img_archive_signed_downloaded"],
                "//conditions:default": [name + "_boot_img_archive_downloaded"],
            }),
            outs = [name + "_gki_prebuilts_outs_downloaded"],
            deprecation = deprecate_msg,
        )

        native.filegroup(
            name = name + "_gki_artifacts_download_or_build",
            srcs = select({
                ":use_prebuilt_gki_set": [name + "_gki_artifacts_downloaded"],
                "//conditions:default": [name + "_gki_artifacts"],
            }),
            deprecation = deprecate_msg,
            **kwargs
        )

        files_by_target_suffix = {}
        for local_filename, config in value["download_configs"].items():
            files_by_target_suffix.setdefault(config["target_suffix"], []).append(local_filename)

        for target_suffix, files in files_by_target_suffix.items():
            native.filegroup(
                name = name + "_" + target_suffix + "_downloaded",
                srcs = ["@{}//{}".format(repo_name, filename) for filename in files],
                tags = ["manual"],
                deprecation = deprecate_msg,
            )

            # A filegroup that:
            # - If --use_prebuilt_gki_num is set, use downloaded prebuilt of kernel_{arch}_{target_suffix}
            # - Otherwise build kernel_{arch}_{target_suffix}
            native.filegroup(
                name = name + "_" + target_suffix + "_download_or_build",
                srcs = select({
                    ":use_prebuilt_gki_set": [":" + name + "_" + target_suffix + "_downloaded"],
                    "//conditions:default": [name + "_" + target_suffix],
                }),
                deprecation = deprecate_msg,
                **kwargs
            )

        additional_artifacts_items = [
            name + "_headers",
            name + "_system_dlkm_image",
            name + "_kmi_symbol_list",
            name + "_gki_artifacts",
        ]

        native.filegroup(
            name = name + "_additional_artifacts_downloaded",
            srcs = [item + "_downloaded" for item in additional_artifacts_items],
            deprecation = not_available_msg,
        )

        native.filegroup(
            name = name + "_additional_artifacts_download_or_build",
            srcs = [item + "_download_or_build" for item in additional_artifacts_items],
            deprecation = not_available_msg,
        )

def _define_common_kernels_additional_tests(
        name,
        kernel_build_name,
        kernel_modules_install,
        modules,
        arch):
    fake_modules_options = Label("//build/kernel/kleaf/artifact_tests:fake_modules_options.txt")

    initramfs(
        name = name + "_fake_initramfs",
        kernel_modules_install = kernel_modules_install,
        modules_options = fake_modules_options,
    )

    initramfs_modules_options_test(
        name = name + "_fake",
        kernel_images = name + "_fake_initramfs",
        expected_modules_options = fake_modules_options,
    )

    write_file(
        name = name + "_empty_modules_options",
        out = name + "_empty_modules_options/modules.options",
        content = [],
    )

    initramfs(
        name = name + "_empty_initramfs",
        kernel_modules_install = kernel_modules_install,
        # Not specify module_options
    )

    initramfs_modules_options_test(
        name = name + "_empty",
        kernel_images = name + "_empty_initramfs",
        expected_modules_options = name + "_empty_modules_options",
    )

    device_modules_test(
        name = name + "_device_modules_test",
        srcs = [kernel_build_name + "_sources"],
        base_kernel_label = native.package_relative_label(kernel_build_name),
        base_kernel_module = min(modules) if modules else None,
        arch = arch,
    )

    native.test_suite(
        name = name,
        tests = [
            name + "_empty",
            name + "_fake",
            name + "_device_modules_test",
        ],
    )
