#!/usr/bin/env python3
#
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

"""Configures the project layout to build DDK modules."""

import argparse
import concurrent.futures
import dataclasses
import json
import logging
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse

_TOOLS_BAZEL = "tools/bazel"
_DEVICE_BAZELRC = "device.bazelrc"
_FILE_MARKER_BEGIN = "### GENERATED SECTION - DO NOT MODIFY - BEGIN ###\n"
_FILE_MARKER_END = "### GENERATED SECTION - DO NOT MODIFY - END ###\n"
_MODULE_BAZEL_FILE = "MODULE.bazel"

_KLEAF_DEPENDENCY_TEMPLATE = """\
\"""Kleaf: Build Android kernels with Bazel.\"""
bazel_dep(name = "kleaf")
local_path_override(
    module_name = "kleaf",
    path = "{kleaf_repo_relative}",
)
"""

_LOCAL_PREBUILTS_CONTENT_TEMPLATE = """\
kernel_prebuilt_ext = use_extension(
    "@kleaf//build/kernel/kleaf:kernel_prebuilt_ext.bzl",
    "kernel_prebuilt_ext",
)
kernel_prebuilt_ext.declare_kernel_prebuilts(
    name = "gki_prebuilts",
    local_artifact_path = "{prebuilts_dir_relative}",
)
use_repo(kernel_prebuilt_ext, "gki_prebuilts")
"""


class KleafProjectSetterError(RuntimeError):
    pass


@dataclasses.dataclass(kw_only=True)
class KleafProjectSetter:
    """Configures the project layout to build DDK modules."""

    build_id: str | None
    build_target: str | None
    ddk_workspace: pathlib.Path | None
    local: bool
    kleaf_repo: pathlib.Path | None
    prebuilts_dir: pathlib.Path | None
    url_fmt: str | None

    def _symlink_tools_bazel(self):
        """Creates the symlink tools/bazel."""
        if not self.ddk_workspace or not self.kleaf_repo:
            return
        # Calculate the paths.
        tools_bazel = self.ddk_workspace / _TOOLS_BAZEL
        kleaf_tools_bazel = self.kleaf_repo / _TOOLS_BAZEL
        # Prepare the location and clean up if necessary.
        tools_bazel.parent.mkdir(parents=True, exist_ok=True)
        tools_bazel.unlink(missing_ok=True)
        tools_bazel.symlink_to(kleaf_tools_bazel)

    @staticmethod
    def _update_file(path: pathlib.Path, update: str):
        """Updates the content of a section between markers in a file."""
        add_content: bool = False
        skip_line: bool = False
        update_written: bool = False
        if path.exists():
            open_mode = "r"
            logging.info("Updating file %s.", path)
        else:
            open_mode = "a+"
            logging.info("Creating file %s.", path)
        with (
            open(path, open_mode, encoding="utf-8") as input_file,
            tempfile.NamedTemporaryFile(mode="w", delete=False) as output_file,
        ):
            for line in input_file:
                if add_content:
                    output_file.write(_FILE_MARKER_BEGIN)
                    output_file.write(update + "\n")
                    update_written = True
                    add_content = False
                if _FILE_MARKER_END in line:
                    skip_line = False
                if _FILE_MARKER_BEGIN in line:
                    skip_line = True
                    add_content = True
                if not skip_line:
                    output_file.write(line)
            if not update_written:
                output_file.write(_FILE_MARKER_BEGIN)
                output_file.write(update + "\n")
                output_file.write(_FILE_MARKER_END)
        shutil.move(output_file.name, path)

    def _try_rel_workspace(self, path: pathlib.Path):
        """Tries to convert |path| to be relative to ddk_workspace."""
        if not self.ddk_workspace:
            raise KleafProjectSetterError(
                "ERROR: _try_rel_workspace called without --ddk_workspace set!"
            )
        try:
            return path.relative_to(self.ddk_workspace)
        except ValueError:
            logging.warning(
                "Path %s is not relative to DDK workspace %s, using absolute"
                " path.",
                path,
                self.ddk_workspace,
            )
            return path

    def _get_local_path_overrides(self):
        """Naive algorithm to extract local_path_override()'s from local @kleaf."""
        path_attr_prefix = 'path = "'
        section = []
        overrides = []
        module_bazel = self.kleaf_repo / _MODULE_BAZEL_FILE
        # Modify path so it is relative to the current DDK workspace.
        kleaf_repo = self._try_rel_workspace(self.kleaf_repo)
        with open(module_bazel, "r", encoding="utf-8") as src:
            for line in src:
                if line.startswith("local_path_override("):
                    section.append(line)
                    continue
                if not section:
                    continue
                elif line.lstrip().startswith(path_attr_prefix):
                    line = line.strip().removeprefix(path_attr_prefix)
                    line = line.removesuffix('",')
                    line = f'    path = "{kleaf_repo / line}",\n'
                section.append(line)
                if line.strip() == ")":
                    overrides.append("".join(section))
                    section.clear()
        return "".join(overrides)

    def _generate_module_bazel(self):
        """Configures the dependencies for the DDK workspace."""
        if not self.ddk_workspace:
            return
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        module_bazel_content = ""
        if self.kleaf_repo:
            module_bazel_content += _KLEAF_DEPENDENCY_TEMPLATE.format(
                kleaf_repo_relative=self._try_rel_workspace(self.kleaf_repo),
            )
            module_bazel_content += self._get_local_path_overrides()

            # https://github.com/bazelbuild/bazel/issues/22579
            # @@rules_cc is implicitly added in a fallback
            # WORKSPACE file if the file doesn't exist.
            # Work around the issue by adding an empty file.
            if (not (self.ddk_workspace / "WORKSPACE").is_file() and
                not (self.ddk_workspace / "WORKSPACE.bazel").is_file() and
                not (self.ddk_workspace / "WORKSPACE.bzlmod").is_file()):
                (self.ddk_workspace / "WORKSPACE.bzlmod").touch()

        if self.prebuilts_dir:
            module_bazel_content += "\n"
            module_bazel_content += _LOCAL_PREBUILTS_CONTENT_TEMPLATE.format(
                # The prebuilts directory must be relative to the DDK workspace.
                prebuilts_dir_relative=self._try_rel_workspace(
                    self.prebuilts_dir
                ),
            )
        if not module_bazel_content:
            logging.info("Nothing to update in %s", module_bazel)
        self._update_file(module_bazel, module_bazel_content)

    def _generate_bazelrc(self):
        """Creates a Bazel configuration file with the minimum setup required."""
        if not self.ddk_workspace or not self.kleaf_repo:
            return
        bazelrc = self.ddk_workspace / _DEVICE_BAZELRC

        kleaf_repo = self._try_rel_workspace(self.kleaf_repo)
        if not kleaf_repo.is_absolute():
            kleaf_repo = pathlib.Path("%workspace%") / kleaf_repo

        bazelrc_content = []
        bazelrc_content.append((
            "common"
            f" --registry=file://{kleaf_repo}/external/bazelbuild-bazel-central-registry"
        ))
        # Explicitly disable internet usage.
        bazelrc_content.append("common --config=no_internet")

        self._update_file(
            bazelrc,
            "\n".join(bazelrc_content),
        )

    def _get_url(self, remote_filename: str) -> str | None:
        """Returns a valid url when it can be formed with target and id."""
        if not self.url_fmt:
            raise KleafProjectSetterError(
                "ERROR: _get_url called without url_fmt set!"
            )
        url = self.url_fmt.format(
            build_id=self.build_id,
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        url_with_fake_id = self.url_fmt.format(
            build_id="__FAKE_BUILD_NUMBER_PLACEHOLDER__",
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        if not self.build_id and url != url_with_fake_id:
            return None
        return url

    def _can_download_artifacts(self):
        """Validates that download are possible within the current context."""
        if not self.url_fmt:
            return False
        # Check if build_id is missing and url_fmt has an anchor depending on it.
        if self._get_url("") is None:
            return False
        return True

    def _download(
        self,
        remote_filename: str,
        out_file_name: pathlib.Path,
        mandatory: bool = True,
    ) -> None:
        """Given the url_fmt, build_id and build_target downloads a remote file.

        Args:
            remote_filename: File name for the file, it can contain anchors for,
              build_id, target and filename.
            out_file_name: Destination place for the download.
            mandatory: When set to true, the download fails when the file could
              not be downloaded.
        """
        url = self._get_url(remote_filename)
        if not url:
            raise KleafProjectSetterError(
                f"ERROR: Unable to download {remote_filename}: can't infer URL"
            )
        # Workaround: Rely on host keychain to download files.
        # This is needed otheriwese downloads fail when running this script
        #   using the hermetic Python toolchain.
        subprocess.run(
            [
                "python3",
                pathlib.Path(__file__).parent / "init_download.py",
                url,
                out_file_name,
            ],
            stderr=subprocess.STDOUT if mandatory else subprocess.DEVNULL,
            check=mandatory,
        )

    def _load_meta_files(self):
        """Loads meta files, possibly downloading them."""
        if self.prebuilts_dir:
            if self._can_download_artifacts():
                self._download_download_configs(self.prebuilts_dir)
            # Otherwise meta files are already in prebuilts_dir.
            self._load_download_configs(self.prebuilts_dir)
        elif self._can_download_artifacts():
            with tempfile.TemporaryDirectory() as meta_files_dir:
                self._download_download_configs(pathlib.Path(meta_files_dir))
                self._load_download_configs(pathlib.Path(meta_files_dir))

    def _download_download_configs(self, meta_files_dir: pathlib.Path):
        """Downloads download_configs.json"""
        if not self._can_download_artifacts():
            raise KleafProjectSetterError(
                "ERROR: _download_meta_files_to called without --url_fmt set!"
            )
        meta_files_dir.mkdir(parents=True, exist_ok=True)

        download_configs = meta_files_dir / "download_configs.json"
        with open(download_configs, "w+", encoding="utf-8") as f:
            self._download("download_configs.json", pathlib.Path(f.name))

    def _load_download_configs(self, meta_files_dir: pathlib.Path):
        """Loads download_configs.json"""
        download_configs = meta_files_dir / "download_configs.json"
        with open(download_configs, "r") as f:
            self._download_list = json.load(f)

    def _download_prebuilts(self) -> None:
        """Downloads prebuilts from a given build_id when provided."""
        if not self.prebuilts_dir:
            raise KleafProjectSetterError(
                "ERROR: _download_prebuilts called without --prebuilts_dir!"
            )
        logging.info("Downloading prebuilts into %s", self.prebuilts_dir)
        with concurrent.futures.ThreadPoolExecutor() as executor:
            futures = []
            for local_filename, config in self._download_list.items():
                remote_filename = config["remote_filename_fmt"].format(
                    build_number = self.build_id,
                )
                dst = self.prebuilts_dir / local_filename
                dst.parent.mkdir(parents=True, exist_ok=True)
                futures.append(
                    executor.submit(self._download, remote_filename, dst,
                                    config["mandatory"])
                )
            for complete_ret in concurrent.futures.as_completed(futures):
                complete_ret.result()  # Raise exception if any

    def _handle_ddk_workspace(self) -> None:
        if not self.ddk_workspace:
            return
        self.ddk_workspace.mkdir(parents=True, exist_ok=True)

    def _handle_kleaf_repo(self) -> None:
        if not self.kleaf_repo:
            return
        self.kleaf_repo.mkdir(parents=True, exist_ok=True)
        # TODO: b/328770706 - According to the needs, syncing git repos logic should go here.

        self._populate_kleaf_repo_extra_files()

    def _handle_prebuilts(self) -> None:
        if not self.prebuilts_dir:
            return
        self.prebuilts_dir.mkdir(parents=True, exist_ok=True)
        if self._can_download_artifacts():
            self._download_prebuilts()

    def _populate_kleaf_repo_extra_files(self) -> None:
        """Populates kleaf_repo by adding extra files"""
        if self.local:
            logging.info("Skipped populating kleaf_repo with --local.")
            # --local assumes the kernel source tree is complete.
            return
        if not self.kleaf_repo:
            logging.info(
                "Skipped populating --kleaf_repo because it is unspecified"
            )
            return
        if not self.prebuilts_dir:
            logging.info(
                "No prebuilts specified, skip populating %s", self.kleaf_repo
            )
            return
        self._extract_headers_archive(self.prebuilts_dir, self.kleaf_repo)

        build_config_constants = self.prebuilts_dir / "build.config.constants"
        if not build_config_constants.is_file():
            logging.warning(
                "%s is not a file, skip copying", build_config_constants
            )
            return
        shutil.copy(
            build_config_constants,
            self.kleaf_repo / "common/build.config.constants",
        )
        if not (self.kleaf_repo / "common/BUILD.bazel").is_file():
            (self.kleaf_repo / "common/BUILD.bazel").write_text("")

    @staticmethod
    def _extract_headers_archive(
        prebuilts_dir: pathlib.Path, kleaf_repo: pathlib.Path
    ):
        """Extracts DDK headers archive from prebuilts_dir into kleaf_repo"""
        # TODO: This should be target-specific. The name of the output is
        # currently (2024-05-16) defined by common/BUILD.bazel, but it may
        # change in the future.
        header_archives = list(
            prebuilts_dir.glob("*_ddk_headers_archive.tar.gz")
        )
        if not header_archives:
            logging.warning(
                "No _ddk_headers_archive.tar.gz found in %s, "
                "skipping header extraction.",
                prebuilts_dir,
            )
            return
        if len(header_archives) > 1:
            raise KleafProjectSetterError(
                "Multiple _ddk_headers_archive.tar.gz found in "
                f"{prebuilts_dir}: {header_archives}"
            )
        logging.info(
            "Extracting header archive %s to %s", header_archives[0], kleaf_repo
        )
        with tarfile.open(header_archives[0]) as tar:
            tar.extractall(kleaf_repo)

    def _run(self) -> None:
        self._symlink_tools_bazel()
        self._generate_module_bazel()
        self._generate_bazelrc()

    def run(self) -> None:
        self._handle_ddk_workspace()
        self._load_meta_files()
        self._handle_prebuilts()
        self._handle_kleaf_repo()
        self._run()


if __name__ == "__main__":

    def abs_path(path_string: str) -> pathlib.Path | None:
        path = pathlib.Path(path_string)
        if not path.is_absolute():
            raise ValueError(f"{path} is not an absolute path.")
        return path

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--build_id",
        type=str,
        help="the build id to download the build for, e.g. 6148204",
        default=None,
    )
    parser.add_argument(
        "--build_target",
        type=str,
        help='the build target to download, e.g. "kernel_aarch64"',
        default="kernel_aarch64",
    )
    parser.add_argument(
        "--ddk_workspace",
        help="Absolute path to DDK workspace root.",
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--local",
        help="Whether to use a local source tree containing Kleaf.",
        action="store_true",
    )
    parser.add_argument(
        "--kleaf_repo",
        help="Absolute path to Kleaf's repo dir.",
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--prebuilts_dir",
        help=(
            "Absolute path to local GKI prebuilts. Usually, it is located"
            " within workspace."
        ),
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--url_fmt",
        help="URL format endpoint for CI downloads.",
        default=None,
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")
    # Validate pre-condition.
    if args.local and not args.kleaf_repo:
        parser.error("--local requires --kleaf_repo.")
    try:
        KleafProjectSetter(**vars(args)).run()
    except KleafProjectSetterError as e:
        logging.error(e, exc_info=e)
        sys.exit(1)
