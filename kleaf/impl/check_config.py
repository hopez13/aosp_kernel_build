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

"""Checks that the input .config has all CONFIG_s listed in defconfig and
fragments."""

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

# Merged list of defconfig expectations.
MergedDefconfig = list[tuple[str, ConfigValue]]


@dataclasses.dataclass
class CheckConfig:
    """Kernel config checker."""

    dot_config: pathlib.Path
    defconfig: pathlib.Path | None = None
    pre_defconfig_fragments: list[pathlib.Path] = dataclasses.field(
        default_factory=list)
    post_defconfig_fragments: list[pathlib.Path] = dataclasses.field(
        default_factory=list)

    def __post_init__(self):
        self._actual = self._parse_config(self.dot_config, is_dot_config=True)
        self._expected = self._merge_defconfig()

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

        Sets errors and warnings."""
        self._errors = list[Mismatch]()
        self._warnings = list[Mismatch]()

        for key, expected_config_value in self._expected:
            actual_config_value = self._actual.get(
                key, ConfigValue("", self.dot_config))
            if actual_config_value.value != expected_config_value.value:
                mismatch = Mismatch(
                    key, expected_config_value, actual_config_value)
                if expected_config_value.nocheck_reason is not None:
                    self._warnings.append(mismatch)
                else:
                    self._errors.append(mismatch)

    def _merge_defconfig(self) -> MergedDefconfig:
        """Merge a list of defconfig and fragments.

        Pre overrides defconfig. Later fragments in pre overrides earlier ones.
        Post overrides pre and defconfig.

        For post defconfig fragments, all requirements from all fragments
        are considered. No overriding is done.
        """

        defconfig_and_pre = ParsedConfig()
        if self.defconfig is not None:
            defconfig_and_pre.update(
                self._parse_config(self.defconfig, is_dot_config=False))

        # pre overrides defconfig. Later overrides former.
        for path in self.pre_defconfig_fragments:
            defconfig_and_pre.update(
                self._parse_config(path, is_dot_config=False))

        # No override for post
        merged_post = MergedDefconfig()
        for path in self.post_defconfig_fragments:
            parsed = self._parse_config(path, is_dot_config=False)
            merged_post.extend(parsed.items())
        post_keys = {key for key, _ in merged_post}

        # Post overrides defconfig & pre
        ret = MergedDefconfig()
        for key, value in defconfig_and_pre.items():
            if key not in post_keys:
                ret.append((key, value))
        ret += merged_post

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

                # If line matches CONFIG_X=..., set the value for this fragment
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
                        val = mo.group("maybe_quoted_value")
                        # As a special case, CONFIG_X=n in defconfig means
                        # unsetting it.
                        if val == "n":
                            val = ""
                        ret[mo.group("key")] = ConfigValue(
                            cls._unquote(val), path, reason)
                    continue  # to next line

                # If the line matches # CONFIG_X is not set, set the value to
                # empty. Technically we could also just leave it alone since
                # the default is empty, but let's handle this case for
                # completeness.
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

                if not line.strip():
                    # ignore empty lines
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dot_config", type=pathlib.Path, required=True)

    parser.add_argument("--defconfig", type=pathlib.Path)
    parser.add_argument("--pre_defconfig_fragments",
                        type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--post_defconfig_fragments",
                        type=pathlib.Path, nargs="*", default=[])

    args = parser.parse_args()
    sys.exit(os.EX_OK if CheckConfig(**vars(args)).run() else os.EX_SOFTWARE)
