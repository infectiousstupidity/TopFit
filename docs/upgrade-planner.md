# Source-aware upgrade planner

TopFit can now evaluate prospective current-phase raid drops by adding **one hypothetical item at a
time** and rerunning the same complete gear/gem/enchant optimizer used for owned gear.

The reported gain is therefore not a per-item score delta. It is:

`best complete set with candidate - best complete owned set`

That allows caps, weapon combinations, socket choices, meta activation, Jewelcrafter limits, and
other whole-set interactions to change around the prospective item.

## Source data

`data/upgrade_sources.lua` is generated from the pinned AtlasLootClassic Wrath source database:

- repository: `Hoizame/AtlasLootClassic`
- commit: `8e99341e4e779328460bf7684c0d5b22ce50ddf1`
- input: `AtlasLootClassic_Data/source-wrath.lua`

The current generated scope is deliberately aligned with ChromieCraft Northrend Phase 3:

- Ulduar
- Vault of Archavon: Archavon
- Vault of Archavon: Emalon

ChromieCraft lists Phase 3 as Tier 8 / Ulduar + Emalon. Koralon and later raids are excluded.

The compact runtime format stores item ID -> instance/encounter/difficulty tuples. The addon decodes
those into source records only when needed.

Regenerate with:

```bash
python tools/generate_upgrade_sources.py
```

The generator downloads the pinned source by default, or accepts a local AtlasLoot source file:

```bash
python tools/generate_upgrade_sources.py --input /path/to/source-wrath.lua
```

## Candidate discovery

The source table contains items for every class/spec, so TopFit first asks the 3.3.5 client for item
data and removes entries the current character cannot equip.

Item data is requested over several frame passes because `GetItemInfo` may be cold for raid items
that have not been seen during the current client session.

Configured legacy "Virtual Items" are suppressed during an upgrade scan. Otherwise the owned
baseline could already contain hypothetical gear and the measured gain would be meaningless.

## Bounded shortlist

Running the full combinatorial optimizer for every source-table item would be unnecessarily slow.
Before full re-optimization, each resolved candidate is expanded through the existing bounded
gem/enchant variant generator.

Per equipment slot TopFit retains:

- the top three candidates by current weighted score; and
- the top candidate for every active capped stat.

Those candidates are deduplicated and bounded to 45 full optimizer runs. Cap specialists are
protected from the global weighted-score truncation.

This is candidate **discovery pruning**; every candidate that survives it receives a complete
optimizer rerun.

## Full evaluation

The scan runs in this order:

1. recalculate an owned-only baseline;
2. inject one prospective candidate as one hypothetical physical item;
3. rerun complete optimization;
4. keep the result only if the winning complete set actually uses that candidate;
5. record positive whole-set gain and source metadata;
6. repeat for the next candidate;
7. restore the owned baseline/Top-N alternatives after the scan.

Prospective items use source `upgrade` and are always recommendation-only. They are never passed
to auto-equip.

## UI

The **Upgrades** plugin tab provides:

- `Scan Phase 3 upgrades`;
- loading/evaluation progress;
- ranked positive upgrades;
- whole-set score gain and percentage gain;
- raid / encounter / difficulty source text.

Clicking a result previews the resulting complete configuration in the existing gear/stat panel.

## Deliberate limits

This first source dataset is raid-focused. The source model is designed to accept additional
generators later for:

- Emblem vendors;
- crafted gear;
- reputation rewards;
- quests;
- PvP gear; and
- later ChromieCraft phases.

Also, upgrades containing proc/meta effects that the current stat-weight scorer cannot value remain
subject to the same explicit unscored-effect limitation as owned gear.
