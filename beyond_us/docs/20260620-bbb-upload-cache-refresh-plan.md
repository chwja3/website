# BBB upload cache refresh plan

## Goal

Force clients to load the latest BBB upload path code after the Supabase Storage `InvalidKey` error showed an old Korean nickname path.

## Success criteria

- App asset version is bumped consistently.
- Service worker cache name is bumped consistently.
- Remote `app.html` points to the new `app.js` query version after push.
- No Supabase SQL is required for this cache-only fix.
