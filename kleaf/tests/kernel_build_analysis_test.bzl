# Copyright (C) 2022 The Android Open Source Project
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

# Define all analysis test for kernel_build().

load(":kernel_build_symtypes_test.bzl", "kernel_build_symtypes_test")

def kernel_build_analysis_test_suite(name):
    """Define all analysis test for `kernel_build()`."""
    native.test_suite(
        name = name,
        tests = [
            kernel_build_symtypes_test(name),
        ],
    )
