# Relay 1.2 (build 6): public signup

The invite gate is removed from the hosted service and the normal iOS setup flow.
New users tap **Get started**, then connect their own Gmail and Hunter accounts.
Existing saved device sessions and provider connections remain valid. The API
client retains optional legacy invitation-header support for custom services;
the hosted service ignores it and the public setup screen does not request it.

## Service protection

- All workspace data and actions still require a random bearer session token.
- Signup is capped at 10 attempts per network per hour and 100 service-wide.
- The signup request body is limited to 1 KiB.
- Network counters persist across restarts using a keyed digest, not a raw IP.
- Existing mailbox pacing, approvals, provider authentication and duplicate checks
  still apply. Opening signup does not send email or connect a provider account.

The existing service limits remain: 1,000 workspaces and a 32 MiB encrypted-snapshot
plaintext cap. Storage is shared by the service, while workspaces are logically
isolated. Public access is not unlimited capacity. Cross-device workspace recovery
is not implemented. Do not delete an existing account to test the setup screen.

## Verification on October 14, 2026

- 42 Swift tests passed.
- 53 backend tests passed, including public signup, session isolation, persistent
  network limits, rejection of spoofed forwarding headers and oversized signup bodies.
- Cloudflare deploy: `56e7a095-e36b-423f-b407-0425a3382bee`.
- Live hosted signup without an invitation returned 201; authenticated state was
  empty and unauthenticated state returned 401. Only the newly created smoke-test
  workspace was deleted afterward. No provider call or email send was made.
- Debug simulator build and signed Release archive succeeded.
- App Store Connect accepted the upload of version 1.2, build 6.
- Build 6 finished processing, was attached to the 1.2 draft, and its native-only
  encryption classification was saved. Automatic release is selected.
- The fresh-install Settings screen was visually checked in an isolated simulator:
  **Get started** is present and there is no invitation field.
- Updated public setup and privacy pages were deployed through GitHub Pages.

## Remaining release checks

Version 1.2 has **not been submitted for review**. App Store Connect's privacy page
and Google's verification console failed to load during the final checks.
Before submission, finish the Apple privacy-label disclosure for the short-lived
network abuse counters (app functionality/security, no advertising or tracking),
then verify the saved draft and submit it. Obtain approval for any new privacy
publication attestation. Google verification/audience status still needs checking
in project `relay-508804`; public Relay signup does not remove Google-side limits.

Version 1.1 (build 5) was already approved when this work began. App Store users
need the 1.2 release for the new setup UI. Earlier installations can continue to
use their saved sessions. Google OAuth availability is independent of Relay
enrollment and remains subject to the project's audience and verification status.
