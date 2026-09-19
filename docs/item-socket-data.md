# Generated item socket data

TopFit needs the original socket layout of an item even after gems are installed. The 3.3.5 tooltip
API does not reliably expose every original socket color once an item is already filled, so the
addon ships a generated lookup from AzerothCore's `item_template`.

## Source

The current generated file is pinned to AzerothCore commit:

`3df225f8cb890379816794c6699cdc891d738e79`

Source table:

`data/sql/base/db_world/item_template.sql`

The generator keeps equippable rows with at least one socket and records only:

- item entry ID;
- `socketColor_1`;
- `socketColor_2`;
- `socketColor_3`; and
- `socketBonus`.

That currently produces 5,944 item rows.

## Runtime format

To avoid one Lua table per item, `data/item_sockets.lua` stores one packed number per item:

`c1 + c2*16 + c3*256 + socketBonus*4096`

3.3.5 socket masks are:

- 1 = META
- 2 = RED
- 4 = YELLOW
- 8 = BLUE
- 14 = PRISMATIC

`socket_metadata.lua` decodes the packed value only when TopFit actually scans that item.

Cached item tables receive:

- `baseSocketColors`: ordered original socket colors;
- `socketBonusID`: SpellItemEnchantment ID for the item's socket bonus.

Profession-added sockets are not part of base metadata. Eternal Belt Buckle, Socket Bracer, and
Socket Gloves are modeled as enchant-candidate effects instead.

## Regeneration

Download or check out the pinned AzerothCore `item_template.sql`, then run:

```bash
python tools/generate_item_sockets.py /path/to/item_template.sql \
  --source-ref 3df225f8cb890379816794c6699cdc891d738e79
```

The generator uses only Python's standard library and writes `data/item_sockets.lua` by default.
Commit the regenerated file together with any source-ref change so data provenance remains explicit.
