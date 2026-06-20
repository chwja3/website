# BBB roster name fallback context

Some BBB buddy rows can point to people who are not app users, or to profiles where display fields contain empty-like values such as the literal string `null`. The user-facing app and admin page should still show the retreat roster participant name.

Decision.

- Roster `participant_name` is the primary display source for BBB buddy names.
- Profile `name`, `display_name`, and login id are fallback values only.
- SQL now normalizes empty strings, literal `null`, and literal `undefined` before choosing a display value.
- Run this hotfix after the roster patch and singleton TF fallback SQL so it becomes the last active definition of the BBB status RPCs.
