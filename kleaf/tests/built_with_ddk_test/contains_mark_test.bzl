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

"""Test that a given kernel module has the built with DDK modinfo tag."""

load("@kernel_toolchain_info//:dict.bzl", "VARS")

def contains_mark_test(name, kernel_module, readelf_tool = None):
    """See `contain_lines_test.py` for explanation.

    Args:
        name: name of test
        kernel_module: A label expanding into the module file.
        readelf_tool: Label to the readelf tool used for testing.
    """

    # Default to
    if readelf_tool == None:
        readelf_tool = "//prebuilts/clang/host/linux-x86/clang-{}:bin/llvm-readelf".format(VARS["CLANG_VERSION"])

    args = [
        "--kernel_module",
        "$(locations {})".format(kernel_module),
        "--readelf_tool",
        "$(execpath {})".format(readelf_tool),
    ]

    native.py_test(
        name = name,
        python_version = "PY3",
        main = "contains_mark_test.py",
        srcs = ["//build/kernel/kleaf/tests/built_with_ddk_test:contains_mark_test.py"],
        data = [kernel_module, readelf_tool],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
    )
