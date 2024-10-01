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

load("//build/kernel/kleaf:kernel.bzl", "ddk_module")
load(":contains_mark_test.bzl", "contains_mark_test")

def ddk_made_test(name):
    """Tests built_with DDK marking.

    Args:
        name: name of the test suite.
    """

    # Test setup
    ddk_module(
        name = name + "_license_sample",
        srcs = ["license.c"],
        out = "sample_license_module.ko",
        tags = ["manual"],
        kernel_build = "//common:kernel_aarch64",
    )

    # Tests
    tests = []
    contains_mark_test(
        name = name + "_license_sample_mark_test",
        kernel_module = name + "_license_sample",
    )
    tests.append(name + "_license_sample_mark_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
