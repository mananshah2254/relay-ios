# Cloudflare private pilot

## External outreach enabled

The owner authorized removing the test-inbox restriction on September 22, 2026.
`ALLOW_EXTERNAL_RECIPIENTS="true"` explicitly overrides the stored test allowlist.
To restore test-only delivery, set it to `"false"` and redeploy. Enrollment,
verified-recipient checks, approval preferences, daily caps, spacing, duplicate
suppression, and uncertain-send protection remain unchanged. Canceled messages
are not requeued by changing this setting. The test-only notes below describe
the original deployment verification, not the current recipient policy.

Deployed September 22, 2026 to:
https://relay-referrals-api.manan-hiren-shah.workers.dev

Workers Free was confirmed before deployment. No paid upgrade, R2 subscription,
or domain purchase was enabled. Public `/health` returns `{"ok":true}`; creating
a session without the private enrollment header returns 403.

## Deployment

Run from `server`:

```sh
npm test
npm run deploy:cloudflare
node scripts/configure-cloudflare.mjs https://relay-referrals-api.manan-hiren-shah.workers.dev --upload
```

The ignored, owner-readable `.env.cloudflare` preserves hosted encryption and
enrollment keys separately from local development. The upload script sends secrets
directly to Wrangler without logging their values. Back up this file securely;
replacing the encryption key makes existing cloud data unreadable.

Use Relay's service setup field with `HTTPS_ORIGIN#ENROLLMENT_KEY`. Keep this
private; never open that setup string in a browser or share it publicly. The app
strips the fragment, sends the key only as an enrollment header, and saves a
session token in Keychain. The Google client secret never belongs in the app.

## Limits and safety

One SQLite-backed Durable Object stores encrypted, chunked snapshots. The pilot
has a 32 MiB plaintext snapshot cap and rewrites the snapshot on mutation. This
is not a scalable public database. Automated tests verify a 3 MiB PDF round trip,
account isolation, deletion, and restart persistence; the full upload limit is
not yet load-tested on the hosted service.

Durable alarms wake only for queued work. A durable sending marker precedes Gmail
submission; uncertain results pause sending instead of automatically retrying.
Free quota exhaustion can interrupt service; do not enable a paid plan automatically.
The recipient allowlist remains enabled. No real messages have been sent during
deployment verification. Gmail consent, Hunter setup, and an explicitly authorized
end-to-end send test remain pending. Public App Store release is a separate review.
