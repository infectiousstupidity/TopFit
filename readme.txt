TopFit - ChromieCraft fork
===========================

This repository is a ChromieCraft-focused continuation of TopFit for World of Warcraft 3.3.5a
(Interface 30300).

The long-term goal is an in-game optimizer that can:

- choose the best complete gear set from items you own;
- evaluate caps and interacting gear choices as a whole set;
- optimize gems and enchants;
- return multiple useful alternative configurations; and
- evaluate prospective upgrades by adding an item and re-running the complete optimization.

Current baseline
----------------

The useful original TopFit foundations are retained: inventory scanning, item caching, stat-weight
scoring, hard/soft caps, whole-set search, weapon/offhand constraints, virtual items, and weight
import/export.

This fork previously contained several data files tailored to a different private realm. They are
not valid ChromieCraft defaults and have been removed from the runtime baseline. Built-in presets,
automatic talent-rating adjustments, and static proc fallbacks are therefore intentionally disabled
until they are rebuilt from verified WotLK 3.3.5a / ChromieCraft data.

Actual gems and enchants already present on items are still read from live item tooltips.

Gem and enchant candidates
--------------------------

The addon now has a separate ChromieCraft-aware candidate model for gems and deterministic enchants.
It understands physical socket fit versus socket-bonus matching, hybrid/prismatic color contribution,
meta activation requirements, profession skill requirements, Jewelcrafter gem limits, item/slot
restrictions, and ChromieCraft progression gates.

Current Phase 3 includes Northrend rare gems, Jewelcrafter Dragon's Eyes, Ulduar Stormjewels, and
Wrath meta gems. Patch 3.2 / Trial of the Crusader epic gems are present in the data but remain
phase-gated until Phase 4.

Proc, on-use, movement, and similar non-static enchant effects are preserved as explicit effect tags
rather than converted into guessed average stat values.

Item socket metadata
--------------------

Original socket colors and socket-bonus IDs are generated from AzerothCore's 3.3.5 `item_template`
data instead of reconstructed from rendered tooltips. The runtime table covers 5,944 equippable
socketed items and uses a compact packed-number representation that is decoded only for items TopFit
actually scans.

This lets already-gemmed items retain their original red/yellow/blue/meta socket layout, which is
required before whole-set re-gemming can be correct. Existing SavedVariables cache entries are
hydrated with the generated metadata automatically.

Owned inventory
---------------

TopFit now optimizes across equipped gear, bags, and a persistent snapshot of the character bank.
Open the bank once after installing or updating the addon so TopFit can record its equippable
contents. The snapshot is refreshed while the bank is open and remains available after it is closed.

Unbound Bind-on-Equip items are valid owned candidates, but TopFit will never auto-equip a
recommended set containing one because doing so may bind a valuable item. Banked items likewise
remain recommendations only until they are withdrawn.

Not implemented yet
-------------------
- wiring gem/enchant candidate sets and socket metadata into the whole-set optimizer;
- Top-N alternative gear sets;
- source-aware upgrade paths;
- spec-specific simulation models.

Development
-----------

The addon targets Lua 5.1. GitHub Actions checks Lua syntax, formatting, Luacheck, unit tests,
whitespace, secret scanning, and Semgrep.

Run the pure Lua tests from the repository root with:

    for test_file in tests/test_*.lua; do lua5.1 "$test_file"; done

See docs/chromiecraft-baseline.md for the baseline code review and keep/remove decisions.
See docs/candidate-model.md for gem/enchant model rules and data provenance.
See docs/item-socket-data.md for generated socket metadata and regeneration instructions.

Credits
-------

Original TopFit by Mirroar, continued by Zae. This fork retains the original project history and
credits while adapting the addon for ChromieCraft.
