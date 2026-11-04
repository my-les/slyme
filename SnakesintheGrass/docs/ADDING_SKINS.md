# Adding skins

All skins live in `SnakesintheGrass/Cosmetics.swift` → `SkinCatalog.all`. The game and the
customize screen read from that list; no rendering code changes are needed.

```swift
Skin(id: "frost", name: "frost", tier: .premium, previewColor: .cyan,
     category: .seasonal, art: .recolor,
     availableFrom: SkinCatalog.date("2026-12-01"), availableUntil: SkinCatalog.date("2027-01-07"))
```

Fields: `id` (lowercase, no spaces; used in asset names and product ids), `name` (shown on the card),
`tier` (`.free` / `.premium`), `category` (`.core`, `.seasonal`, `.branded`, `.textured`; the
customize screen groups in that order), `art` (`.recolor` or `.textured`), and an optional
`availableFrom` / `availableUntil` window. Outside the window a skin is hidden unless the player
already owns it. Removed ids that are still saved on a device fall back to `og` automatically.

## The 14 pieces

Each skin needs 14 images named `skin_<id>_<piece>`, one imageset each in
`SnakesintheGrass/Assets.xcassets/skin_<id>_<piece>.imageset/`:

head_up, head_down, head_left, head_right,
body_horizontal, body_vertical, body_topleft, body_topright, body_bottomleft, body_bottomright,
tail_up, tail_down, tail_left, tail_right

Size: 40×40 px PNG with transparency (same as the og pieces), registered as the `1x` universal
image. Pieces must tile edge to edge and keep the og orientation (look at the og imagesets, e.g.
`head_right.imageset`). If a piece is missing the og piece is drawn instead.

## Recolor skin (generated from og art)

1. Add an entry to `tools/skins.json`: `{"id": "mint", "body": "#3EE6A8"}`
   (optional `"light": true` for dark eyes on pale bodies, `"alpha": 0.6` for translucency).
2. Run `python3 tools/recolor_skins.py mint` from the repo root (needs Pillow). No args = all.
3. Add the `Skin(... art: .recolor)` entry to `SkinCatalog.all`.

## Textured / branded skin (hand-made art)

1. Draw the 14 pieces at 40×40 using the og pieces as templates.
2. Create the 14 imagesets `skin_<id>_<piece>.imageset` (PNG + Contents.json, like the generated
   ones). Do not add the skin to `tools/skins.json`, or the script will overwrite your art.
3. Add `Skin(... category: .textured /* or .branded */, art: .textured)` to `SkinCatalog.all`.

## StoreKit product id

Premium skins sell as non-consumables with product id `com.ysdwysd.skin.<id>`
(`EntitlementStore.productID(skinID:)`). Create the matching product in App Store Connect.
Maps use `com.ysdwysd.map.<id>`.
