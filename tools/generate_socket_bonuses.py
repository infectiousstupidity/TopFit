#!/usr/bin/env python3
"""Generate TopFit socket-bonus stat data from WotLK 3.3.5 SQL exports."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

STAT_KEYS = {
    3: "ITEM_MOD_AGILITY_SHORT",
    4: "ITEM_MOD_STRENGTH_SHORT",
    5: "ITEM_MOD_INTELLECT_SHORT",
    6: "ITEM_MOD_SPIRIT_SHORT",
    7: "ITEM_MOD_STAMINA_SHORT",
    12: "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    13: "ITEM_MOD_DODGE_RATING_SHORT",
    14: "ITEM_MOD_PARRY_RATING_SHORT",
    15: "ITEM_MOD_BLOCK_RATING_SHORT",
    19: "ITEM_MOD_CRIT_RATING_SHORT",
    31: "ITEM_MOD_HIT_RATING_SHORT",
    32: "ITEM_MOD_CRIT_RATING_SHORT",
    35: "ITEM_MOD_RESILIENCE_RATING_SHORT",
    36: "ITEM_MOD_HASTE_RATING_SHORT",
    37: "ITEM_MOD_EXPERTISE_RATING_SHORT",
    38: "ITEM_MOD_ATTACK_POWER_SHORT",
    43: "ITEM_MOD_MANA_REGENERATION_SHORT",
    44: "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    45: "ITEM_MOD_SPELL_POWER_SHORT",
}


def parse_tuple(line: str) -> list[str]:
    values: list[str] = []
    current: list[str] = []
    quoted = False
    escaped = False
    end = len(line) - (2 if line.endswith(("),", ");")) else 1 if line.endswith(")") else 0)

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


def item_columns(sql: str) -> list[str]:
    start = sql.index("CREATE TABLE `item_template`")
    end = sql.index(") ENGINE=", start)
    return re.findall(r"^\s*`([^`]+)`", sql[start:end], flags=re.MULTILINE)


def referenced_bonus_ids(item_sql: str) -> set[int]:
    columns = item_columns(item_sql)
    indexes = {name: columns.index(name) for name in (
        "InventoryType",
        "socketColor_1",
        "socketColor_2",
        "socketColor_3",
        "socketBonus",
    )}
    result: set[int] = set()

    for line in item_sql.splitlines():
        if not line.startswith("("):
            continue
        values = parse_tuple(line)
        if len(values) != len(columns) or int(values[indexes["InventoryType"]] or 0) == 0:
            continue
        socket_colors = (
            int(values[indexes["socketColor_1"]] or 0),
            int(values[indexes["socketColor_2"]] or 0),
            int(values[indexes["socketColor_3"]] or 0),
        )
        if not any(socket_colors):
            continue
        bonus_id = int(values[indexes["socketBonus"]] or 0)
        if bonus_id:
            result.add(bonus_id)

    return result


def lua_stats(stats: dict[str, int]) -> str:
    if not stats:
        return "{}"
    values = ", ".join(f"{key} = {stats[key]}" for key in sorted(stats))
    return "{ " + values + " }"


def generate(item_sql: str, enchant_sql: str) -> str:
    wanted = referenced_bonus_ids(item_sql)
    rows: list[tuple[int, str, dict[str, int], list[str]]] = []

    for line in enchant_sql.splitlines():
        if not line.startswith("("):
            continue
        values = parse_tuple(line)
        enchant_id = int(values[0])
        if enchant_id not in wanted:
            continue

        name = values[14].strip('"').replace('\\\"', '"')
        effects = [int(values[index] or 0) for index in (2, 3, 4)]
        points = [int(values[index] or 0) for index in (5, 6, 7)]
        args = [int(values[index] or 0) for index in (11, 12, 13)]
        stats: dict[str, int] = {}
        tags: list[str] = []

        for effect, point, arg in zip(effects, points, args):
            if not effect:
                continue
            if effect == 5 and point > 0 and arg in STAT_KEYS:
                key = STAT_KEYS[arg]
                stats[key] = stats.get(key, 0) + point
            elif effect == 3:
                match = re.match(r"^\+(\d+) Block Value$", name)
                if match:
                    key = "ITEM_MOD_BLOCK_VALUE_SHORT"
                    stats[key] = stats.get(key, 0) + int(match.group(1))
                else:
                    tags.append("UNSCORED_SOCKET_BONUS")
            elif enchant_id == 2799:
                tags.append("SCALED_STAMINA_SOCKET_BONUS")
            elif enchant_id == 2800:
                tags.append("SCALED_ARMOR_SOCKET_BONUS")
            else:
                tags.append("UNSCORED_SOCKET_BONUS")

        rows.append((enchant_id, name, stats, sorted(set(tags))))

    found = {row[0] for row in rows}
    missing = sorted(wanted - found)
    if missing:
        raise ValueError(f"missing SpellItemEnchantment rows: {missing}")

    rows.sort()
    lines = [
        "-- Generated socket-bonus data for WotLK 3.3.5a.",
        "-- Source item references: AzerothCore item_template.",
        "-- Source enchant values: ForgedWoW/WrathForgedCore SpellItemEnchantment.",
        "-- Only socketBonus IDs referenced by equippable socketed items are emitted.",
        "",
        "TopFit.socketBonusData = {",
    ]
    for enchant_id, name, stats, tags in rows:
        fields = [f"name = {name!r}".replace("'", '"'), f"stats = {lua_stats(stats)}"]
        if tags:
            effects = ", ".join(f'"{tag}"' for tag in tags)
            fields.append(f"effects = {{ {effects} }}")
        lines.append(f"    [{enchant_id}] = {{ " + ", ".join(fields) + " },")
    lines.extend(("}", ""))
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("item_template_sql", type=Path)
    parser.add_argument("spell_item_enchantment_sql", type=Path)
    parser.add_argument("--output", type=Path, default=Path("data/socket_bonuses.lua"))
    args = parser.parse_args()

    output = generate(
        args.item_template_sql.read_text(encoding="utf-8"),
        args.spell_item_enchantment_sql.read_text(encoding="utf-8"),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
