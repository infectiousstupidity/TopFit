# UI stabilization

This pass treats an unconfigured weight set as a real application state instead of letting the
optimizer silently run with a score of zero.

## Plugin tabs

Plugin frames are still registered independently, but once the progress frame exists the plugin
manager eagerly fires each plugin's existing `OnShow` initializer. This keeps the old plugin APIs
while removing the fragile "first click must initialize the frame" behavior that could leave
Virtual Items or Upgrades visibly blank.

The selected tab now keeps its highlight/font state after the mouse leaves it.

## Weight readiness

A set is calculation-ready only when it has at least one numeric non-zero weight. Positive and
negative weights are both valid; an empty table or rows whose values are all zero are not.

When a set is not ready:

- Start is disabled;
- the score area reads **No weights configured** instead of a misleading score of zero;
- the Weights & Caps panel shows an empty-state instruction when it contains no rows;
- an **Import...** action is available next to **Add stat...**;
- the Upgrades scan button is disabled with the same reason; and
- the upgrade planner also rejects a programmatic scan attempt defensively.

## Legacy layout fixes

The stabilization adapter avoids rewriting the large legacy frame/stats files:

- the historical duplicate global frame name used by **Add stat...** is intercepted during plugin
  construction and changed to `TopFit_ProgressFrame_addStatButton`;
- the narrow summary checkbox label is shortened from **Force armor type** to
  **Class armor only**, with the existing tooltip retaining the full explanation.

This file is intentionally an adapter around the legacy UI. Once the old frame is replaced, these
compatibility wrappers can be removed as a unit.
