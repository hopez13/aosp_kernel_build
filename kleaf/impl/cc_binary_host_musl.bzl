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

"""Drop-in replacement of cc_binary so it can be built against musl libc."""

load(":transitioned_tool.bzl", "transitioned_tool")

# Used by all *.BUILD files for sub-repositories generated by @kleaf. This is not expected to be
# used outside of @kleaf; however, load visibility does not support repo-level controls.
visibility("public")

def cc_binary_host_musl(name, visibility, **kwargs):
    """Drop-in replacement of cc_binary so it can be built against musl libc.

    If --musl_tools_from_sources, this binary is built against the host musl libc. Otherwise it
    uses the default target platform.

    Args:
        name: name of the target. Note that the final binary has a different name.
        visibility: visibility
        **kwargs: passthrough kwargs to cc_binary.
    """
    kwargs["deps"] = (kwargs.get("deps", None) or []) + select({
        Label("//build/kernel/kleaf/platforms/libc:musl"): [Label("//prebuilts/kernel-build-tools:libc_musl")],
        "//conditions:default": [],
    })
    kwargs.setdefault("linkstatic", select({
        Label("//build/kernel/kleaf/platforms/libc:musl"): False,
        "//conditions:default": None,
    }))

    native.cc_binary(
        name = name + "_bin",
        visibility = ["//visibility:private"],
        **kwargs
    )

    transitioned_tool(
        name = name,
        src = name + "_bin",
        target_platform = select({
            Label("//build/kernel/kleaf:musl_tools_from_sources_is_true"): Label("//build/kernel/kleaf/impl:host_musl"),
            "//conditions:default": None,
        }),
        visibility = visibility,
    )
