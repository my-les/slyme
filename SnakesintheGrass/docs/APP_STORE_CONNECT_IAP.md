# slyme in-app purchases: App Store Connect setup

All products are **Non-Consumable**. Product ids must match exactly; the app builds them in
`EntitlementStore` (`productID(skinID:)`, `productID(mapID:)`, `pack*ID`). Local testing uses
`slyme.storekit` (same ids and prices), selected in the shared `slyme` scheme (Run > Options).

Nothing here has been created in App Store Connect yet.

## Products to create (App > Monetization > In-App Purchases > +)

| Reference name | Product ID | Type | Price (USD, pick the matching tier) | Display name | Description (max 55 chars) |
|---|---|---|---|---|---|
| skin duo blue | com.ysdwysd.skin.duo | Non-Consumable | $0.99 | duo blue skin | A bright cyan snake skin. |
| skin gold | com.ysdwysd.skin.gold | Non-Consumable | $0.99 | gold skin | A gold snake skin. |
| skin ghost | com.ysdwysd.skin.ghost | Non-Consumable | $0.99 | ghost skin | A see-through ghost snake skin. |
| skin indigo | com.ysdwysd.skin.indigo | Non-Consumable | $0.99 | indigo skin | A deep indigo snake skin. |
| map pillars | com.ysdwysd.map.pillars | Non-Consumable | $1.99 | pillars map | A board full of pillars to dodge. |
| map box | com.ysdwysd.map.box | Non-Consumable | $1.99 | box map | Walled board: hit the edge and the run ends. |
| map cross | com.ysdwysd.map.cross | Non-Consumable | $1.99 | cross map | A cross of blocks splits the board. |
| map yard | com.ysdwysd.map.yard | Non-Consumable | $1.99 | yard map | Fenced yard: hit the edge and the run ends. |
| pack skins | com.ysdwysd.pack.skins | Non-Consumable | $2.99 | all skins | Unlocks every paid snake skin. |
| pack maps | com.ysdwysd.pack.maps | Non-Consumable | $3.99 | all maps | Unlocks every paid map. |
| pack everything | com.ysdwysd.pack.everything | Non-Consumable | $5.99 | everything | Unlocks every paid skin and map. |

Notes:
- Set the price schedule base country to United States and let Apple auto-equalize other storefronts.
- Packs are separate products. Someone who already owns some singles still pays the full pack price;
  consider saying so in the pack description or lowering the pack later. Apple does not prorate.
- Family Sharing: optional per product (off in `slyme.storekit`). Turning it on is a one-way switch.
- New skins/maps: add a product `com.ysdwysd.skin.<id>` / `map.<id>`, add it to `slyme.storekit`.
  Packs cover new premium items automatically (code-side); mention that in pack descriptions only if you mean it.

## Review screenshot (required per product)

Each IAP needs a **Review Information > Screenshot** (any device size, e.g. 1290x2796 from an iPhone
6.9" simulator) showing the item in the app before purchase. Use the purchase sheet:
- Skins: customize > skins > tap the locked skin (sheet shows name + price).
- Maps: customize > maps > tap the locked map.
- Packs: the same sheet, which shows the pack line ("unlock all skins $2.99").
Add review notes: "Customize > tap any locked item. Restore purchases is on the customize screen."

## Checklist to ship IAPs with the next version

1. **Agreements, Tax, and Banking**: Paid Apps agreement active (Account Holder must accept), bank
   account and tax forms complete. IAPs stay "Missing Metadata"/unbuyable until this is done.
2. Create the 11 products above with price, at least one localization (English US), review
   screenshot and review notes. Status should become **Ready to Submit**.
3. Bump the version (current live 1.1 > e.g. 1.2) and build number, archive, upload.
4. On the new version page, in **In-App Purchases and Subscriptions**, add all 11 products so they
   are reviewed with that build. (First-time IAPs must be submitted with an app version.)
5. Sandbox test on a real device: Users and Access > Sandbox > create a tester; on device
   Settings > Developer > Sandbox Apple Account. Test buy single, buy pack, cancel, Ask to Buy
   (pending), restore on a second device / after reinstall, and airplane mode (offline message).
6. TestFlight build: purchases are free sandbox purchases; verify prices load from App Store Connect
   (not the local `.storekit`, which TestFlight/App Store builds ignore).
7. App Store listing: the "In-App Purchases" section appears automatically; optionally promote the
   everything pack. Update the description to mention optional cosmetic purchases.
8. Privacy: no new data collection (StoreKit only). No App Privacy changes needed for IAP alone.

## Capability / entitlements

StoreKit 2 needs no entitlement file entry. In-App Purchase is enabled by default for App IDs;
in Xcode you can add the "In-App Purchase" capability for clarity, but it only toggles the App ID
service and adds nothing to `slyme.entitlements`. The project was left unchanged on this point.
