# ChromieCraft baseline review

This fork contains useful TopFit 3.3.5a optimizer code, but it also accumulated data and features
for a different private realm. The baseline keeps the parts that are useful for the planned
ChromieCraft gear optimizer and removes inputs that can silently produce wrong recommendations.

## Keep

- `inventory.lua`: bag/equipped-item discovery, item-link cache, tooltip scanning, socket/enchant
  parsing, and item-to-slot mapping.
- `calculation.lua`: whole-set search, pruning, cap handling, duplicate-item checks, weapon/offhand
  constraints, forced items, and frame-yielded calculation.
- `plugins/virtual_items.lua`: useful foundation for future "what if I had this item?" upgrade
  evaluation.
- `import.lua`: Pawn/TopFit/AskMrRobot weight import is still useful for the first stat-weight
  scoring model.
- `procparser.lua`: live tooltip parsing is retained. Without a verified proc database, effects
  lacking enough information remain unscored instead of borrowing realm-specific values.
- `simc_export.lua`: retained for now because it is an independent diagnostic/export tool and also
  contains the current weapon-speed tooltip parser used by item scoring.
- `tooltip.lua`, `frame.lua`, `options.lua`, `plugin.lua`, and `plugins/stats.lua`: retained as
  the working UI while the optimizer is evolved incrementally.
- `Libs/`: vendored dependencies; leave untouched.

## Remove from the runtime baseline

- `presets.lua`: its cap conversions and weights were changed for a level-60 private realm and are
  not safe ChromieCraft defaults.
- `talentbonuses.lua`: it explicitly models that realm's custom talent trees and rating
  conversions. ChromieCraft-specific/spec-specific talent handling should be rebuilt from verified
  3.3.5a rules.
- `simc_proc_data.lua`: contains realm-specific proc values/cooldowns. The live tooltip parser is
  safer than silently applying the wrong fallback metadata.
- `enchant_ids.lua`: no first-party runtime code reads `TopFit.enchantIDs`.
- `gem_ids.lua`: its only runtime consumer was the legacy empty-socket estimate. That estimate
  cannot correctly model off-color gems, socket-bonus tradeoffs, meta activation, profession-only
  gems, or whole-set caps, so it is disabled until the real gem optimizer is implemented.

Git history retains all removed data if any part is worth recovering later.

## Baseline behavior

`chromiecraft.lua` deliberately supplies empty preset, talent-bonus, and gem-candidate data. This
keeps the existing UI and optimizer stable without applying data from another realm. Actual gems
and enchants already present on owned items are still parsed from their live item tooltips.

## Owned inventory policy

The optimizer now treats equipped items, bag items, and the last scanned character-bank contents as
owned gear. The bank cannot be queried remotely by addons, so the player must open it once to create
the snapshot; bank events keep that snapshot current while the bank is accessible.

Unbound Bind-on-Equip gear is included in optimization. It is not auto-equipped, because equipping
it can bind the item. Banked recommendations are also not auto-equipped. Both remain visible in the
calculated best set so ownership and safety are separate concerns.

WoW 3.3.5's `GetInventoryItemsForSlot(slot, table)` returns packed physical locations mapped to
item IDs. TopFit uses that API for player-specific equip eligibility and stores full item links for
bank entries so enchants and gems remain part of the item identity.

## Test boundary

The unit tests cover pure optimizer and ownership rules that can run outside the WoW client:

- hard/soft active-cap detection;
- multiple caps on one stat;
- unreachable-cap pruning;
- duplicate physical-item detection;
- class armor mapping;
- bank snapshot merging and physical-copy identity;
- manual-equip blockers for virtual, banked, and unbound BoE recommendations.

WoW API/tooltip integration remains an in-client integration-test concern.

## Deferred on purpose

These are required for the final addon, but they should be separate tasks rather than mixed into
the baseline cleanup:

1. a verified gem/enchant candidate model with profession and meta requirements;
2. Top-N complete gear configurations rather than only one winner;
3. source-aware upgrade candidates and full re-optimization per candidate;
4. spec-aware scoring beyond fixed stat weights;
5. generated/verified ChromieCraft item and source data;
6. replacement or simplification of the legacy UI after optimizer behavior is covered.
