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

load(":ddk/ddk_module.bzl", "ddk_module")
load(":ddk/ddk_package.bzl", "ddk_package")

def ddk_module_package(
        name,
        kernel_build,
        module_name,
        srcs = None,
        hdrs = None,
        deps = None,
        **kwargs):
    """The combination of [`ddk_module`](#ddk_module) and [`ddk_package`](#ddk_package).

    This is useful for simple modules with only one module in the package.

    Args:
        name: See [`ddk_package.name`](#ddk_package-name). Name of the target.
        module_name: Name of the `.ko` file without the suffix.

            To specify multiple `.ko` file within this package, specify multiple
            [`ddk_module`](#ddk_module)s
            and one [`ddk_package`](#ddk_package); do not use `ddk_module_package`.
        kernel_build: See [`ddk_module.kernel_build`](#ddk_module-kernel_build)
        srcs: See [`ddk_module.srcs`](#ddk_module-srcs)
        hdrs: See [`ddk_module.hdrs`](#ddk_module-hdrs)
        deps: See [`ddk_module.deps`](#ddk_module-deps)
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    ddk_module(
        name = module_name,
        kernel_build = kernel_build,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        **kwargs
    )

    ddk_package(
        name = name,
        kernel_build = kernel_build,
        deps = [module_name],
        **kwargs
    )
