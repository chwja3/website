# BBB singleton TF fallback context

The previous BBB auto matching groups people by group and participation tier. Buckets with only one person cannot form a circular buddy pair, so their care buddy and secret buddy stayed empty.

New rule.

- If a `토참` or `일참` bucket has exactly one person, that person gets a care buddy from `전참` in the same group.
- That same person gets a secret buddy from the TF/staff pool, preferring TF/staff in the same group.
- Because one TF/staff user may need to care for multiple singleton participants, extra TF care links live in `bbb_extra_care_roster_links` instead of being forced into the single `care_buddy_roster_id` field.
- Admin manual care buddy search is no longer limited to the same group or same participation tier. The save RPC also allows cross-group assignments.
- User app BBB status now exposes `extraCareBuddies`, and the care buddy box renders those names for TF/staff users who receive singleton partial participants as extra care targets.
- Manual SQL order matters. Run `20260620000600_bbb_singleton_tf_fallback.sql` before the latest roster patch SQL so roster sync uses the conflict-safe function.
- Roster sync now deduplicates `group_members` and `bbb_assignments` by `matched_profile_id` before upsert, which prevents duplicate matched roster rows from causing PostgreSQL `ON CONFLICT ... cannot affect row a second time`.
- `public.group_role` enum values are `leader`, `assistant`, and `member`. Co-leader style rows must be ordered as `assistant`; using `coleader` in SQL makes PostgreSQL raise `invalid input value for enum group_role`.
