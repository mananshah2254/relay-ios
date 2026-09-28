# Google setup status — September 22, 2026

Configured in the owner's separate Google Cloud project `relay-508804`:

- OAuth app name: Relay; audience: External, Testing.
- Owner's Google account added as the sole test user.
- Gmail API enabled.
- Web OAuth client: Relay Development Backend.
- Registered redirect: `http://localhost:8787/v1/google/callback`.
- Hosted redirect saved and verified: `https://relay-referrals-api.manan-hiren-shah.workers.dev/v1/google/callback`.
- Declared scopes: `openid`, `userinfo.email`, and `gmail.send` only.
- Downloaded credentials imported into the private, ignored `server/.env`.
- Backend restarted with OAuth configured; `/health` returned `{"ok":true}`.
- Pilot recipient allowlist restricted to the owner's test inbox.
- All 28 backend tests passed, including Cloudflare storage and alarm recovery.

The private pilot backend is deployed on Cloudflare Workers Free and its public
HTTPS health check passes. No paid plan was enabled, and the app has not completed Google production
verification. Gmail login, granting access, Hunter key entry, and a real send test
remain to be completed by/with the owner. Do not interpret successful configuration
checks as proof of end-to-end OAuth or email delivery.

## Owner's next steps in the simulator

1. In Relay → Settings → Connect Gmail, sign in with the registered test account.
   Review Google's requested permission before consenting. Do not paste a password
   or verification code into chat.
2. Back in Relay, enter the Hunter API key in Settings → Hunter → Connect Hunter.
3. Set the sender details/template and optionally choose a PDF résumé.
4. Arrange an explicit test to the owner's inbox before real recipient outreach.
   The current allowlist prevents messages to other recipients.

The iPhone build now uses the hosted HTTPS backend, not localhost. Private enrollment
is required before Gmail connection. See [hosting operations](../server/cloudflare/README.md).

## Credential handling

The Google secret does not belong in Xcode or the iOS app. The downloaded JSON
remains in the owner's Downloads folder with owner-only filesystem permissions.
Back it up securely or remove that redundant copy after storing it safely. Do not
rotate the storage encryption key: existing encrypted app data needs that same key.
