# Gem/enchant variant optimizer

TopFit now evaluates gem/enchant changes as part of the complete gear-set search rather than as an
independent per-slot afterthought.

## Search shape

A physical item is expanded into hypothetical variants before the legacy whole-set recursion runs.
Each variant has:

- the same physical ownership/location identity as the source item;
- a valid hypothetical 3.3.5 item link with enchant/gem fields replaced;
- recomputed permanent stat totals;
- ordered gem IDs and color contributions;
- Jewelcrafter unique-group counts;
- any meta gem carried by the variant;
- socket-bonus state; and
- flags for effects that are not yet scoreable.

Physical identity is separate from the item link. Two variants of the same ring are still one
physical ring and cannot occupy both ring slots.

## Bounded frontier

Enumerating every legal gem and enchant across every owned item would multiply the legacy gear
search into an impractical search space. TopFit therefore keeps a bounded frontier per item.

Candidate selection preserves:

- the exact current item setup;
- highest weighted gem choices;
- highest weighted color-matching choices;
- best choices for every color-contribution class, including hybrids needed for meta activation;
- best contributors to every active cap;
- Jewelcrafter and non-Jewelcrafter constraint classes;
- the current gem;
- the current enchant, including an unknown enchant's parsed static stats; and
- distinct final color/meta/cap signatures.

The gem socket beam is also bounded and keeps separate active-cap values in its signature so a
lower raw-score hit/expertise/etc. choice is not discarded merely because it shares the same color
with a stronger uncapped gem.

This is a responsive approximation, not a mathematical proof that every possible gem/enchant
permutation was enumerated.

## Whole-set constraints

After a complete gear combination is assembled, TopFit validates constraints that cannot be decided
correctly per item:

- total red/yellow/blue contribution for meta activation;
- all selected meta-gem requirements; and
- global unique groups such as the three-Jeweler's-Gems limit.

If a newly discovered best set violates one of these rules, the legacy best result is rolled back
and search continues from the previous valid maximum.

## Socket bonuses

`data/socket_bonuses.lua` contains generated WotLK socket-bonus stat vectors sourced from Rawr's
historical WotLK importer:

- repository: `akindle/rawr-archive`
- commit: `41dbc494779205981ceed7ab5d15ba3d46a7bc19`
- source path: `issues/14256/2258`

`tools/generate_socket_bonuses.py` regenerates that table.

Only bonus IDs with an explicit historical stat mapping are scored. Unknown IDs remain unscored;
TopFit does not infer a number from the ID or invent a value.

## Effects not reduced to permanent stats

Candidate records can carry `effects` for mechanics such as Berserking, Black Magic, movement
speed, activated Engineering effects, mana procs, or percentage-based meta effects. Variants that
contain one of these effects are marked as having an unscored effect.

The current stat-weight optimizer does not invent an average value for those mechanics. A later
spec-aware scoring layer can consume the same variant structure without changing inventory or
socket legality.

## Applying recommendations

Variant item links are hypothetical: they describe the recommended enchant/gem fields but the
physical item in the player's bags/bank is unchanged.

For that reason, a winning set that requires modification is recommendation-only. TopFit refuses
to auto-equip it until the required gem/enchant changes have actually been applied.

## Correctness boundary

This step makes gem/enchant choices participate in whole-set cap and meta interactions, which is a
substantial improvement over the removed empty-socket shortcut. Remaining limitations are explicit:

1. the frontier is bounded rather than exhaustive;
2. non-static effects are not yet assigned spec-aware values;
3. unknown current gems make meta-color validation conservative; and
4. unsupported socket-bonus IDs are unscored.

These are separate future tasks rather than hidden assumptions in the optimizer.
