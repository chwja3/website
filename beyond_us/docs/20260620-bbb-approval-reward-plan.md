# BBB approval reward plan

## Goal

Fix the case where admin-approved BBB Mission 1 and Mission 2 photos do not give the user a usable card pack.

## Assumptions

- BBB Mission 1 and Mission 2 rewards are still stored internally as `special_pack.granted`.
- `events` is the ledger and `user_inventory` is a fast cache.
- Already-approved rows should be repaired without duplicate rewards.

## Steps

1. Add an idempotent inventory reconciliation helper for special packs.
2. Harden the photo approval reward helper so it always reconciles inventory.
3. Backfill already-approved BBB M1/M2 photo rows.
4. Let the app use existing special packs even if the special-pack tab toggle is off.
