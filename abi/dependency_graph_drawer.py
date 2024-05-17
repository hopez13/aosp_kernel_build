#!/usr/bin/env python3
#
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
#
# Utility function to create a visualization graph using dot language.

import argparse
import hashlib
import json
import logging
import pathlib
import sys


def create_graphviz(
    adjacency_list: dict,
    output: pathlib.Path,
    colors: bool,
):
    "Creates a diagram to display a graph using dot language."
    content = ["digraph {"]
    content.extend([
        "\tgraph [rankdir=LR, splines=ortho];",
        "\tnode [color=steelblue, shape=plaintext];",
        "\tedge [arrowhead=odot, color=olive];",
    ])
    for node in adjacency_list.values():
        # vmlinux is dependency for most of the nodes so skip it.
        if node["name"] == "vmlinux":
            continue
        # Skip nodes without dependents.
        if not node["dependents"]:
            # logging.warning(f"Skipping leaf module {modules[from_id]}")
            continue
        edges = []
        for neighbor in node["dependents"]:
            edges.append(f'"{adjacency_list[neighbor]["name"]}"')
        edge_str = ",".join(edges)
        # Customize edge colors.
        edge_color = ""
        if colors:
            h = hashlib.shake_256(edge_str.encode())
            edge_color = f' [color="  # {h.hexdigest(3)}"]'
        content.append(f'\t"{node["name"]}" -> {edge_str}{edge_color};')
    content.append("}")
    out = pathlib.Path(output)
    out.write_text("\n".join(content), encoding="utf-8")


def read_graph(
    adjacency_list_file: pathlib.Path,
):
    with open(adjacency_list_file, "r", encoding="utf-8") as adjacency_list:
        try:
            return json.load(adjacency_list)
        except json.JSONDecodeError as e:
            logging.error("Failed to load %s: %s", adjacency_list_file, e)
            sys.exit(1)


def main():
    """Creates two maps of dependencies a directory full of kernel modules."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "adjacency_list_file",
        type=pathlib.Path,
        help="File with a graph represented as an adjacency list.",
    )
    parser.add_argument("output", help="Where to store the output")
    parser.add_argument(
        "--colors",
        action="store_true",
        help=(
            "Edges to dependents of a module share the same color. This is"
            " useful to differentiate dependencies of a module."
        ),
    )

    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    adjacency_list = read_graph(args.adjacency_list_file)
    # Create graph visualization.
    create_graphviz(adjacency_list, args.output, args.colors)


if __name__ == "__main__":
    sys.exit(main())
