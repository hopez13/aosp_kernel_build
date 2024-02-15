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

"""Extension that helps declaring kernel prebuilts."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "//build/kernel/kleaf/impl:kernel_prebuilt_utils.bzl",
    "CI_TARGET_MAPPING",
    "GKI_DOWNLOAD_CONFIGS",
)

visibility("public")

_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{filename}/url?redirect=true"

def _bool_to_str(b):
    """Turns boolean to string."""

    # We can't use str() because bool(str(False)) != False
    return "True" if b else ""

def _str_to_bool(s):
    """Turns string to boolean."""

    # We can't use bool() because bool(str(False)) != False
    if s == "True":
        return True
    if not s:
        return False
    fail("Invalid value {}".format(s))

def _new_kernel_prebuilt_repo_impl(repository_ctx):
    download_config = repository_ctx.attr.download_config
    mandatory = repository_ctx.attr.mandatory
    if repository_ctx.attr.auto_download_config:
        if download_config:
            fail("{}: download_config should not be set when auto_download_config is True".format(repository_ctx.attr.name))
        if mandatory:
            fail("{}: mandatory should not be set when auto_download_config is True".format(repository_ctx.attr.name))
        download_config, mandatory = _infer_download_config(repository_ctx.attr.target)

    futures = []

    for local_filename, remote_filename_fmt in download_config.items():
        remote_filename = remote_filename_fmt.format(
            build_number = repository_ctx.attr.build_number,
            target = repository_ctx.attr.target,
        )
        file_mandatory = _str_to_bool(mandatory.get(local_filename, _bool_to_str(True)))
        artifact_url = repository_ctx.attr.artifact_url_fmt.format(
            build_number = repository_ctx.attr.build_number,
            target = repository_ctx.attr.target,
            filename = remote_filename,
        )
        local_path = repository_ctx.path(paths.join(local_filename, paths.basename(local_filename)))
        future = repository_ctx.download(
            url = artifact_url,
            output = local_path,
            allow_fail = not file_mandatory,
            # TODO(b/325494748): With bazel 7.1.0, use parallel download
            # block = False, # TODO bazel 7.1.0
        )
        futures.append(future)

        repository_ctx.file(paths.join(local_filename, "BUILD.bazel"), """\
exports_files(
    [{}],
    visibility = ["//visibility:public"],
)""".format(repr(paths.basename(local_filename))))

    # TODO(b/325494748): With bazel 7.1.0, use parallel download
    # for future in futures:
    #     future.wait()

    repository_ctx.file("""WORKSPACE.bazel""", """\
workspace({})
""".format(repr(repository_ctx.attr.name)))

_new_kernel_prebuilt_repo = repository_rule(
    implementation = _new_kernel_prebuilt_repo_impl,
    attrs = {
        "artifact_url_fmt": attr.string(),
        "build_number": attr.string(),
        "auto_download_config": attr.bool(),
        "download_config": attr.string_dict(),
        "mandatory": attr.string_dict(),
        "target": attr.string(),
    },
)

def _infer_download_config(target):
    chosen_mapping = None
    for mapping in CI_TARGET_MAPPING.values():
        if mapping["target"] == target:
            chosen_mapping = mapping
    if not chosen_mapping:
        fail("auto_download_config with {} is not supported yet.".format(target))

    download_config = {}
    mandatory = {}

    for out in chosen_mapping["outs"]:
        download_config[out] = out
        mandatory[out] = True

    protected_modules = chosen_mapping["protected_modules"]
    download_config[protected_modules] = protected_modules
    mandatory[protected_modules] = False

    for config in GKI_DOWNLOAD_CONFIGS:
        config_mandatory = config.get("mandatory", True)
        for out in config.get("outs", []):
            download_config[out] = out
            mandatory[out] = config_mandatory
        for out, remote_filename_fmt in config.get("outs_mapping", {}).items():
            download_config[out] = remote_filename_fmt
            mandatory[out] = config_mandatory

    mandatory = {key: _bool_to_str(value) for key, value in mandatory.items()}

    return download_config, mandatory

def _kernel_prebuilt_ext_impl(module_ctx):
    for module in module_ctx.modules:
        for declared in module.tags.declare:
            _new_kernel_prebuilt_repo(
                name = declared.name,
                artifact_url_fmt = declared.artifact_url_fmt,
                build_number = declared.build_number,
                auto_download_config = declared.auto_download_config,
                download_config = declared.download_config,
                mandatory = declared.mandatory,
                target = declared.target,
            )

kernel_prebuilt_ext = module_extension(
    doc = "Extension that helps declaring kernel prebuilts",
    implementation = _kernel_prebuilt_ext_impl,
    tag_classes = {
        "declare": tag_class(
            doc = "Declares a repo that contains kernel prebuilts",
            attrs = {
                "name": attr.string(
                    doc = "name of repository",
                    mandatory = True,
                ),
                "artifact_url_fmt": attr.string(
                    doc = """API endpoint for Android CI artifacts.

                        The format may include anchors for the following properties:
                            * {build_number}
                            * {target}
                            * {filename}

                        Its default value is the API endpoint for http://ci.android.com.""",
                    default = _ARTIFACT_URL_FMT,
                ),
                "build_number": attr.string(
                    doc = """build number to be used in `artifact_url_fmt`.

                        Unlike `kernel_prebuilt_repo`, the environment variable
                        `KLEAF_DOWNLOAD_BUILD_NUMBER_MAP` is **NOT** respected.
                    """,
                ),
                "auto_download_config": attr.bool(
                    doc = """If `True`, infer `download_config` and `mandatory`
                        from `target`.""",
                ),
                "download_config": attr.string_dict(
                    doc = """Configure the list of files to download.

                        Key: local file name.

                        Value: remote file name format string, with the following anchors:
                            * {build_number}
                            * {target}
                    """,
                ),
                "mandatory": attr.string_dict(
                    doc = """Configure whether files are mandatory.

                        Key: local file name.

                        Value: Whether the file is mandatory.

                        If a file name is not found in the dictionary, default
                        value is `True`. If mandatory, failure to download the
                        file results in a build failure.
                    """,
                ),
                "target": attr.string(
                    doc = """Name of the build target as identified by the remote build server.

                        This attribute has two effects:

                        * Replaces the `{target}` anchor in `artifact_url_fmt`.
                          If `artifact_url_fmt` does not have the `{target}` anchor,
                          this has no effect.

                        * If `auto_download_config` is `True`, `download_config`
                          and `mandatory` is inferred from a
                          list of known configs keyed on `target`.
                    """,
                    default = "kernel_aarch64",
                ),
            },
        ),
    },
)
