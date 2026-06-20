# BBB approval reward context

Admin approval for BBB Mission 1 and Mission 2 was confirmed not to give users a usable card pack. The existing approval flow calls `bu_issue_special_pack_for_photo`, but if an old reward event exists without matching `user_inventory`, or if the app hides special packs behind the `specialPack` toggle, the user can still see no usable card pack.

The fix keeps the event-ledger model. `special_pack.granted` and `special_pack.consumed` are treated as source of truth, while `user_inventory.special_pack_*` is reconciled from those events. The app also treats a positive `pendingSpecialPacks` value as drawable even when the admin display toggle is off.
