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

"""Drop-in replacement for skylib's common_settings.bzl.

- `make_variable` attribute is not supported.
- `error_if`: If not None, and the value of the flag is the same as this value,
  emit a build error.
- `warn_if`: If not None, and the value of the flag is the same as this value,
  emit a deprecation warning.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _bool_flag_impl(ctx):
    if (ctx.attr.error_if_1 == ctx.attr.error_if_2 and
        ctx.attr.error_if_1 == ctx.build_setting_value):
        fail("{} has invalid value {}".format(ctx.label, ctx.build_setting_value))
    if (ctx.attr.warn_if_1 == ctx.attr.warn_if_2 and
        ctx.attr.warn_if_1 == ctx.build_setting_value):
        # buildifier: disable=print
        print("""
WARNING: {} has deprecated value {}.
    This will be unsupported in the future.
""".format(ctx.label, ctx.build_setting_value))
    return [
        BuildSettingInfo(value = ctx.build_setting_value),
    ]

_bool_flag = rule(
    implementation = _bool_flag_impl,
    build_setting = config.bool(flag = True),
    attrs = {
        # Split into two attributes so we can test if the value is actually set.
        "error_if_1": attr.bool(default = False),
        "error_if_2": attr.bool(default = True),
        "warn_if_1": attr.bool(default = False),
        "warn_if_2": attr.bool(default = True),
    },
)

def bool_flag(
        name,
        error_if = None,
        warn_if = None,
        build_setting_default = None,
        **kwargs):
    _bool_flag(
        name = name,
        error_if_1 = error_if,
        error_if_2 = error_if,
        warn_if_1 = warn_if,
        warn_if_2 = warn_if,
        build_setting_default = build_setting_default,
        **kwargs
    )

def _string_flag_impl(ctx):
    if ctx.attr.error_if and ctx.attr.error_if == ctx.build_setting_value:
        fail("{} has invalid value {}".format(ctx.label, ctx.build_setting_value))
    if ctx.attr.warn_if and ctx.attr.warn_if == ctx.build_setting_value:
        # buildifier: disable=print
        print("""
WARNING: {} has deprecated value {}.
    This will be unsupported in the future.
""".format(ctx.label, ctx.build_setting_value))

    if ctx.attr.values and ctx.build_setting_value not in ctx.attr.values:
        fail("{} has invalid value {}. Valid values are {}".format(
            ctx.label,
            ctx.build_setting_value,
            ctx.attr.values,
        ))

    return [
        BuildSettingInfo(value = ctx.build_setting_value),
    ]

string_flag = rule(
    implementation = _string_flag_impl,
    build_setting = config.string(flag = True),
    attrs = {
        "error_if": attr.string(),
        "warn_if": attr.string(),
        "values": attr.string_list(),
    },
)
