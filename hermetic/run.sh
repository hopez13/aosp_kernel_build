#!/bin/bash
#
# Copyright (C) 2020 The Android Open Source Project
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

set -e

BASE_DIR=$(readlink -f $(dirname $0)/../../../)

# Build the hermetic container
docker build -t hermetic $BASE_DIR/build/kernel/hermetic

# Run the hermetic container
docker run -ti                                                  \
           --user $(id -u):$(id -g)                             \
           --mount type=bind,source=/mnt/sdc/glibc/glibc-2.38/build/install,target=/glibc/      \
           --mount type=bind,source=${BASE_DIR},target=/b/      \
           hermetic
