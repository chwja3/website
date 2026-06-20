# BBB manual profile reassign context

The previous admin duplicate-resolution RPC returned `profile_already_matched` when a candidate profile was already attached to another roster row. In real operations, that blocks the exact workflow admins need for duplicate names: choose the correct roster row and move the app account there.

New behavior.

- If the selected profile is already matched to another row in the same source batch, the old row is cleared.
- The old row becomes `manual_unmatched` with a detail that says it was cleared because the profile moved.
- The target row becomes `matched_manual`.
- The older cleared row uses `manual_unmatched`, and roster sync preserves that state so it is not auto-matched again.
- `bu_sync_bbb_assignments_from_roster` runs afterward so `bbb_assignments` follows the confirmed roster row without re-running profile auto matching.
