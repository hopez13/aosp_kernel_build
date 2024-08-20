<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Functions that are useful in the common kernel package (usually `//common`).

<a id="common_kernel"></a>

## common_kernel

<pre>
common_kernel(<a href="#common_kernel-name">name</a>, <a href="#common_kernel-outs">outs</a>, <a href="#common_kernel-build_config">build_config</a>, <a href="#common_kernel-arch">arch</a>, <a href="#common_kernel-visibility">visibility</a>, <a href="#common_kernel-toolchain_version">toolchain_version</a>, <a href="#common_kernel-defconfig_fragments">defconfig_fragments</a>,
              <a href="#common_kernel-enable_interceptor">enable_interceptor</a>, <a href="#common_kernel-kmi_symbol_list">kmi_symbol_list</a>, <a href="#common_kernel-additional_kmi_symbol_lists">additional_kmi_symbol_lists</a>, <a href="#common_kernel-trim_nonlisted_kmi">trim_nonlisted_kmi</a>,
              <a href="#common_kernel-kmi_symbol_list_strict_mode">kmi_symbol_list_strict_mode</a>, <a href="#common_kernel-kmi_symbol_list_add_only">kmi_symbol_list_add_only</a>, <a href="#common_kernel-module_implicit_outs">module_implicit_outs</a>,
              <a href="#common_kernel-protected_exports_list">protected_exports_list</a>, <a href="#common_kernel-protected_modules_list">protected_modules_list</a>, <a href="#common_kernel-gki_system_dlkm_modules">gki_system_dlkm_modules</a>, <a href="#common_kernel-make_goals">make_goals</a>,
              <a href="#common_kernel-abi_definition_stg">abi_definition_stg</a>, <a href="#common_kernel-kmi_enforced">kmi_enforced</a>, <a href="#common_kernel-build_gki_artifacts">build_gki_artifacts</a>, <a href="#common_kernel-gki_boot_img_sizes">gki_boot_img_sizes</a>, <a href="#common_kernel-page_size">page_size</a>,
              <a href="#common_kernel-deprecation">deprecation</a>, <a href="#common_kernel-ddk_headers_archive">ddk_headers_archive</a>, <a href="#common_kernel-ddk_module_headers">ddk_module_headers</a>, <a href="#common_kernel-extra_dist">extra_dist</a>)
</pre>

Macro for an Android Common Kernel.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="common_kernel-name"></a>name |  name of the kernel_build().   |  none |
| <a id="common_kernel-outs"></a>outs |  See [kernel_build.outs](kernel.md#kernel_build-outs)   |  none |
| <a id="common_kernel-build_config"></a>build_config |  See [kernel_build.build_config](kernel.md#kernel_build-build_config)   |  none |
| <a id="common_kernel-arch"></a>arch |  See [kernel_build.arch](kernel.md#kernel_build-arch)   |  `None` |
| <a id="common_kernel-visibility"></a>visibility |  default visibility for some targets instantiated with this macro   |  `None` |
| <a id="common_kernel-toolchain_version"></a>toolchain_version |  See [kernel_build.toolchain_version](kernel.md#kernel_build-toolchain_version)   |  `None` |
| <a id="common_kernel-defconfig_fragments"></a>defconfig_fragments |  See [kernel_build.defconfig_fragments](kernel.md#kernel_build-defconfig_fragments)   |  `None` |
| <a id="common_kernel-enable_interceptor"></a>enable_interceptor |  See [kernel_build.enable_interceptor](kernel.md#kernel_build-enable_interceptor)   |  `None` |
| <a id="common_kernel-kmi_symbol_list"></a>kmi_symbol_list |  See [kernel_build.kmi_symbol_list](kernel.md#kernel_build-kmi_symbol_list)   |  `None` |
| <a id="common_kernel-additional_kmi_symbol_lists"></a>additional_kmi_symbol_lists |  See [kernel_build.additional_kmi_symbol_lists](kernel.md#kernel_build-additional_kmi_symbol_lists)   |  `None` |
| <a id="common_kernel-trim_nonlisted_kmi"></a>trim_nonlisted_kmi |  See [kernel_build.trim_nonlisted_kmi](kernel.md#kernel_build-trim_nonlisted_kmi)   |  `None` |
| <a id="common_kernel-kmi_symbol_list_strict_mode"></a>kmi_symbol_list_strict_mode |  See [kernel_build.kmi_symbol_list_strict_mode](kernel.md#kernel_build-kmi_symbol_list_strict_mode)   |  `None` |
| <a id="common_kernel-kmi_symbol_list_add_only"></a>kmi_symbol_list_add_only |  See [kernel_abi.kmi_symbol_list_add_only](kernel.md#kernel_abi-kmi_symbol_list_add_only)   |  `None` |
| <a id="common_kernel-module_implicit_outs"></a>module_implicit_outs |  See [kernel_build.module_implicit_outs](kernel.md#kernel_build-module_implicit_outs)   |  `None` |
| <a id="common_kernel-protected_exports_list"></a>protected_exports_list |  See [kernel_build.protected_exports_list](kernel.md#kernel_build-protected_exports_list)   |  `None` |
| <a id="common_kernel-protected_modules_list"></a>protected_modules_list |  See [kernel_build.protected_modules_list](kernel.md#kernel_build-protected_modules_list)   |  `None` |
| <a id="common_kernel-gki_system_dlkm_modules"></a>gki_system_dlkm_modules |  system_dlkm module_list   |  `None` |
| <a id="common_kernel-make_goals"></a>make_goals |  See [kernel_build.make_goals](kernel.md#kernel_build-make_goals)   |  `None` |
| <a id="common_kernel-abi_definition_stg"></a>abi_definition_stg |  See [kernel_abi.abi_definition_stg](kernel.md#kernel_abi-abi_definition_stg)   |  `None` |
| <a id="common_kernel-kmi_enforced"></a>kmi_enforced |  See [kernel_abi.kmi_enforced](kernel.md#kernel_abi-kmi_enforced)   |  `None` |
| <a id="common_kernel-build_gki_artifacts"></a>build_gki_artifacts |  nonconfigurable. If true, build GKI artifacts under target name `<name>_gki_artifacts`.   |  `None` |
| <a id="common_kernel-gki_boot_img_sizes"></a>gki_boot_img_sizes |  gki_artifacts.boot_img_sizes   |  `None` |
| <a id="common_kernel-page_size"></a>page_size |  See [kernel_build.page_size](kernel.md#kernel_build-page_size)   |  `None` |
| <a id="common_kernel-deprecation"></a>deprecation |  If set, mark target deprecated with given message.   |  `None` |
| <a id="common_kernel-ddk_headers_archive"></a>ddk_headers_archive |  nonconfigurable. Target to the archive packing DDK headers   |  `None` |
| <a id="common_kernel-ddk_module_headers"></a>ddk_module_headers |  See [kernel_build.ddk_module_headers](kernel.md#kernel_build-ddk_module_headers)   |  `None` |
| <a id="common_kernel-extra_dist"></a>extra_dist |  extra targets added to `<name>_dist`   |  `None` |


<a id="define_db845c"></a>

## define_db845c

<pre>
define_db845c(<a href="#define_db845c-name">name</a>, <a href="#define_db845c-outs">outs</a>, <a href="#define_db845c-build_config">build_config</a>, <a href="#define_db845c-module_outs">module_outs</a>, <a href="#define_db845c-make_goals">make_goals</a>, <a href="#define_db845c-define_abi_targets">define_abi_targets</a>,
              <a href="#define_db845c-kmi_symbol_list">kmi_symbol_list</a>, <a href="#define_db845c-kmi_symbol_list_add_only">kmi_symbol_list_add_only</a>, <a href="#define_db845c-module_grouping">module_grouping</a>, <a href="#define_db845c-unstripped_modules_archive">unstripped_modules_archive</a>,
              <a href="#define_db845c-gki_modules_list">gki_modules_list</a>, <a href="#define_db845c-dist_dir">dist_dir</a>)
</pre>

Define target for db845c.

Note: This is a mixed build.

Requires [`define_common_kernels`](#define_common_kernels) to be called in the same package.

**Deprecated**. Use [`kernel_build`](kernel.md#kernel_build) directly.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="define_db845c-name"></a>name |  name of target. Usually `"db845c"`.   |  none |
| <a id="define_db845c-outs"></a>outs |  See [kernel_build.outs](kernel.md#kernel_build-outs).   |  none |
| <a id="define_db845c-build_config"></a>build_config |  See [kernel_build.build_config](kernel.md#kernel_build-build_config). If `None`, default to `"build.config.db845c"`.   |  `None` |
| <a id="define_db845c-module_outs"></a>module_outs |  See [kernel_build.module_outs](kernel.md#kernel_build-module_outs). The list of in-tree kernel modules.   |  `None` |
| <a id="define_db845c-make_goals"></a>make_goals |  See [kernel_build.make_goals](kernel.md#kernel_build-make_goals).  A list of strings defining targets for the kernel build.   |  `None` |
| <a id="define_db845c-define_abi_targets"></a>define_abi_targets |  See [kernel_abi.define_abi_targets](kernel.md#kernel_abi-define_abi_targets).   |  `None` |
| <a id="define_db845c-kmi_symbol_list"></a>kmi_symbol_list |  See [kernel_build.kmi_symbol_list](kernel.md#kernel_build-kmi_symbol_list).   |  `None` |
| <a id="define_db845c-kmi_symbol_list_add_only"></a>kmi_symbol_list_add_only |  See [kernel_abi.kmi_symbol_list_add_only](kernel.md#kernel_abi-kmi_symbol_list_add_only).   |  `None` |
| <a id="define_db845c-module_grouping"></a>module_grouping |  See [kernel_abi.module_grouping](kernel.md#kernel_abi-module_grouping).   |  `None` |
| <a id="define_db845c-unstripped_modules_archive"></a>unstripped_modules_archive |  See [kernel_abi.unstripped_modules_archive](kernel.md#kernel_abi-unstripped_modules_archive).   |  `None` |
| <a id="define_db845c-gki_modules_list"></a>gki_modules_list |  List of gki modules to be copied to the dist directory. If `None`, all gki kernel modules will be copied.   |  `None` |
| <a id="define_db845c-dist_dir"></a>dist_dir |  Argument to `copy_to_dist_dir`. If `None`, default is `"out/{name}/dist"`.   |  `None` |

**DEPRECATED**

Use [`kernel_build`](kernel.md#kernel_build) directly.


<a id="define_prebuilts"></a>

## define_prebuilts

<pre>
define_prebuilts(<a href="#define_prebuilts-kwargs">kwargs</a>)
</pre>

Define --use_prebuilt_gki and relevant targets.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="define_prebuilts-kwargs"></a>kwargs |  common kwargs to internal targets.   |  none |

**DEPRECATED**

See build/kernel/kleaf/docs/ddk/workspace.md for new ways to define prebuilts.


