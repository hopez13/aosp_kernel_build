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

"""Tests for check_config."""

from absl.testing import absltest
import pathlib
import tempfile
import unittest

from check_config import CheckConfig, ConfigValue, Mismatch


class CheckConfigTest(unittest.TestCase):
    def setUp(self):
        # pylint: disable=invalid-name
        self.maxDiff = None
        self.tempdir = tempfile.TemporaryDirectory()
        self.tempdir_path = pathlib.Path(self.tempdir.name)
        self.dot_config = self.tempdir_path / ".config"
        self.defconfig = self.tempdir_path / "defconfig"
        self.defconfig2 = self.tempdir_path / "defconfig2"

    def tearDown(self):
        self.tempdir.cleanup()

    def test_parse_dot_config(self):
        self.dot_config.write_text("""\
CONFIG_A=y
CONFIG_B="hello world"
CONFIG_C=m
# CONFIG_D is not set
""")
        self.assertEqual(
            # pylint: disable=protected-access
            CheckConfig._parse_config(self.dot_config, is_dot_config=True),
            {
                "CONFIG_A": ConfigValue("y", self.dot_config),
                "CONFIG_B": ConfigValue("hello world", self.dot_config),
                "CONFIG_C": ConfigValue("m", self.dot_config),
                "CONFIG_D": ConfigValue("", self.dot_config),
            },
        )

    def test_parse_defconfig(self):
        self.defconfig.write_text("""\
CONFIG_A=y
CONFIG_B=hello world
CONFIG_C=m
# CONFIG_D is not set
CONFIG_E=y # nocheck: this is a test
CONFIG_F=n
CONFIG_G="quoted string"
""")
        self.assertEqual(
            # pylint: disable=protected-access
            CheckConfig._parse_config(self.defconfig, is_dot_config=False),
            {
                "CONFIG_A": ConfigValue("y", self.defconfig),
                "CONFIG_B": ConfigValue("hello world", self.defconfig),
                "CONFIG_C": ConfigValue("m", self.defconfig),
                "CONFIG_D": ConfigValue("", self.defconfig),
                "CONFIG_E": ConfigValue("y", self.defconfig, "this is a test"),
                "CONFIG_F": ConfigValue("", self.defconfig),
                "CONFIG_G": ConfigValue("quoted string", self.defconfig),
            }
        )

    def test_nocheck_reasons(self):
        self.defconfig.write_text("""\
CONFIG_A=y # nocheck
CONFIG_B=y # nocheck:
CONFIG_C=y # nocheck: with reason
""")
        self.assertEqual(
            # pylint: disable=protected-access
            CheckConfig._parse_config(self.defconfig, is_dot_config=False),
            {
                "CONFIG_A": ConfigValue("y", self.defconfig, ""),
                "CONFIG_B": ConfigValue("y", self.defconfig, ""),
                "CONFIG_C": ConfigValue("y", self.defconfig, "with reason"),
            }
        )

    def test_bad_line(self):
        self.defconfig.write_text("""\
bad line
""")
        with self.assertRaises(ValueError):
            # pylint: disable=protected-access
            CheckConfig._parse_config(self.defconfig, is_dot_config=False)

    def test_merge(self):
        self.defconfig.write_text("""\
CONFIG_A=y
CONFIG_B=y
""")
        self.defconfig2.write_text("""\
# CONFIG_A is not set # nocheck: not enforced
CONFIG_C=y
""")
        self.assertEqual(
            # pylint: disable=protected-access
            CheckConfig._merge_post_defconfig_fragments([
                CheckConfig._parse_config(self.defconfig, is_dot_config=False),
                CheckConfig._parse_config(
                    self.defconfig2, is_dot_config=False),
            ]),
            [
                ("CONFIG_A", ConfigValue("y", self.defconfig)),
                ("CONFIG_B", ConfigValue("y", self.defconfig)),
                ("CONFIG_A", ConfigValue("", self.defconfig2, "not enforced")),
                ("CONFIG_C", ConfigValue("y", self.defconfig2)),
            ]
        )

    def test_check_simple(self):
        content = """\
CONFIG_A=y
# CONFIG_B is not set
"""
        self._test_check_common(content, [content], [], [])

    def test_check_fail(self):
        self._test_check_common(
            "CONFIG_A=y\n", ["# CONFIG_A is not set\n"], [
                Mismatch("CONFIG_A",
                         ConfigValue("", self.tempdir_path / "defconfig0"),
                         ConfigValue("y", self.dot_config))
            ], [])

    def test_check_n(self):
        """See b/364938352."""
        self._test_check_common(
            "# CONFIG_A is not set\n", ["CONFIG_A=n\n"], [], [])

    def test_check_n_missing(self):
        self._test_check_common(
            "", ["CONFIG_A=n\n"], [], [])

    def test_check_not_set_missing(self):
        self._test_check_common(
            "", ["# CONFIG_A is not set\n"], [], [])

    def test_check_warn(self):
        self._test_check_common(
            "# CONFIG_A is not set\n",
            ["CONFIG_A=y # nocheck\n"], [], [
                Mismatch("CONFIG_A",
                         ConfigValue("y", self.tempdir_path / "defconfig0",
                                     ""),
                         ConfigValue("", self.dot_config))
            ])

    def test_check_warn_opposite(self):
        self._test_check_common(
            "CONFIG_A=y\n",
            ["# CONFIG_A is not set # nocheck\n"],
            [],
            [
                Mismatch("CONFIG_A",
                         ConfigValue("", self.tempdir_path / "defconfig0",
                                     ""),
                         ConfigValue("y", self.dot_config))
            ])

    def test_merge_conflicting_y(self):
        self._test_check_common(
            "CONFIG_A=y\n",
            [
                "CONFIG_A=y\n",
                "# CONFIG_A is not set\n"
            ],
            [
                Mismatch("CONFIG_A",
                         ConfigValue("", self.tempdir_path / "defconfig1"),
                         ConfigValue("y", self.dot_config))
            ], [])

    def test_merge_conflicting_n(self):
        self._test_check_common(
            "# CONFIG_A is not set\n",
            [
                "CONFIG_A=y\n",
                "# CONFIG_A is not set\n"
            ],
            [
                Mismatch("CONFIG_A",
                         ConfigValue("y", self.tempdir_path / "defconfig0"),
                         ConfigValue("", self.dot_config))
            ], [])

    def test_merge_conflicting_warn_y(self):
        self._test_check_common(
            "CONFIG_A=y\n",
            [
                "CONFIG_A=y\n",
                "# CONFIG_A is not set # nocheck\n"
            ],
            [],
            [
                Mismatch("CONFIG_A",
                         ConfigValue("", self.tempdir_path / "defconfig1", ""),
                         ConfigValue("y", self.dot_config))
            ])

    def test_merge_conflicting_warn_n(self):
        self._test_check_common(
            "# CONFIG_A is not set\n",
            [
                "CONFIG_A=y # nocheck\n",
                "# CONFIG_A is not set\n"
            ],
            [],
            [
                Mismatch("CONFIG_A",
                         ConfigValue("y", self.tempdir_path /
                                     "defconfig0", ""),
                         ConfigValue("", self.dot_config))
            ])

    def _test_check_common(
            self,
            dot_config_content: str,
            defconfig_contents: list[str],
            expected_errors: list[Mismatch],
            expected_warnings: list[Mismatch]):
        self.dot_config.write_text(dot_config_content)

        defconfig_paths = []
        for index, content in enumerate(defconfig_contents):
            defconfig_path = self.tempdir_path / f"defconfig{index}"
            defconfig_path.write_text(content)
            defconfig_paths.append(defconfig_path)

        check_config = CheckConfig(self.dot_config, defconfig_paths)
        # pylint: disable=protected-access
        check_config._check()
        # pylint: disable=protected-access
        self.assertEqual(check_config._errors, expected_errors)
        self.assertEqual(check_config._warnings, expected_warnings)


if __name__ == "__main__":
    absltest.main()
