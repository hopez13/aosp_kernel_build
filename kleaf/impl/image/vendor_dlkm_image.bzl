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
"""
Build vendor_dlkm.img for vendor modules.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    ":common_providers.bzl",
    "ImagesInfo",
)
load(
    ":image/image_utils.bzl",
    "SYSTEM_DLKM_MODULES_LOAD_NAME",
    "SYSTEM_DLKM_STAGING_ARCHIVE_NAME",
    "VENDOR_DLKM_STAGING_ARCHIVE_NAME",
    "image_utils",
)
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _vendor_dlkm_image_impl(ctx):
    vendor_dlkm_img = ctx.actions.declare_file("{}/vendor_dlkm.img".format(ctx.label.name))
    vendor_dlkm_modules_load = ctx.actions.declare_file("{}/vendor_dlkm.modules.load".format(ctx.label.name))
    vendor_dlkm_modules_blocklist = ctx.actions.declare_file("{}/vendor_dlkm.modules.blocklist".format(ctx.label.name))
    modules_staging_dir = vendor_dlkm_img.dirname + "/staging"
    vendor_dlkm_staging_dir = modules_staging_dir + "/vendor_dlkm_staging"
    vendor_dlkm_fs_type = ctx.attr.vendor_dlkm_fs_type
    vendor_dlkm_etc_files = " ".join([f.path for f in ctx.files.vendor_dlkm_etc_files])
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    if ctx.attr.dedup_dlkm_modules:
        # buildifier: disable=print
        print("\nWARNING: {}: dedup_dlkm_modules is deprecated as GKI modules are not included in the vendor_dlkm by default.".format(
            ctx.label,
        ))

    vendor_dlkm_staging_archive = None
    if ctx.attr.vendor_dlkm_archive:
        vendor_dlkm_staging_archive = ctx.actions.declare_file("{}/{}".format(ctx.label.name, VENDOR_DLKM_STAGING_ARCHIVE_NAME))

    command = ""
    additional_inputs = []
    if ctx.file.vendor_boot_modules_load:
        command += """
                # Restore vendor_boot.modules.load or vendor_kernel_boot.modules.load
                # to modules.load, where build_utils.sh build_vendor_dlkm uses
                  cat {vendor_boot_modules_load} >> ${{DIST_DIR}}/modules.load
        """.format(
            vendor_boot_modules_load = ctx.file.vendor_boot_modules_load.path,
        )
        additional_inputs.append(ctx.file.vendor_boot_modules_load)

    link_with_gki_modules_step = _link_with_gki_modules(
        ctx,
        gki_modules_staging_dir = system_dlkm_staging_dir if ctx.attr.system_dlkm_image else modules_staging_dir,
    )
    command += link_with_gki_modules_step.cmd
    additional_inputs += link_with_gki_modules_step.inputs

    command += """
            # Use `strip_modules` intead of relying on this.
               unset DO_NOT_STRIP_MODULES
            # Build vendor_dlkm
              mkdir -p {vendor_dlkm_staging_dir}
              (
                MODULES_STAGING_DIR={modules_staging_dir}
                VENDOR_DLKM_ETC_FILES={quoted_vendor_dlkm_etc_files}
                VENDOR_DLKM_FS_TYPE={vendor_dlkm_fs_type}
                VENDOR_DLKM_STAGING_DIR={vendor_dlkm_staging_dir}
                SYSTEM_DLKM_STAGING_DIR={system_dlkm_staging_dir}
                VENDOR_DLKM_GKI_MODULES_LIST={vendor_dlkm_gki_modules_list}
                build_vendor_dlkm {vendor_dlkm_archive}
              )
            # Move output files into place
              mv "${{DIST_DIR}}/vendor_dlkm.img" {vendor_dlkm_img}
              mv "${{DIST_DIR}}/vendor_dlkm.modules.load" {vendor_dlkm_modules_load}
              if [[ -f "${{DIST_DIR}}/vendor_dlkm_staging_archive.tar.gz" ]]; then
                mv "${{DIST_DIR}}/vendor_dlkm_staging_archive.tar.gz" {vendor_dlkm_staging_archive}
              fi
              if [[ -f "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" ]]; then
                mv "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" {vendor_dlkm_modules_blocklist}
              else
                : > {vendor_dlkm_modules_blocklist}
              fi
            # Remove staging directories
              rm -rf {vendor_dlkm_staging_dir}
              if [[ -n "{system_dlkm_staging_dir}" ]]; then
                rm -rf {system_dlkm_staging_dir}
              fi
    """.format(
        modules_staging_dir = modules_staging_dir,
        quoted_vendor_dlkm_etc_files = shell.quote(vendor_dlkm_etc_files),
        vendor_dlkm_fs_type = vendor_dlkm_fs_type,
        vendor_dlkm_staging_dir = vendor_dlkm_staging_dir,
        vendor_dlkm_img = vendor_dlkm_img.path,
        vendor_dlkm_modules_load = vendor_dlkm_modules_load.path,
        vendor_dlkm_modules_blocklist = vendor_dlkm_modules_blocklist.path,
        vendor_dlkm_archive = "1" if ctx.attr.vendor_dlkm_archive else "",
        vendor_dlkm_staging_archive = vendor_dlkm_staging_archive.path if ctx.attr.vendor_dlkm_archive else None,
        system_dlkm_staging_dir = system_dlkm_staging_dir if not ctx.attr.vendor_dlkm_gki_modules_list else "",
        vendor_dlkm_gki_modules_list = ctx.file.vendor_dlkm_gki_modules_list.path if ctx.attr.vendor_dlkm_gki_modules_list else "",
    )

    additional_inputs += ctx.files.vendor_dlkm_etc_files
    outputs = [vendor_dlkm_img, vendor_dlkm_modules_load, vendor_dlkm_modules_blocklist]
    if ctx.attr.vendor_dlkm_archive:
        outputs.append(vendor_dlkm_staging_archive)

    default_info = image_utils.build_modules_image_impl_common(
        ctx = ctx,
        what = "vendor_dlkm",
        outputs = outputs,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        set_ext_modules = True,
        additional_inputs = additional_inputs,
        mnemonic = "VendorDlkmImage",
    )

    images_info = ImagesInfo(files_dict = {
        vendor_dlkm_img.basename: depset([vendor_dlkm_img]),
    })

    return [
        default_info,
        images_info,
    ]

def _link_with_gki_modules(ctx, gki_modules_staging_dir):
    inputs = []

    if ctx.attr.system_dlkm_image:
        if ctx.attr.vendor_dlkm_gki_modules_list:
            fail("{}: With vendor_dlkm_gki_modules_list, build_system_dlkm must not be set".format(ctx.label))
        system_dlkm_files = ctx.files.system_dlkm_image
        src_attr = "system_dlkm_image"
    elif ctx.attr.base_kernel_images:
        system_dlkm_files = ctx.files.base_kernel_images
        src_attr = "base_kernel_images"
    elif ctx.attr.vendor_dlkm_gki_modules_list:
        fail("{}: With vendor_dlkm_gki_modules_list, either build_system_dlkm or base_kernel_images must be set".format(
            ctx.label,
        ))
    else:
        # No GKI modules provided to link against. So exit early.
        return struct(cmd = "", inputs = [])

    system_dlkm_staging_archive = utils.find_file(
        name = SYSTEM_DLKM_STAGING_ARCHIVE_NAME,
        files = system_dlkm_files,
        what = "{} ({} for {})".format(ctx.attr.base_kernel_images.label, src_attr, ctx.label),
        required = True,
    )
    if not ctx.attr.vendor_dlkm_gki_modules_list:
        system_dlkm_modules_load = utils.find_file(
            name = SYSTEM_DLKM_MODULES_LOAD_NAME,
            files = system_dlkm_files,
            what = "{} ({} for {})".format(ctx.attr.base_kernel_images.label, src_attr, ctx.label),
            required = True,
        )
    else:
        system_dlkm_modules_load = ctx.file.vendor_dlkm_gki_modules_list

    inputs += [system_dlkm_staging_archive, system_dlkm_modules_load]

    cmd = """
           # Extract modules from system_dlkm staging archive for depmod
             mkdir -p {gki_modules_staging_dir}
             if [[ -z "{vendor_dlkm_gki_modules_list}" ]]; then
               tar xf {system_dlkm_staging_archive} --wildcards -C {gki_modules_staging_dir} '*.ko'
             else
               for module in $(cat {vendor_dlkm_gki_modules_list}); do
                 tar xf {system_dlkm_staging_archive} --wildcards -C {gki_modules_staging_dir} '*/'${{module}}
               done
             fi
    """.format(
        system_dlkm_staging_archive = system_dlkm_staging_archive.path,
        gki_modules_staging_dir = gki_modules_staging_dir,
        vendor_dlkm_gki_modules_list = ctx.file.vendor_dlkm_gki_modules_list.path if ctx.attr.vendor_dlkm_gki_modules_list else "",
    )

    return struct(cmd = cmd, inputs = inputs)

vendor_dlkm_image = rule(
    implementation = _vendor_dlkm_image_impl,
    doc = """Build vendor_dlkm image.

Execute `build_vendor_dlkm` in `build_utils.sh`.

When included in a `copy_to_dist_dir` rule, this rule copies a `vendor_dlkm.img` to `DIST_DIR`.
""",
    attrs = image_utils.build_modules_image_attrs_common({
        "vendor_boot_modules_load": attr.label(
            allow_single_file = True,
            doc = """File to `vendor_boot.modules.load`.

Modules listed in this file is stripped away from the `vendor_dlkm` image.""",
        ),
        "vendor_dlkm_archive": attr.bool(doc = "Whether to archive the `vendor_dlkm` modules"),
        "vendor_dlkm_fs_type": attr.string(doc = """vendor_dlkm.img fs type""", values = ["ext4", "erofs"]),
        "vendor_dlkm_gki_modules_list": attr.label(allow_single_file = True),
        "vendor_dlkm_modules_list": attr.label(allow_single_file = True),
        "vendor_dlkm_etc_files": attr.label_list(allow_files = True),
        "vendor_dlkm_modules_blocklist": attr.label(allow_single_file = True),
        "vendor_dlkm_props": attr.label(allow_single_file = True),
        "dedup_dlkm_modules": attr.bool(doc = "WARNING: dedup_dlkm_modules is deprecated now that GKI modules are not included in the vendor_dlkm."),
        "system_dlkm_image": attr.label(),
        "base_kernel_images": attr.label(allow_files = True),
    }),
)
