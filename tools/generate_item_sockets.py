#!/usr/bin/env python3
"""Generate compact TopFit socket metadata from AzerothCore item_template.sql."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SOCKET_MASKS = {0, 1, 2, 4, 8, 14}
SOURCE_REPO = "azerothcore/azerothcore-wotlk"
SOURCE_PATH = "data/sql/base/db_world/item_template.sql"


def parse_tuple(line: str) -> list[str]:
    values: list[str] = []
    current: list[str] = []
    quoted = False
    escaped = False

    end = len(line)
    if line.endswith("),") or line.endswith(");"):
        end -= 2
    elif line.endswith(")"):
        end -= 1

    for char in line[1:end]:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if quoted and char == "\\":
            current.append(char)
            escaped = True
            continue
        if char == "'":
            current.append(char)
            quoted = not quoted
            continue
        if char == "," and not quoted:
            values.append("".join(current))
            current = []
            continue
        current.append(char)

    values.append("".join(current))
    return values


def columns_from_sql(sql: str) -> list[str]:
    start = sql.index("CREATE TABLE `item_template`")
    end = sql.index(") ENGINE=", start)
    create_table = sql[start:end]
    return re.findall(r"^\s*`([^`]+)`", create_table, flags=re.MULTILINE)


def generate(sql: str, source_ref: str) -> str:
    columns = columns_from_sql(sql)
    indexes = {name: columns.index(name) for name in (
        "entry",
        "InventoryType",
        "socketColor_1",
        "socketColor_2",
        "socketColor_3",
        "socketBonus",
    )}

    rows: list[tuple[int, int]] = []
    for line in sql.splitlines():
        if not line.startswith("("):
            continue

        values = parse_tuple(line)
        if len(values) != len(columns):
            continue
        if int(values[indexes["InventoryType"]] or 0) == 0:
            continue

        colors = [
            int(values[indexes["socketColor_1"]] or 0),
            int(values[indexes["socketColor_2"]] or 0),
            int(values[indexes["socketColor_3"]] or 0),
        ]
        if not any(colors):
            continue
        if any(color not in SOCKET_MASKS for color in colors):
            raise ValueError(f"unknown socket color mask for item {values[indexes['entry']]}: {colors}")

        item_id = int(values[indexes["entry"]])
        socket_bonus = int(values[indexes["socketBonus"]] or 0)
        packed = colors[0] + colors[1] * 16 + colors[2] * 256 + socket_bonus * 4096
        rows.append((item_id, packed))

    rows.sort()
    lines = [
        "-- Generated file. Do not edit by hand.",
        f"-- Source: https://github.com/{SOURCE_REPO}/blob/{source_ref}/{SOURCE_PATH}",
        "-- AzerothCore item_template socketColor_1..3 + socketBonus, packed as:",
        "--   c1 + c2*16 + c3*256 + socketBonus*4096",
        "-- Socket masks: META=1, RED=2, YELLOW=4, BLUE=8, PRISMATIC=14.",
        f"-- Rows: {len(rows)}",
        "",
        "TopFit.itemSocketData = {",
    ]
    lines.extend(f"    [{item_id}] = {packed}," for item_id, packed in rows)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("item_template_sql", type=Path)
    parser.add_argument("--source-ref", required=True, help="Pinned AzerothCore commit SHA")
    parser.add_argument("--output", type=Path, default=Path("data/item_sockets.lua"))
    args = parser.parse_args()

    sql = args.item_template_sql.read_text(encoding="utf-8")
    output = generate(sql, args.source_ref)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
