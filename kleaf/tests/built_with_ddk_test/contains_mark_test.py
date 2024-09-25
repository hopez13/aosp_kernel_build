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
import pathlib
import re
import subprocess
import sys
import unittest

from absl.testing import absltest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel_module", nargs="+",
                        type=pathlib.Path, help="Kernel module file")
    parser.add_argument("--depmod",
                        type=pathlib.Path, help="Depmod tool")
    return parser.parse_known_args()


arguments = None


class CheckMarkTest(unittest.TestCase):
    def test_all(self):
        modules = [
            m for m in arguments.kernel_module if m.suffix == ".ko"]
        self.assertTrue(len(modules) > 0, "no .ko files found")
        modinfo = pathlib.Path("modinfo")
        modinfo.symlink_to(arguments.depmod)
        for module in modules:
            out = subprocess.check_output(
                [modinfo, "-F", "built_with", module],  text=True)
            tag_count = 0
            for line in out.split("\n"):
                if line == "DDK":
                    tag_count += 1
                self.assertEqual(
                    tag_count, 1, "built with DDK tag should appear exactly once")


if __name__ == '__main__':
    arguments, _ = load_arguments()
    sys.argv[1:] = _
    absltest.main()
