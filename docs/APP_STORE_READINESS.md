# Relay App Store preflight — September 24, 2026

Status: not uploaded or submitted. The installed development app is not an App Store release.

## Decisions and external blockers

1. **Discovery feature:** Apple's current guideline 5.1.1(viii) addresses compiling personal information from sources other than the user, including public databases. Relay's Hunter-sourced named employee addresses create a substantial review risk. This is an interpretation of the guideline, not an Apple decision about this app. Do not hide discovery from review or silently remove the core feature. The owner must choose whether to seek Apple's guidance while retaining discovery, or authorize a genuinely different public product using user-supplied recipients and explicit review. Manual selection of Hunter results alone does not resolve the sourcing concern.
2. **Apple membership:** current project uses team QX8465Q2BQ, previously configured as a Personal Team. Current paid membership has not been verified. App Store Connect is open at sign-in, awaiting the owner. Apple lists ordinary Developer Program enrollment at USD 99/year, with regional pricing and eligible waivers. No enrollment payment or agreement has been accepted.
3. **Google production access:** last confirmed configuration was External Testing for relay-508804. Live console state must be checked; do not claim verification is completed. gmail.send is a sensitive scope. Prepare production branding, verified domain/privacy URLs, scope justification and a truthful demonstration for Google verification. Do not simply switch audiences and call it verified.
4. **Release identity:** confirm final listing name, public support email, seller details, release territories and pricing. Do not publish private contact details by assumption.

## Local findings

- Signed iPhone development installation and unsigned Release compilation succeeded September 23. 35 Swift and 51 backend tests passed. This does not prove distribution signing, archive validation, or review approval.
- Backend is live on the existing Cloudflare Workers free deployment. Current deployment a6a71c2a-1332-4b4d-ad4e-0172e94c4079 enforces at least 600 seconds between attempts, with existing rolling daily limits. Retain the free-hosting constraint.
- Account deletion and provider disconnect controls exist. Verify full deletion/revocation against an isolated review account, not the owner's live data.
- Privacy manifest exists in both targets. It must be reconciled with final product behavior and App Store privacy disclosures; a manifest does not replace a published privacy policy.
- Settings currently explains backend storage but has no public privacy-policy link. Publish accurate support/privacy pages and expose them in the app before submission.
- Current onboarding uses a private enrollment mechanism. Decide on genuine invite-only distribution versus public onboarding; do not remove enrollment protection without an authenticated, abuse-controlled replacement.
- Google connects a Gmail mailbox rather than serving as Relay's primary login. Assess Apple's guideline 4.8 third-party-service-client exception; do not assume Google integration automatically requires or exempts Sign in with Apple.
- Current base version is 0.1.0 (build 1). Choose release numbering and validate icons, screenshots, share extension, export compliance, deployment SDK, accessibility and device coverage after the release feature set is settled.
- Offline samples help inspect layout, but do not give reviewers full access to Gmail/Hunter behavior. Supply a functional, disclosed review path that avoids unsolicited test sends and demonstrates the actual shipped functionality.

## Next sequence after the owner's decision

1. Verify paid team and App Store Connect access.
2. Resolve discovery/review compliance and production onboarding; preserve the installed pilot unless changes are explicitly authorized.
3. Confirm public identity/contact details; publish accurate privacy/support pages and link them in Settings.
4. Complete Google production prerequisites and verification.
5. Create App Store record and distribution identifiers, archive, validate, upload, and use TestFlight for release testing (not as a policy bypass).
6. Complete metadata, screenshots, age rating, export compliance, App Privacy and review access with owner-approved factual declarations.
7. Submit transparently for Apple review. Approval and timing remain Apple's decision.

## Primary sources checked

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 5.1.1, 5.1.2, 4.8 and review access.
- [Apple Developer enrollment](https://developer.apple.com/programs/enroll/) — membership, seller identity and fees.
- [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes) — gmail.send sensitivity and verification.
- [Google sensitive-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification) — production prerequisites.

The older PRODUCTION_RELEASE.md contains historical architecture plans. Use this preflight and the current Cloudflare operations documentation for present status.
