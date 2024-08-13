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

"""Like `native_binary` but invoked with a given list of arguments."""

load("@bazel_skylib//rules:native_binary.bzl", "native_binary")
load("@bazel_skylib//rules:write_file.bzl", "write_file")

visibility("//build/kernel/...")

def native_binary_with_arg(
        name,
        src,
        args,
        **kwargs):
    """Like `native_binary` but invoked with a given list of arguments.

    Args:
        name: name of the target
        src: actual native binary
        args: list of arguments
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    private_kwargs = kwargs | dict(
        visibility = ["//visibility:private"],
    )

    native_binary(
        name = "kleaf_internal_do_not_use/{}".format(name),
        out = "kleaf_internal_do_not_use/{}".format(name),
        src = src,
        **private_kwargs
    )

    write_file(
        name = "kleaf_internal_do_not_use/{}_args".format(name),
        out = "kleaf_internal_do_not_use/{}_args.txt".format(name),
        content = args + [""],
        **private_kwargs
    )

    native.cc_binary(
        name = name,
        srcs = [Label("arg_wrapper.cpp")],
        data = [
            ":kleaf_internal_do_not_use/{}".format(name),
            ":kleaf_internal_do_not_use/{}_args".format(name),
        ],
        **kwargs
    )
