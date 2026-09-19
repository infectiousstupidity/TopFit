#!/usr/bin/env python3
"""Generate compact current-phase raid upgrade sources from pinned AtlasLoot Wrath source data."""

from __future__ import annotations

import argparse
import re
import urllib.request
from pathlib import Path

ATLASLOOT_COMMIT = "8e99341e4e779328460bf7684c0d5b22ce50ddf1"
SOURCE_URL = (
    "https://raw.githubusercontent.com/Hoizame/AtlasLootClassic/"
    f"{ATLASLOOT_COMMIT}/AtlasLootClassic_Data/source-wrath.lua"
)

INSTANCE_NAMES = {
    20: (
        "Ulduar",
        [
            "Flame Leviathan",
            "Ignis the Furnace Master",
            "Razorscale",
            "XT-002 Deconstructor",
            "The Iron Council",
            "Kologarn",
            "Algalon the Observer",
            "Auriaya",
            "Hodir",
            "Thorim",
            "Freya",
            "Mimiron",
            "General Vezax",
            "Yogg-Saron",
            "Trash",
            "Patterns",
        ],
    ),
    25: (
        "Vault of Archavon",
        [
            "Archavon the Stone Watcher",
            "Emalon the Storm Watcher",
        ],
    ),
}

ENTRY_RE = re.compile(r"^\[(\d+)\]\s*=\s*(.+),\s*$")
KEYED_SOURCE_RE = re.compile(
    r"\{\[1\]\s*=\s*(20|25),\[2\]\s*=\s*(\d+),\[3\]\s*=\s*1"
    r"(?:,\[4\]\s*=\s*\d+)?(?:,\[5\]\s*=\s*(\{[\d,\s]+\}|\d+))?[^{}]*\}"
)
POSITIONAL_SOURCE_RE = re.compile(
    r"^\{(20|25),\s*(\d+),\s*1(?:,\s*\d+)?(?:,\s*(\{[\d,\s]+\}|\d+))?\}$"
)


def load_source(path: Path | None) -> str:
    if path:
        return path.read_text(encoding="utf-8")
    with urllib.request.urlopen(SOURCE_URL) as response:
        return response.read().decode("utf-8")


def difficulty_mask(raw: str | None) -> int:
    mask = 0
    for value in re.findall(r"\d+", raw or ""):
        if value == "3":
            mask |= 1
        elif value == "4":
            mask |= 2
    return mask


def direct_records(raw: str) -> list[tuple[int, int, int]]:
    records: list[tuple[int, int, int]] = []
    for match in KEYED_SOURCE_RE.finditer(raw):
        records.append(
            (int(match.group(1)), int(match.group(2)), difficulty_mask(match.group(3)))
        )
    positional = POSITIONAL_SOURCE_RE.fullmatch(raw)
    if positional:
        records.append(
            (
                int(positional.group(1)),
                int(positional.group(2)),
                difficulty_mask(positional.group(3)),
            )
        )
    return records


def parse_entries(source: str) -> dict[int, str]:
    result: dict[int, str] = {}
    for line in source.splitlines():
        match = ENTRY_RE.match(line)
        if match:
            result[int(match.group(1))] = match.group(2)
    return result


def records_for(
    item_id: int, entries: dict[int, str], seen: set[int] | None = None
) -> list[tuple[int, int, int]]:
    seen = seen or set()
    if item_id in seen:
        return []
    seen.add(item_id)

    raw = entries.get(item_id)
    if raw is None:
        return []
    if raw.isdigit():
        return records_for(int(raw), entries, seen)
    return direct_records(raw)


def generate(source: str) -> str:
    entries = parse_entries(source)
    selected: dict[int, list[tuple[int, int, int]]] = {}

    for item_id in sorted(entries):
        records = []
        for instance, boss, mask in records_for(item_id, entries):
            if instance == 20 or (instance == 25 and boss <= 2):
                record = (instance, boss, mask)
                if record not in records:
                    records.append(record)
        if records:
            selected[item_id] = records

    out = [
        "-- Generated current-phase raid upgrade sources for ChromieCraft.",
        f"-- Source: Hoizame/AtlasLootClassic commit {ATLASLOOT_COMMIT}",
        "-- Input: AtlasLootClassic_Data/source-wrath.lua",
        "-- Scope: Ulduar + Vault of Archavon (Archavon/Emalon), matching Northrend Phase 3.",
        "-- difficultyMask: 1 = 10-player, 2 = 25-player, 3 = both, 0 = unspecified.",
        "",
        "TopFit.upgradeSourceInstances = {",
    ]
    for instance_id in (20, 25):
        name, encounters = INSTANCE_NAMES[instance_id]
        out.extend(
            [
                f"    [{instance_id}] = {{",
                f'        name = "{name}",',
                "        minChromiePhase = 3,",
                "        encounters = {",
            ]
        )
        for index, encounter in enumerate(encounters, 1):
            out.append(f'            [{index}] = "{encounter}",')
        out.extend(["        },", "    },"])
    out.extend(["}", "", "TopFit.upgradeSourceData = {"])

    for item_id, records in selected.items():
        encoded = ", ".join(
            f"{{ {instance}, {boss}, {mask} }}" for instance, boss, mask in records
        )
        out.append(f"    [{item_id}] = {{ {encoded} }},")

    out.extend(["}", ""])
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, help="Local AtlasLoot source-wrath.lua")
    parser.add_argument(
        "--output", type=Path, default=Path("data/upgrade_sources.lua")
    )
    args = parser.parse_args()

    args.output.write_text(generate(load_source(args.input)), encoding="utf-8")


if __name__ == "__main__":
    main()
