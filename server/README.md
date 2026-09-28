# Relay service

This is the small backend used by the Relay iOS app. It owns the Hunter and Gmail credentials, resolves only supported job-board APIs, stores campaign snapshots, and sends one Gmail message at a time from a durable queue. It is intentionally a single-process pilot service: run exactly one instance for each `DATA_DIR`.

## Local setup

Requires Node.js 22 or newer. From this directory:

```sh
npm run setup
# edit .env and add GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET when Gmail is needed
npm test
npm start
```

`npm run preflight` reports missing local configuration without exposing secrets.
For a single VM behind HTTPS, see [the prepared pilot deployment](deploy/README.md).
Use `node scripts/preflight.mjs --hosted` with the hosted environment to check it.

`npm run setup` creates `.env` with a random 32-byte `STORE_KEY_HEX` and mode `0600`; it never overwrites an existing file. Keep that key in a password manager and back up the encrypted `DATA_DIR` together with it. Losing the key makes the stored state unrecoverable. The default development origin is `http://localhost:8787`.

To import Google's downloaded **Web application** client JSON without displaying
its secret, run `node scripts/import-google-oauth.mjs /absolute/path/download.json
relay-508804`. The importer verifies the project and callback, preserves the storage
key, and refuses to replace different existing OAuth credentials. Keep the download
private; never commit it. Restart the backend after import.

Current hosting: Cloudflare Workers Free, deployed September 22, 2026 with an
encrypted SQLite Durable Object and alarm-driven queue. See [hosting operations](cloudflare/README.md).
The VM templates remain unused references. The local file store is not compatible
with ephemeral free hosts. See [release status](../docs/PRODUCTION_RELEASE.md).

## Configuration

- `HOST` and `PORT` control the listener. Bind to loopback for local testing.
- `PUBLIC_BASE_URL` must be an HTTPS origin in deployment, or an HTTP localhost origin for development. It must match the URL used in the iOS app and the Google OAuth redirect registration.
- `DATA_DIR` is the private directory containing `state.enc` and a process lock.
- `STORE_KEY_HEX` is exactly 64 hexadecimal characters. Never commit or log it.
- `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are a **Web application** OAuth client for the backend callback, not an iOS client. Register `PUBLIC_BASE_URL/v1/google/callback` exactly in Google Cloud.
- `TEST_RECIPIENT_ALLOWLIST` is a comma-separated list of test inboxes. Set this before any live pilot; addresses outside it are canceled by the queue.
- `TRUST_LOOPBACK_PROXY=true` is only for the supplied Caddy configuration on the same
  VM. It trusts an overwritten client-IP header only from a loopback connection.

The service requests only Google's `gmail.send` scope (plus identity scopes). It does not read Gmail inboxes. Provider credentials and résumé bytes are encrypted at rest and are not returned by `/v1/state`.

## Operating limits and recovery

The app bounds each Hunter lookup to the saved contact limit (1–20), spaces sends by at least five seconds, and applies a daily cap. A lookup budget is reserved before calling Hunter; an interrupted lookup is not automatically repeated. A send that may have reached Gmail is marked `uncertain`, pauses the queue, and is never retried automatically. Check Gmail Sent before any manual action.

This pilot store is not suitable for multiple replicas or unattended public enrollment. Use a transactional database, distributed queue, account recovery, monitoring, backups, and a reviewed privacy policy before production. Apple and Google review the actual product and data flows; a successful local test does not guarantee approval.
