# Top-N complete configurations

TopFit now keeps a small frontier of complete, cap-valid gear configurations instead of discarding
every result except the single global maximum.

## Frontier policy

The runtime keeps at most five results per calculated set.

Results are ordered by:

1. total weighted score, descending;
2. fewer required gear/gem/enchant changes;
3. fewer manual blockers such as banked, unbound BoE, virtual, or modified items; and
4. a deterministic configuration signature.

Exact duplicate outcomes are collapsed. Ring-slot and trinket-slot swaps are normalized, so the
same two rings shown in the opposite order do not consume two result slots.

To avoid five nearly identical gem permutations crowding out genuinely different gear choices,
TopFit keeps at most two modification variants of the same physical gear set.

## Search integration

The legacy recursive optimizer still owns the actual search and its single `bestCombination`.

`alternatives.lua` wraps `SaveCurrentCombination()` and temporarily clears the legacy maximum so
the existing implementation materializes each cap-valid candidate using exactly the same weapon,
cap, set-stat, variant, and greedy-fill logic. The wrapper records that candidate in the Top-N
frontier and immediately restores the real legacy maximum when the candidate is not better.

This avoids copying the large legacy combination builder into a second implementation.

## UI

When more than one configuration exists, compact controls replace the otherwise-unused progress-bar
area after calculation:

- `<` / `>` browse alternatives;
- the center label shows rank and score as a percentage of the best result;
- `Use` makes the displayed configuration the active recommendation.

Selecting an alternative updates the existing item/stat result display. Using it still respects all
existing safety rules: banked items, unbound BoEs, virtual items, and hypothetical gem/enchant
changes remain manual.

## Change summary

Each frontier entry records:

- physical gear changes;
- gem/enchant modification count;
- banked-item count;
- unbound-BoE count;
- virtual-item count; and
- total manual blockers.

These values are retained for later UX such as "near-max with fewer changes" or "budget" views,
without changing the primary score ordering in this step.

## Deliberate boundary

This step does not yet discover upgrades the player does not own. The next milestone can use the
same complete-configuration frontier when evaluating a prospective item: add the candidate item,
rerun optimization, then compare its best resulting complete set against the current frontier.
