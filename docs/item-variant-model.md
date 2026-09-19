# Item variant model

The optimizer eventually needs to choose three things independently:

1. the owned base item;
2. a normal enchant/tinker for that slot; and
3. gems for the item's original sockets plus any independent added socket.

Creating every combination eagerly is too large, so `variants.lua` exposes the dimensions and can
compose one selected combination on demand.

## Stackable socket modifications

Blacksmithing Socket Bracer and Socket Gloves stack with normal enchants in Wrath. Eternal Belt
Buckle is handled by the same model. These live in `TopFit.socketModificationCandidates`, separate
from `TopFit.enchantCandidates`.

An added prismatic socket does **not** become part of the item's original socket-bonus requirement.
The socket bonus is checked only against `baseSocketColors`.

## Concrete variant fields

`BuildItemVariant()` returns:

- `staticStats`: base item stats + non-meta gem stats + enchant stats + active fixed socket bonus;
- `socketColors`: original sockets plus the selected independent added socket;
- `socketBonusActive` and `socketBonus`;
- `colorCounts`: red/yellow/blue contribution for whole-character meta checks;
- `uniqueGemCounts`: local usage such as Jeweler's Gems;
- `metaGems`: meta candidates kept conditional until the whole character is known;
- `effects`: non-static enchant/socket-bonus effects that are not converted into fake stats;
- original item proc metadata.

Meta-gem stats/effects are intentionally not added to `staticStats` locally. A meta gem is only
active after the whole equipped set satisfies its requirement.

## Choice traversal

`GetItemVariantChoices()` returns normal enchant choices, base socket gem choices, and each
socket-modification branch with its corresponding extra socket candidate set. It does not enumerate
the Cartesian product. The whole-set optimizer should traverse these dimensions and prune using the
active weights/caps.
