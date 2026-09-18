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

Not implemented yet
-------------------

- bank inventory snapshots;
- automatic gem/enchant combination optimization;
- meta-gem and profession restriction solving;
- Top-N alternative gear sets;
- source-aware upgrade paths;
- spec-specific simulation models.

Development
-----------

The addon targets Lua 5.1. GitHub Actions checks Lua syntax, formatting, Luacheck, unit tests,
whitespace, secret scanning, and Semgrep.

Run the pure calculation tests from the repository root with:

    lua5.1 tests/test_calculation.lua

See docs/chromiecraft-baseline.md for the baseline code review and keep/remove decisions.

Credits
-------

Original TopFit by Mirroar, continued by Zae. This fork retains the original project history and
credits while adapting the addon for ChromieCraft.
