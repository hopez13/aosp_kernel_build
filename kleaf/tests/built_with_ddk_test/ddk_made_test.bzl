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

"""Tests that different DDK use cases are properly marked."""

load(
    "//build/kernel/kleaf:kernel.bzl",
    "ddk_module",
    "ddk_submodule",
)
load(":contains_mark_test.bzl", "contains_mark_test")

def _ddk_module_test_make(
        name,
        **kwargs):
    ddk_module(
        name = name + "_module",
        tags = ["manual"],
        **kwargs
    )

    contains_mark_test(
        name = name,
        kernel_module = name + "_module",
    )

def ddk_made_test(name):
    """Tests built_with DDK marking.

    Args:
        name: name of the test suite.
    """

    # Tests
    tests = []

    # License test (a.k.a one file)
    _ddk_module_test_make(
        name = name + "_license_sample_test",
        srcs = ["license.c"],
        out = name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
    )
    tests.append(name + "_license_sample_test")

    # Submodule Tests
    ddk_submodule(
        name = name + "_submodule_dep_a",
        out = name + "_submodule_dep_a.ko",
        srcs = ["license.c"],
        tags = ["manual"],
    )
    _ddk_module_test_make(
        name = name + "_submodule_test",
        kernel_build = "//common:kernel_aarch64",
        deps = [
            name + "_submodule_dep_a",
        ],
    )
    tests.append(name + "_submodule_test_b")
    ddk_submodule(
        name = name + "_submodule_dep_b",
        out = name + "_submodule_dep_b.ko",
        srcs = [
            "subdir/license.c",
            #    "subdir/dep.c"
        ],
        tags = ["manual"],
    )
    # TODO: Fix this tests case.
    # _ddk_module_test_make(
    #    name = name + "_submodule_test_a_b",
    #    kernel_build = "//common:kernel_aarch64",
    #    deps = [
    #        name + "_submodule_dep_a",
    #        name + "_submodule_dep_b",
    #    ],
    # )
    # tests.append(name + "_submodule_test_a_b")

    # Multiple source files with ddk_marker collision.
    _ddk_module_test_make(
        name = name + "_multiple_files_test",
        srcs = [
            "dep.c",
            "license.c",
        ],
        out = name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
    )
    tests.append(name + "_multiple_files_test")

    # Tests for subdirectories.
    _ddk_module_test_make(
        name = name + "_multiple_files_in_subdir_test",
        srcs = [
            "subdir/dep.c",
            "subdir/license.c",
        ],
        out = "subdir/" + name + "_module.ko",
        kernel_build = "//common:kernel_aarch64",
    )
    tests.append(name + "_multiple_files_in_subdir_test")
    _ddk_module_test_make(
        name = name + "_single_file_in_subdir_test",
        srcs = [
            "subdir/license.c",
        ],
        out = "subdir/" + name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
    )
    tests.append(name + "_single_file_in_subdir_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
