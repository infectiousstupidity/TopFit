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

Gem/enchant variant optimization
--------------------------------

Each owned physical item is now expanded into a bounded set of useful gem/enchant variants before
the whole-set search runs. The frontier retains the current setup, strongest weighted choices,
cap-relevant choices, socket-color/meta alternatives, Jewelcrafter/non-Jewelcrafter alternatives,
and the current gem/enchant where known.

The whole-set validator enforces meta activation and global Jeweler's Gem limits across all selected
items. Physical identity is preserved independently of the hypothetical item link, so one ring or
trinket cannot be used twice merely by choosing two different variants.

Socket bonuses use a generated WotLK bonus-stat table. Unsupported bonus IDs and non-static effects
such as proc enchants or percentage meta effects remain explicitly unscored rather than guessed.
Recommendations containing gem/enchant changes are never auto-equipped.

This is intentionally a bounded frontier, not an exhaustive proof over every possible gem/enchant
permutation. That keeps the 3.3.5 client responsive while preserving the dimensions that can change
the optimum under the current stat-weight/cap model.

Alternative complete configurations
-----------------------------------

TopFit now retains up to five complete cap-valid results instead of discarding everything except the
single best set. Exact duplicates and ring/trinket slot swaps are collapsed, and at most two
gem/enchant variants of the same physical gear set are retained so tiny modification differences do
not crowd out genuinely different gear choices.

After a calculation, compact < / > controls let you browse alternatives and see each result as a
percentage of the best score. "Use" makes the displayed configuration the active recommendation while
preserving all existing safety rules for banked gear, BoEs, virtual items, and hypothetical
gem/enchant changes.

Source-aware upgrade paths
--------------------------

The Upgrades plugin can scan currently available Phase 3 raid drops and measure their real whole-set
gain. It first recalculates an owned-only baseline, then injects one prospective item at a time and
reruns the complete gear/gem/enchant optimizer.

Current generated sources cover Ulduar plus Archavon and Emalon in Vault of Archavon. Results show
the item, whole-set score gain/percentage, and raid/encounter/difficulty. Clicking a result previews
the complete configuration that makes use of that item.

Candidate discovery is bounded before the expensive reruns: TopFit keeps the strongest weighted
choices per slot plus active-cap specialists, then fully re-optimizes each survivor. Configured
legacy virtual items are suppressed during the scan so they cannot contaminate the owned baseline.

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
- broader upgrade-source generation for emblem vendors, crafted/reputation/quest/PvP gear;
- spec-specific simulation models for currently unscored proc/meta effects;
- an exhaustive optimizer mode if profiling shows it can be made safe on the 3.3.5 client.

Development
-----------

The addon targets Lua 5.1. GitHub Actions checks Lua syntax, formatting, Luacheck, unit tests,
whitespace, secret scanning, and Semgrep.

Run the pure Lua tests from the repository root with:

    for test_file in tests/test_*.lua; do lua5.1 "$test_file"; done

See docs/chromiecraft-baseline.md for the baseline code review and keep/remove decisions.
See docs/candidate-model.md for gem/enchant model rules and data provenance.
See docs/item-socket-data.md for generated socket metadata and regeneration instructions.
See docs/variant-optimizer.md for the bounded gem/enchant search and its correctness boundary.
See docs/alternatives.md for Top-N result retention and browsing.
See docs/upgrade-planner.md for source-aware full-set upgrade evaluation.

Credits
-------

Original TopFit by Mirroar, continued by Zae. This fork retains the original project history and
credits while adapting the addon for ChromieCraft.
