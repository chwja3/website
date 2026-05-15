# Case Sensitive User Id Context

## Decision

Nicknames are now exact user ids. Case differences are meaningful. The app should not merge or fallback between `Oh! New`, `oh! New`, and `OH! NEW`.

## Consequences

- A sheet/event row whose user id differs only by case from an active user is treated as a different or unknown user.
- Inactive exact users do not contribute to active users with different casing.
- `repairCaseVariantUserDataDryRun` remains useful for finding case variants, but apply should release inactive or unknown exact user tickets rather than rename them to another case variant.
