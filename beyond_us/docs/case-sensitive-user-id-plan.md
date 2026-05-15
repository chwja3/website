# Case Sensitive User Id Plan

## Goal

Treat nicknames as case-sensitive user ids across GAS data ownership. `Oh! New` and `oh! New` must be different users even when the spelling only differs by case.

## Implementation

1. Make `userIdKey_()` preserve case and only trim whitespace.
2. Keep a separate folded-key helper only for diagnostics that need to find case variants.
3. Remove automatic active-user fallback across case variants.
4. Keep repair functions, but make them release inactive or unknown exact user ids instead of renaming them to a case variant.

## Verification

- `isSameUserId_('Oh! New', 'oh! New')` becomes false.
- Active raffle ticket and Collection ownership use exact nickname identity.
- Case variant audit still reports variants for admin diagnosis.
