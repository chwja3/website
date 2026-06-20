# BBB singleton TF fallback plan

## Goal

When a Saturday-only or Sunday-only group bucket has only one person, assign that person a care buddy from full participants in the same group and a secret buddy from the TF/staff pool, preferring TF/staff in the same group.

## Design

- Keep the existing one-care-buddy and one-secret-buddy roster fields.
- Add a separate `bbb_extra_care_roster_links` table so one TF/staff person can care for multiple singleton partial participants.
- Sync app-facing `bbb_assignments` from roster links after auto assignment.
- Show extra care buddies in the TF/staff user's BBB care buddy panel.

## Success criteria

- Normal buckets with two or more people still use circular matching within the same group and tier.
- Singleton `토참` and `일참` rows receive a full-participant care buddy.
- Singleton `토참` and `일참` rows receive a TF/staff secret buddy, same group first.
- The TF/staff user can see all extra care buddies assigned to them.
