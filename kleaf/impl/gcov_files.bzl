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

"""Export GCOV files."""

load(":common_providers.bzl", "GcovInfo")

visibility("//build/kernel/kleaf/...")

def _gcov_files_impl(ctx):
    files = [
        src[GcovInfo].gcno_mapping
        for src in ctx.attr.srcs
        if src[GcovInfo].gcno_mapping
    ]
    return [
        DefaultInfo(
            files = depset(files),
        ),
    ]

gcov_files = rule(
    implementation = _gcov_files_impl,
    doc = "Export the files for coverage analysis if GCOV is enabled.",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            doc = "kernel_build or kernel_module",
            providers = [GcovInfo],
        ),
    },
)
