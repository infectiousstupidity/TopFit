#!/usr/bin/env python3
"""Generate TopFit socket-bonus stat data from Rawr's WotLK switch table."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

STAT_MAP = {
    "Agility": "ITEM_MOD_AGILITY_SHORT",
    "ArmorPenetrationRating": "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    "AttackPower": "ITEM_MOD_ATTACK_POWER_SHORT",
    "BlockRating": "ITEM_MOD_BLOCK_RATING_SHORT",
    "BlockValue": "ITEM_MOD_BLOCK_VALUE_SHORT",
    "CritRating": "ITEM_MOD_CRIT_RATING_SHORT",
    "DefenseRating": "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    "DodgeRating": "ITEM_MOD_DODGE_RATING_SHORT",
    "ExpertiseRating": "ITEM_MOD_EXPERTISE_RATING_SHORT",
    "HasteRating": "ITEM_MOD_HASTE_RATING_SHORT",
    "HitRating": "ITEM_MOD_HIT_RATING_SHORT",
    "Intellect": "ITEM_MOD_INTELLECT_SHORT",
    "Mp5": "ITEM_MOD_MANA_REGENERATION_SHORT",
    "ParryRating": "ITEM_MOD_PARRY_RATING_SHORT",
    "Resilience": "ITEM_MOD_RESILIENCE_RATING_SHORT",
    "SpellPower": "ITEM_MOD_SPELL_POWER_SHORT",
    "Spirit": "ITEM_MOD_SPIRIT_SHORT",
    "Stamina": "ITEM_MOD_STAMINA_SHORT",
    "Strength": "ITEM_MOD_STRENGTH_SHORT",
}

SOURCE_REPO = "akindle/rawr-archive"
SOURCE_COMMIT = "41dbc494779205981ceed7ab5d15ba3d46a7bc19"
SOURCE_PATH = "issues/14256/2258"


def generate(source: str) -> str:
    marker = "Hugeass switch to deal with all the socket bonuses"
    start = source.index(marker)
    end = source.index("#endregion", start)
    region = source[start:end]

    entries: list[tuple[int, dict[str, float]]] = []
    for match in re.finditer(r'case\s+"(\d+)":([\s\S]*?)break;', region):
        bonus_id = int(match.group(1))
        stats: dict[str, float] = {}
        for stat_match in re.finditer(r"stats\.([A-Za-z0-9_]+)\s*\+=\s*([0-9.]+);", match.group(2)):
            token = STAT_MAP.get(stat_match.group(1))
            if token:
                value = float(stat_match.group(2))
                stats[token] = stats.get(token, 0.0) + value
        if stats:
            entries.append((bonus_id, stats))

    entries.sort()
    lines = [
        "-- Generated socket-bonus stat data. Do not edit by hand.",
        f"-- Source repository: https://github.com/{SOURCE_REPO}",
        f"-- Source commit: {SOURCE_COMMIT}",
        f"-- Source path: {SOURCE_PATH} (Rawr WotLK socket-bonus switch)",
        "-- Unsupported socketBonus IDs remain explicitly unscored by the variant optimizer.",
        "",
        "TopFit.socketBonusStats = {",
    ]
    for bonus_id, stats in entries:
        rendered = []
        for token in sorted(stats):
            value = stats[token]
            number = str(int(value)) if value.is_integer() else str(value)
            rendered.append(f'["{token}"] = {number}')
        lines.append(f"    [{bonus_id}] = {{ {', '.join(rendered)} }},")
    lines.extend(["}", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("rawr_source", type=Path)
    parser.add_argument("--output", type=Path, default=Path("data/socket_bonuses.lua"))
    args = parser.parse_args()

    output = generate(args.rawr_source.read_text(encoding="utf-8-sig"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
