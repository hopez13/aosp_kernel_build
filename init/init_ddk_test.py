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

"""Tests for init_ddk.py"""

import json
import logging
import pathlib
import shutil
import tempfile
import textwrap
from typing import Any
import xml.dom.minidom

from absl.testing import absltest
from absl.testing import parameterized
import init_ddk

# pylint: disable=protected-access


def join(*args: Any) -> str:
    return "\n".join([*args])


_HELLO_WORLD = "Hello World!"


class KleafProjectSetterTest(parameterized.TestCase):

    @parameterized.named_parameters([
        (
            "Empty",
            "",
            join(
                init_ddk._FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                init_ddk._FILE_MARKER_END,
            ),
        ),
        (
            "BeforeNoMarkers",
            "Existing test\n",
            join(
                "Existing test",
                init_ddk._FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                init_ddk._FILE_MARKER_END,
            ),
        ),
        (
            "AfterMarkers",
            join(
                init_ddk._FILE_MARKER_BEGIN,
                init_ddk._FILE_MARKER_END,
                "Existing test after.",
            ),
            join(
                init_ddk._FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                init_ddk._FILE_MARKER_END,
                "Existing test after.",
            ),
        ),
    ])
    def test_update_file_existing(self, current_content, wanted_content):
        """Tests only text within markers are updated."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            with open(tmp_file, "w+", encoding="utf-8") as tf:
                tf.write(current_content)
            init_ddk.KleafProjectSetter._update_file(
                tmp_file, "\n" + _HELLO_WORLD
            )
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(wanted_content, got.read())

    def test_update_file_no_existing(self):
        """Tests files are created when they don't exist."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            init_ddk.KleafProjectSetter._update_file(
                tmp_file, "\n" + _HELLO_WORLD
            )
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(
                    join(
                        init_ddk._FILE_MARKER_BEGIN,
                        _HELLO_WORLD,
                        init_ddk._FILE_MARKER_END,
                    ),
                    got.read(),
                )

    def test_relevant_directories_created(self):
        """Tests corresponding directories are created if they don't exist."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_dir = pathlib.Path(temp_dir)
            ddk_workspace = temp_dir / "ddk_workspace"
            kleaf_repo = temp_dir / "kleaf_repo"
            prebuilts_dir = temp_dir / "prebuilts_dir"
            try:
                init_ddk.KleafProjectSetter(
                    build_id=None,
                    build_target=None,
                    ddk_workspace=ddk_workspace,
                    kleaf_repo=kleaf_repo,
                    local=False,
                    prebuilts_dir=prebuilts_dir,
                    url_fmt=None,
                    superproject_tool="repo",
                    sync="false",
                ).run()
            except:  # pylint: disable=bare-except
                pass
            finally:
                self.assertTrue(ddk_workspace.exists())
                self.assertTrue(kleaf_repo.exists())
                self.assertTrue(prebuilts_dir.exists())

    def test_tools_bazel_symlink(self):
        """Tests a symlink to tools/bazel is correctly created."""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_dir = pathlib.Path(temp_dir)
            ddk_workspace = temp_dir / "ddk_workspace"
            try:
                init_ddk.KleafProjectSetter(
                    build_id=None,
                    build_target=None,
                    ddk_workspace=ddk_workspace,
                    kleaf_repo=temp_dir / "kleaf_repo",
                    local=False,
                    prebuilts_dir=None,
                    url_fmt=None,
                    superproject_tool="repo",
                    sync="false",
                ).run()
            except BaseException as e:  # pylint: disable=bare-except
                logging.error(e)
            finally:
                tools_bazel_symlink = ddk_workspace / init_ddk._TOOLS_BAZEL
                self.assertTrue(tools_bazel_symlink.is_symlink())

    def _run_test_module_bazel_for_prebuilts(
        self,
        ddk_workspace: pathlib.Path,
        prebuilts_dir: pathlib.Path,
        expected: str,
    ):
        """Helper method for checking path in a prebuilt extension."""
        download_configs = prebuilts_dir / "download_configs.json"
        download_configs.parent.mkdir(parents=True)
        download_configs.write_text("{}")
        try:
            init_ddk.KleafProjectSetter(
                build_id=None,
                build_target=None,
                ddk_workspace=ddk_workspace,
                kleaf_repo=None,
                local=False,
                prebuilts_dir=prebuilts_dir,
                url_fmt=None,
                superproject_tool="repo",
                sync="false",
            ).run()
        except:  # pylint: disable=bare-except
            pass
        finally:
            module_bazel = ddk_workspace / init_ddk._MODULE_BAZEL_FILE
            self.assertTrue(module_bazel.exists())
            content = module_bazel.read_text()
            self.assertTrue(f'local_artifact_path = "{expected}",' in content)

    def test_module_bazel_for_prebuilts(self):
        """Tests prebuilts setup is correct for relative and non-relative to workspace dirs."""
        with tempfile.TemporaryDirectory() as tmp:
            ddk_workspace = pathlib.Path(tmp) / "ddk_workspace"
            # Verify the right local_artifact_path is set for prebuilts
            #  in a relative to workspace directory.
            prebuilts_dir_rel = ddk_workspace / "prebuilts_dir"
            self._run_test_module_bazel_for_prebuilts(
                ddk_workspace=ddk_workspace,
                prebuilts_dir=prebuilts_dir_rel,
                expected="prebuilts_dir",
            )

            # Verify the right local_artifact_path is set for prebuilts
            #  in a non-relative to workspace directory.
            prebuilts_dir_abs = pathlib.Path(tmp) / "prebuilts_dir"
            self._run_test_module_bazel_for_prebuilts(
                ddk_workspace=ddk_workspace,
                prebuilts_dir=prebuilts_dir_abs,
                expected=str(prebuilts_dir_abs),
            )

    def test_download_works_for_local_file(self):
        """Tests that local files can be downloaded."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_dir = pathlib.Path(tmp_dir)
            remote_file = tmp_dir / "remote_file"
            remote_file.write_text("Hello World!")
            out_file = tmp_dir / "out_file"
            url_fmt = f"file://{tmp_dir}/{{filename}}"
            init_ddk.KleafProjectSetter(
                build_id=None,
                build_target=None,
                ddk_workspace=None,
                kleaf_repo=None,
                local=False,
                prebuilts_dir=None,
                url_fmt=url_fmt,
                superproject_tool="repo",
                sync="false",
            )._download(
                remote_filename="remote_file",
                out_file_name=out_file,
            )
            self.assertTrue(out_file.exists())
            self.assertEqual(out_file.read_text(), "Hello World!")

    def test_non_mandatory_doesnt_fail(self):
        """Tests that optional files don't produce errors."""
        with tempfile.TemporaryDirectory() as tmp:
            ddk_workspace = pathlib.Path(tmp) / "ddk_workspace"
            prebuilts_dir = ddk_workspace / "prebuilts_dir"
            download_configs = ddk_workspace / "download_configs.json"
            download_configs.parent.mkdir(parents=True, exist_ok=True)
            download_configs.write_text(
                json.dumps({
                    "non-existent-file": {
                        "target_suffix": "non-existent-file",
                        "mandatory": False,
                        "remote_filename_fmt": "non-existent-file",
                    }
                })
            )
            with open(download_configs, "r", encoding="utf-8"):
                url_fmt = f"file://{str(download_configs.parent)}/{{filename}}"
                init_ddk.KleafProjectSetter(
                    build_id="12345",
                    build_target=None,
                    ddk_workspace=ddk_workspace,
                    kleaf_repo=None,
                    local=False,
                    prebuilts_dir=prebuilts_dir,
                    url_fmt=url_fmt,
                    superproject_tool="repo",
                    sync="false",
                ).run()

    @parameterized.named_parameters(
        # (Name, MODULE.bazel in @kleaf, expectation)
        ("Empty", "", ""),
        (
            "Dependencies",
            """
local_path_override(
    module_name = "abseil-py",
    path = "external/python/absl-py",
)
local_path_override(
    module_name = "apple_support",
    path = "external/bazelbuild-apple_support",
)
        """,
            """local_path_override(
    module_name = "abseil-py",
    path = "kleaf_repo/external/python/absl-py",
)
local_path_override(
    module_name = "apple_support",
    path = "kleaf_repo/external/bazelbuild-apple_support",
)\n""",
        ),
    )
    def test_local_path_overrides_extraction(
        self, current_content, wanted_content
    ):
        """Tests extraction of local path overrides works correctly."""
        with tempfile.TemporaryDirectory() as tmp:
            ddk_workspace = pathlib.Path(tmp) / "ddk_workspace"
            kleaf_repo = ddk_workspace / "kleaf_repo"
            kleaf_repo.mkdir(parents=True, exist_ok=True)
            kleaf_repo_module_bazel = kleaf_repo / init_ddk._MODULE_BAZEL_FILE
            kleaf_repo_module_bazel.write_text(current_content)
            got_content = init_ddk.KleafProjectSetter(
                build_id=None,
                build_target=None,
                ddk_workspace=ddk_workspace,
                kleaf_repo=kleaf_repo,
                local=True,
                prebuilts_dir=None,
                url_fmt=None,
                superproject_tool="repo",
                sync="false",
            )._get_local_path_overrides()
            self.assertEqual(got_content, wanted_content)

    def test_update_manifest(self):
        """Tests that the repo manifest is updated correctly."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            ddk_workspace = tmp / "ddk_workspace"

            repo_manifest = ddk_workspace / ".repo/manifests/default.xml"
            repo_manifest.parent.mkdir(parents=True, exist_ok=True)
            repo_manifest.write_text(textwrap.dedent("""\
                <?xml version="1.0" encoding="UTF-8"?>
                <manifest />
            """))

            remote_prebuilts_dir = tmp / "remote_prebuilts_dir"
            remote_prebuilts_dir.mkdir(parents=True, exist_ok=True)
            download_configs = remote_prebuilts_dir / "download_configs.json"
            download_configs.write_text(json.dumps({
                "manifest.xml": {
                    "target_suffix": "init_ddk_files",
                    "mandatory": False,
                    "remote_filename_fmt": "manifest_{build_number}.xml",
                },
            }))

            build_id = "12345"
            downloaded_manifest = (remote_prebuilts_dir /
                                   f"manifest_{build_id}.xml")
            source = (pathlib.Path(__file__).parent /
                      "test_data/sample_manifest.xml")
            shutil.copy(source, downloaded_manifest)

            init_ddk.KleafProjectSetter(
                build_id=build_id,
                build_target=None,
                ddk_workspace=ddk_workspace,
                kleaf_repo=ddk_workspace / "external/kleaf",
                local=False,
                prebuilts_dir=ddk_workspace / "prebuilts_dir",
                url_fmt=f"file://{str(remote_prebuilts_dir)}/{{filename}}",
                superproject_tool="repo",
                sync="false",
            ).run()

            with xml.dom.minidom.parse(
                str(ddk_workspace / ".repo/manifests/kleaf.xml")) as dom:

                root: xml.dom.minidom.Element = dom.documentElement
                self.assertFalse(root.getElementsByTagName("superproject"))
                self.assertFalse(root.getElementsByTagName("default"))
                self.assertTrue(root.getElementsByTagName("remote"))

                projects = root.getElementsByTagName("project")
                project_paths = [
                    project.getAttribute("path") for project in projects
                ]
                self.assertCountEqual(
                    project_paths, [
                        "external/kleaf/build/kernel",
                        # TODO(b/291918721): should sync to
                        #  external/bazel-skylib directly below repo root
                        "external/kleaf/external/bazel-skylib",
                    ])

            with xml.dom.minidom.parse(
                str(ddk_workspace / ".repo/manifests/default.xml")) as dom:
                root: xml.dom.minidom.Element = dom.documentElement
                includes = root.getElementsByTagName("include")
                include_names = [
                    include.getAttribute("name") for include in includes
                ]
                self.assertListEqual(include_names, ["kleaf.xml"])


# This could be run as: tools/bazel test //build/kernel:init_ddk_test --test_output=all
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG, format="%(levelname)s: %(message)s"
    )
    absltest.main()
