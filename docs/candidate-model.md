# Gem and enchant candidate model

This layer defines what gem/enchant choices are legal and available. It deliberately does not yet
change TopFit's whole-set search. Keeping candidate correctness separate from search integration
makes socket/meta/profession rules testable before the search space grows.

## Progression

`TopFit.chromiecraftPhase` is currently `3`, matching ChromieCraft's Ulduar / Tier 8 release.

Candidate records may declare `minChromiePhase`:

- Phase 1: Northrend rare gems, Dragon's Eyes, Wrath meta gems, and baseline Wrath enchants.
- Phase 3: Ulduar Stormjewels and Ulduar-specific weapon enchants such as Blade Ward/Blood Draining.
- Phase 4: normal epic Cardinal Ruby / King's Amber / Majestic Zircon / Ametrine /
  Dreadstone / Eye of Zul gems and Nightmare Tear.

Reference: https://chromiecraft.com/en/progression/

## Socket rules

The model separates two concepts that the old TopFit empty-socket shortcut conflated:

1. **Physical fit:** any non-meta gem can be placed in any non-meta colored socket.
2. **Socket-bonus match:** a gem only satisfies a red/yellow/blue socket when its color contribution
   includes that color. Hybrid gems contribute both colors; prismatic gems contribute red, yellow,
   and blue. Meta gems only fit meta sockets.

`BuildGemCandidateSets()` therefore exposes every physically legal candidate for each socket; it
does not prematurely restrict candidates to matching colors.

## Meta gems

Meta requirements are represented as data instead of special cases in the optimizer. Current
definitions include common Wrath metas such as Chaotic, Relentless, Austere, Insightful, Ember, and
Revitalizing.

`ValidateGemLoadout()` counts color contribution across the supplied complete loadout and rejects an
inactive meta.

## Profession restrictions

This addon targets the 3.3.5 client, so profession detection uses the Wrath skill-frame APIs
`GetNumSkillLines()` and `GetSkillLineInfo()`. It does not use later-client profession APIs.

Profession-restricted candidates use the 3.3.5 skill-line IDs:

- Blacksmithing: 164
- Leatherworking: 165
- Tailoring: 197
- Engineering: 202
- Enchanting: 333
- Jewelcrafting: 755
- Inscription: 773

Dragon's Eyes require Jewelcrafting 350 and share a three-item `JEWELERS_GEMS` limit. Ring enchants
require Enchanting 400. Blacksmithing sockets and Engineering/Leatherworking enhancements carry their
own skill requirements.

## Enchant effects

Static stats are stored in `stats`. Effects that are not equivalent to permanent stats are stored
in `effects` instead. Examples include Tuskarr's movement speed, Hyperspeed Accelerators,
Berserking, Black Magic, Blade Ward, and Blood Draining.

This prevents the old behavior of turning procs into guessed average stats before a spec-aware model
exists.

## Data provenance

The ordinary 3.3.5 rare/epic gem stat vectors and Dragon's Eye vectors are carried forward from
TopFit's original 3.3.5 data. Candidate semantics and phase gating are new. Stormjewels are curated
explicitly; the historical table's Bold Stormjewel ID typo (`45962`) is corrected to `45862`.

The enchant list is intentionally curated rather than restoring the removed giant enchant table. It
contains deterministic Wrath endgame choices plus profession enhancements and explicitly tagged
non-static effects.

AzerothCore's item/DBC structures remain the intended source for the later generated item socket and
source database:

- `item_template.Socket[]` describes item socket colors.
- `item_template.socketBonus` references SpellItemEnchantment.
- `item_template.GemProperties` references GemProperties.

## Item socket metadata

The original socket-layout blocker is now handled by generated AzerothCore data. Cached item tables
receive `baseSocketColors` and `socketBonusID` even when every original socket is already filled,
so solver code no longer has to infer original colors from the rendered tooltip.

Profession-added sockets such as Eternal Belt Buckle, Socket Bracer, and Socket Gloves remain
candidate effects. They are intentionally not baked into base item metadata.

## Optimizer integration

`variants.lua` now builds a bounded per-item frontier from these candidates and the generated
`baseSocketColors`. `variant_optimizer.lua` feeds those variants into TopFit's whole-set search
while preserving physical-item identity and enforcing meta/Jewelcrafter constraints across the
complete selected set.

The frontier is deliberately bounded. It preserves current, high-score, cap-relevant, color/meta,
and profession-constraint alternatives, but it is not an exhaustive enumeration of every possible
gem/enchant permutation. Non-static effects remain explicitly unscored until spec-aware models exist.
