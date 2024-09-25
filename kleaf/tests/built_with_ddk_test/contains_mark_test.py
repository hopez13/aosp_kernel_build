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
import collections
import unittest
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


class CheckMarkTest(unittest.TestCase):
    def test_all(self):
        modulePath = [
            m for m in arguments.kernel_module if m.suffix == ".ko"][0]
        print("Hello World")
        out = subprocess.check_output(
            [arguments.readelf_tool, "-X .modinfo", modulePath], stderr=subprocess.STDOUT)
        print(f"{out = }")
        # .decode()
        print("Hello World!!")
        # print(arguments)


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
