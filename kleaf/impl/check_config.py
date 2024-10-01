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

"""Checks that the input .config has all listed in defconfig and fragments."""

import argparse
import dataclasses
import os
import pathlib
import re
import sys
import textwrap


@dataclasses.dataclass(frozen=True)
class ConfigValue:
    value: str
    source: pathlib.Path
    nocheck_reason: str | None = None


@dataclasses.dataclass(frozen=True)
class Mismatch:
    key: str
    expected: ConfigValue
    actual: ConfigValue


ParsedConfig = dict[str, ConfigValue]
MergedPostDefconfig = list[tuple[str, ConfigValue]]


@dataclasses.dataclass
class CheckConfig:
    """Kernel config checker."""

    dot_config: pathlib.Path
    post_defconfig_fragments: list[pathlib.Path]

    def __post_init__(self):
        self.actual = self._parse_dot_config(self.dot_config)
        self.expected = self._merge_post_defconfig_fragments(
            self._parse_defconfig(fragment)
            for fragment in self.post_defconfig_fragments)

    def run(self):
        """Executes the check.

        Returns:
            True if check passes (no errors), false otherwise."""
        self._check()

        for mismatch in self._errors:
            print(textwrap.dedent(f"""\
                ERROR: {mismatch.key}: actual '{mismatch.actual.value}', expected '{mismatch.expected.value}' from {mismatch.expected.source}
            """), file=sys.stderr)

        for mismatch in self._warnings:
            print(textwrap.dedent(f"""\
                WARNING: {mismatch.key}: actual '{mismatch.actual.value}', expected '{mismatch.expected.value}' from {mismatch.expected.source}
                    (ignore reason: {mismatch.expected.nocheck_reason})
            """), file=sys.stderr)

        return not self._errors

    def _check(self):
        """Executes the check.

        Sets error_keys and warning_keys."""
        self._errors = list[Mismatch]()
        self._warnings = list[Mismatch]()

        for key, expected_config_value in self.expected:
            actual_config_value = self.actual.get(
                key, ConfigValue("", self.dot_config))
            if actual_config_value.value != expected_config_value.value:
                mismatch = Mismatch(
                    key, expected_config_value, actual_config_value)
                if expected_config_value.nocheck_reason is not None:
                    self._warnings.append(mismatch)
                else:
                    self._errors.append(mismatch)

    @staticmethod
    def _merge_post_defconfig_fragments(fragments) -> MergedPostDefconfig:
        """Merge a list of **post** defconfig fragments.

        For post defconfig fragments, all requirements from all fragments
        are considered. No overriding is done."""
        ret = MergedPostDefconfig()
        for fragment in fragments:
            ret.extend(fragment.items())
        return ret

    @classmethod
    def _parse_config(cls, path: pathlib.Path, is_dot_config: bool) \
            -> ParsedConfig:
        """Common functions for parsing .config and defconfig."""

        if is_dot_config:
            # For .config, no # nocheck comments are parsed.
            config_set_value = re.compile(
                r"^(?P<key>CONFIG_\w*)=(?P<maybe_quoted_value>.*)")
            config_unset = re.compile(r"^# (?P<key>CONFIG_\w*) is not set$")
        else:
            nocheck = r"(\s*# nocheck:?\s*(?P<reason>.*))?"
            config_set_value = re.compile(
                r"^(?P<key>CONFIG_\w*)=(?P<maybe_quoted_value>.*?)" +
                nocheck + "$")
            config_unset = re.compile(
                r"^# (?P<key>CONFIG_\w*) is not set" + nocheck + "$")
        ret = ParsedConfig()

        with path.open() as f:
            for line in f:
                line = line.rstrip()  # strip new line character
                mo = config_set_value.match(line)
                if mo:
                    if is_dot_config:
                        ret[mo.group("key")] = ConfigValue(
                            cls._unquote(mo.group("maybe_quoted_value")),
                            path)
                    else:
                        reason = mo.group("reason")
                        if reason is not None:
                            reason = reason.strip()
                        val = cls._unquote(mo.group("maybe_quoted_value"))
                        # As a special case, CONFIG_X=n in defconfig means
                        # unsetting it.
                        if val == "n":
                            val = ""
                        ret[mo.group("key")] = ConfigValue(val, path, reason)
                    continue  # to next line

                mo = config_unset.match(line)
                if mo:
                    reason = mo.groupdict().get("reason")
                    if reason is not None:
                        reason = reason.strip()
                    ret[mo.group(1)] = ConfigValue("", path, reason)
                    continue  # to next line

                if line.lstrip().startswith("#"):
                    # ignore comment lines
                    continue  # to next line
                raise ValueError(f"Unexpected line in {path}: {line}")

        return ret

    @staticmethod
    def _unquote(s: str) -> str:
        """Unquote a string in .config.

        Note: This is a naive algorithm and it doesn't necessarily match
        how kconfig handles things.
        """
        if s.startswith('"') and s.endswith('"'):
            return s[1:-1]
        return s

    @classmethod
    def _parse_dot_config(cls, path: pathlib.Path) -> ParsedConfig:
        return CheckConfig._parse_config(path, is_dot_config=True)

    @classmethod
    def _parse_defconfig(cls, path: pathlib.Path) -> ParsedConfig:
        return CheckConfig._parse_config(path, is_dot_config=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dot_config", type=pathlib.Path, required=True)

    parser.add_argument("--post_defconfig_fragments",
                        type=pathlib.Path, required=True, nargs="*",
                        default=[])

    args = parser.parse_args()
    sys.exit(os.EX_OK if CheckConfig(**vars(args)).run() else os.EX_SOFTWARE)
