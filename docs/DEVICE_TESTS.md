# Device and distribution checkpoints

These checks require Xcode, an iPhone, and the operator's configured accounts. They are not replaced by the command-line unit tests.

## First run and sharing

- Build the Relay scheme for iOS Simulator and a signed physical device.
- Confirm demo data is labeled, demo operations do not call the service, and leaving demo restores the actual connection.
- Connect the service, terminate the app, and confirm the same session survives reopening.
- Confirm Relay appears in the system share sheet from Safari and the current LinkedIn app.
- Test a numeric LinkedIn job URL, a slugged URL, a job-search link containing `currentJobId`, a LinkedIn hiring post, a plain-text URL, a Greenhouse URL, and a Lever URL.
- Inspect the actual shared payload before claiming automatic LinkedIn description extraction. Record title/company/description availability and fallback frequency across a sample of jobs.
- Share while offline, close the extension, restore connectivity, and verify either a successful background handoff or an accurately pending import in Relay.
- Share the same job twice and confirm a single campaign and no extra Hunter lookups.
- Change account/service, then confirm old queued shares do not silently move to the new connection.

## Contacts and templates

- Resolve job details using authoritative data or explicit user input. Ambiguous domain suggestions must not start mail to an arbitrary company.
- Set a five-contact limit and confirm at most five email addresses are retrieved and at most five recipients are queued.
- Test no contacts, fewer than five contacts, duplicate addresses, invalid/unknown verification, and exhausted credits.
- Confirm relevant contacts actually match the requested department and preference; the UI must not claim hiring-manager certainty.
- Insert every supported template placeholder and verify the rendered message. Unknown fields and missing required values should stop preparation.
- Import a readable PDF, an oversized PDF, a non-PDF renamed to `.pdf`, and a PDF from an external document provider.
- Replace the saved resume after preparation and confirm existing campaigns keep their original attachment snapshot.

## Gmail and queue

Use designated test inboxes and `TEST_RECIPIENT_ALLOWLIST` for these checks.

- Complete and cancel the Google browser authorization flow; confirm failed consent does not show a connected Gmail account.
- Verify the Gmail sender, subject, Unicode body, single recipient, and PDF contents at a receiving test inbox.
- Exercise review mode and explicit automatic mode. Automatic mode still holds incomplete jobs.
- Verify configured spacing across campaigns on the same account, plus the daily cap.
- Cancel between sends, then confirm already-submitted mail is not labeled recalled and future messages stop.
- Disconnect Gmail while a queue is active; confirm unsent work stops.
- Restart the backend during a send. Potentially accepted sends must become uncertain, not automatically duplicated.
- Trigger account/usage failures and confirm no unbounded retries or hidden bypass of provider limits.
- Check app status after force-closing the phone app while the backend continues.

## Native quality and release

- Check compact and large iPhones, dark mode, large Dynamic Type, VoiceOver labels, keyboard dismissal, and long company/job titles.
- Run a signed Release archive and inspect privacy-manifest output and extension entitlements.
- Supply operator-specific privacy/support URLs, final name/icon, accurate screenshots, and a fully accessible review environment.
- Complete applicable Google verification and assess App Store guideline 5.1.1(viii) against the actual Hunter feature.
- Confirm account deletion removes service access and active data; document backup retention separately if backups are introduced.

