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

import argparse
import unittest
import re
import subprocess
import sys
import pathlib

from absl.testing import absltest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel_module", nargs="+",
                        type=pathlib.Path, help="Kernel module file")
    parser.add_argument("--readelf_tool",
                        type=pathlib.Path, help="Readelf tool")
    return parser.parse_known_args()


arguments = None


def extract_key_value(line):
    pattern = r"\[.*?\]\s*(.*?)\s*=\s*(.*)"
    match = re.match(pattern, line)
    if match:
        return match.group(1), match.group(2)
    else:
        return "", ""


class CheckMarkTest(unittest.TestCase):
    def test_all(self):
        modulePath = [
            m for m in arguments.kernel_module if m.suffix == ".ko"]
        self.assertTrue(len(modulePath) == 1,
                        "test requires exactly one .ko file")
        modulePath = modulePath[0]
        out = subprocess.check_output(
            [arguments.readelf_tool, "-p", ".modinfo", modulePath],  text=True)
        tag_count = 0
        for line in out.split("\n")[1:]:
            tag, value = extract_key_value(line)
            if tag == "built_with" and value == "DDK":
                tag_count += 1
        self.assertTrue(
            tag_count == 1, "built with DDK tag should appear exactly once")


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
