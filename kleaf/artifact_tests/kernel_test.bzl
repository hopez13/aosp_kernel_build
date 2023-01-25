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
"""
Tests for artifacts produced by kernel_module.
"""

visibility("//build/kernel/kleaf/...")

def kernel_module_test(
        name,
        modules = None,
        **kwargs):
    """A test on artifacts produced by [kernel_module](#kernel_module).

    Args:
        name: name of test
        modules: The list of `*.ko` kernel modules, or targets that produces
            `*.ko` kernel modules (e.g. [kernel_module](#kernel_module)).
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:kernel_module_test.py"
    modinfo = "//build/kernel:hermetic-tools/modinfo"
    args = ["--modinfo", "$(location {})".format(modinfo)]
    data = [modinfo]
    if modules:
        args.append("--modules")
        args += ["$(locations {})".format(module) for module in modules]
        data += modules

    native.py_test(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = data,
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
        **kwargs
    )

def kernel_build_test(
        name,
        target = None,
        **kwargs):
    """A test on artifacts produced by [kernel_build](#kernel_build).

    Args:
        name: name of test
        target: The [`kernel_build()`](#kernel_build).
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:kernel_build_test.py"
    strings = "//build/kernel:hermetic-tools/llvm-strings"
    args = ["--strings", "$(location {})".format(strings)]
    if target:
        args += ["--artifacts", "$(locations {})".format(target)]

    native.py_test(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = [target, strings],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
            "@io_abseil_py//absl/testing:parameterized",
        ],
        **kwargs
    )

def initramfs_modules_options_test(
        name,
        kernel_images,
        expected_modules_options,
        **kwargs):
    """Tests that initramfs has modules.options with the given content.

    Args:
        name: name of the test
        kernel_images: name of the `kernel_images` target. It must build initramfs.
        expected_modules_options: file with expected content for `modules.options`
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:initramfs_modules_options_test.py"
    cpio = "//build/kernel:hermetic-tools/cpio"
    diff = "//build/kernel:hermetic-tools/diff"
    gzip = "//build/kernel:hermetic-tools/gzip"
    args = [
        "--cpio",
        "$(location {})".format(cpio),
        "--diff",
        "$(location {})".format(diff),
        "--gzip",
        "$(location {})".format(gzip),
        "--expected",
        "$(location {})".format(expected_modules_options),
        "$(locations {})".format(kernel_images),
    ]

    native.py_test(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = [
            cpio,
            diff,
            expected_modules_options,
            gzip,
            kernel_images,
        ],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
        **kwargs
    )

def initramfs_modules_lists_test(
        name,
        kernel_images,
        expected_modules_list = None,
        expected_modules_recovery_list = None,
        expected_modules_charger_list = None,
        **kwargs):
    """Tests that the initramfs has modules.load* files with the given content.

    Args:
        name: name of the test
        kernel_images: name of the `kernel_images` target. It must build initramfs.
        expected_modules_list: file with the expected content for `modules.load`
        expected_modules_recovery_list: file with the expected content for `modules.load.recovery`
        expected_modules_charger_list: file with the expected content for `modules.load.charger`
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    test_binary = Label("//build/kernel/kleaf/artifact_tests:initramfs_modules_lists_test")
    args = []

    if expected_modules_list:
        args += [
            "--expected_modules_list",
            "$(rootpath {})".format(expected_modules_list),
        ]

    if expected_modules_recovery_list:
        args += [
            "--expected_modules_recovery_list",
            "$(rootpath {})".format(expected_modules_recovery_list),
        ]

    if expected_modules_charger_list:
        args += [
            "--expected_modules_charger_list",
            "$(rootpath {})".format(expected_modules_charger_list),
        ]

    args.append("$(rootpaths {})".format(kernel_images))

    hermetic_exec_test(
        name = name,
        data = [
            expected_modules_list,
            expected_modules_recovery_list,
            expected_modules_charger_list,
            kernel_images,
            test_binary,
        ],
        script = run_py_binary_cmd(test_binary),
        args = args,
        timeout = "short",
        **kwargs
    )
