# Relay production release path

`localhost` is development-only. On an iPhone it points back to the phone, and an
App Store build must use an internet-reachable HTTPS API origin.

## Product decision before public review

The full Hunter discovery experience can be tested in private development. A
TestFlight distribution can also require Apple review and is not an exemption from
its rules. Hunter discovery remains a material public App Store review question.
Apple App Review guideline 5.1.1(viii) says apps that compile personal information
from sources other than the user, even public databases, are not permitted.

A proposed lower-risk public version would:

1. Ask the user for the job title and company; treat a shared URL as reference only.
2. Accept recipient addresses supplied by the user. Merely selecting recipients from
   a discovered third-party list does not resolve the underlying data-sourcing issue.
3. Show every recipient and rendered email before sending.
4. Keep automatic/batch sending out of the first public review build.

The implemented app still includes Hunter discovery and optional automatic sending.
No separate App Store feature flag or user-supplied-recipient flow has been built.
Resolve the release feature set with the owner; never conceal features from reviewers.

## Production infrastructure

The owner has selected **free services only for hosting**. No paid VM, billing
account, Cloud SQL instance, paid upgrade, or custom-domain purchase is authorized.
The Google setup is currently in the separate `relay-508804` project, in External
Testing mode. Its `Relay Development Backend` Web OAuth client uses
`http://localhost:8787/v1/google/callback` for local simulator development only.
Credentials are in the ignored private `server/.env`, never the iOS bundle.

The current encrypted file store is intentionally a single-process pilot. Do not put
it on Cloud Run unchanged: Cloud Run's local filesystem is ephemeral and the current
queue expects one continuously operating process.

The following was an earlier **paid architecture proposal**, not an approved
deployment plan. It remains a reference until a free-compatible implementation is
built and validated:

- Cloud Run for the HTTPS Node service.
- Cloud SQL for PostgreSQL as the source of truth for users, encrypted provider
  tokens, job records, recipients, message snapshots, suppression, and send state.
- Cloud Tasks for one durable send task per approved message with scheduled spacing.
- Secret Manager for `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, encryption keys, and
  service credentials.
- Cloud Storage for encrypted résumé objects, with short-lived server-side access.
- A verified custom domain such as `api.yourdomain.com`.
- Cloud Logging/Error Reporting, uptime checks, database backups, and budget alerts.

Until the database/queue migration is complete, a single-instance service with a
persistent disk can run a small private pilot. It is not the final public architecture.
The installable service/proxy templates for that pilot are in
[server/deploy](../server/deploy/README.md). They have not been deployed.

### Free-hosted private pilot (deployed September 22, 2026)

The private pilot runs on Cloudflare Workers Free with encrypted SQLite-backed
Durable Object storage and alarm-driven sends. Its HTTPS `/health` passes and
unauthorized enrollment returns 403. The hosted OAuth callback is registered.
All 28 backend tests pass, including alarm restart/uncertain-send behavior, account
isolation, deletion, and a 3 MiB PDF persistence test. Gmail consent and real delivery
remain unverified. The snapshot store is capped at 32 MiB and is not a public-scale
database. See [operations and limits](../server/cloudflare/README.md).
Quota exhaustion can interrupt service; no automatic paid upgrade is authorized.

Render Free is not a drop-in deployment: its service sleeps after inactivity and
does not support persistent disks. Deploying the current file store there would
lose state. It is not used by this deployment.

Sources: [Cloudflare Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/),
[Cloudflare storage API](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/),
[Render Free limits](https://render.com/docs/free).

## Exact release order

1. Join the paid Apple Developer Program and make the App ID, Share Extension ID,
   App Group, and Keychain group under that paid team.
2. Choose the final app name, support email, website domain, and privacy-policy URL.
3. Create separate Google Cloud projects for development and production.
4. Build the production database, durable queue, account recovery, and encrypted
   résumé storage; import no development secrets or user data.
5. Deploy the API, map the HTTPS custom domain, and verify `/health` externally.
6. In Google Cloud, set the OAuth app to External, configure the verified domain and
   privacy links, enable Gmail API, and register exactly:
   `https://api.yourdomain.com/v1/google/callback`.
7. Put the production Google Web OAuth client values in Secret Manager. Never put the
   client secret in Xcode or the iOS app.
8. Set `PUBLIC_BASE_URL=https://api.yourdomain.com` in the service and set this Xcode
   build setting (using xcconfig URL escaping):
   `RELAY_BACKEND_URL = https:/$()/api.yourdomain.com`.
9. Run a TestFlight pilot with a recipient allowlist, review mode, low daily limit,
   account deletion, OAuth revoke, queue-recovery, and Gmail Sent-folder checks.
10. Complete Google OAuth verification for the requested Gmail scope. Prepare a
    truthful demo video and keep requested scopes minimal.
11. Publish the privacy policy and support page, complete App Privacy disclosures,
    add App Review notes and a working review account/path, then upload an Archive to
    App Store Connect.
12. Submit the public-safe build first. Treat Apple approval as a review decision,
    never as something hosting or code can guarantee.

## Job intake used by the app

The implemented workflow in review mode is now:

`enter role + company (link optional) -> resolve employer domain -> confirm domain ->
find contacts -> preview emails -> approve send`

Greenhouse and Lever links may still provide metadata through their supported APIs.
LinkedIn links are never scraped. The Share Extension attempts to prefill explicit
LinkedIn share text, but requires the user to confirm the title and company. When the
company website is omitted, the backend calls Hunter Domain Finder with
`perfect_match=true` and accepts only an exact normalized company-name match.
Contact discovery waits for domain confirmation even if automatic sending is enabled.
Once a user has confirmed the domain, their saved automatic mode can queue the
prepared messages without a second approval; review mode continues to require it.
