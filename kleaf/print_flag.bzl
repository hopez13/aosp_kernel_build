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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _impl(ctx):
    print("{}={}".format(ctx.attr.flag.label, ctx.attr.flag[BuildSettingInfo].value))

print_flag = rule(
    doc = "A rule that prints a flag",
    implementation = _impl,
    attrs = {
        "flag": attr.label(providers = [BuildSettingInfo]),
    },
)
