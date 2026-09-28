# Relay API contract

The native app and Share Extension use the same API. Paths are relative to the configured service origin. JSON uses camelCase; dates use ISO 8601 strings. The implementation is under `server/`, and Swift models and client methods are in `Sources/OutreachCore/`.

## Authentication

`POST /v1/session` with `{}` creates an opaque device session and returns `{ "token": "…", "userId": "…" }`. All other app endpoints require `Authorization: Bearer <token>`. The Google browser callback authenticates using its one-time OAuth state instead. Session tokens belong in the shared Keychain, never UserDefaults or analytics.

The initial implementation uses device sessions. It does not yet provide cross-device account recovery. Keep the existing token when reconnecting to the same service. Public deployment requires operational controls for enrollment and account recovery.

## Endpoints

| Method | Path | Request | Success payload |
| --- | --- | --- | --- |
| POST | `/v1/session` | `{}` | `Session` |
| GET | `/v1/state` | — | `AppSnapshot` |
| PUT | `/v1/settings` | `OutreachSettings` | `OutreachSettings` |
| POST | `/v1/hunter` | `{apiKey}` | `{connected: true}` |
| DELETE | `/v1/hunter` | — | Empty/success |
| POST | `/v1/google/connect` | `{}` | `{authorizationURL}` |
| GET | `/v1/google/callback` | OAuth query | Redirect to `relayreferrals://oauth/complete` |
| DELETE | `/v1/google` | — | Empty/success |
| POST | `/v1/resume` | `{filename, dataBase64}` | `ResumeDocument` |
| DELETE | `/v1/resume` | — | Empty/success |
| POST | `/v1/jobs` | `ImportRequest` | `Campaign` |
| PATCH | `/v1/jobs/:id` | `ImportRequest` | `Campaign` |
| POST | `/v1/jobs/:id/research` | `{confirmedDomain?}` | `Campaign` |
| POST | `/v1/jobs/:id/approve` | `{}` | `Campaign` |
| POST | `/v1/jobs/:id/cancel` | `{}` | `Campaign` |
| POST | `/v1/queue/pause` | `{}` | `{queuePaused: true}` |
| POST | `/v1/queue/resume` | `{}` | `{queuePaused: false}` |
| DELETE | `/v1/account` | — | Empty/success |

Errors use `{ "error": { "code": "machine_code", "message": "Readable explanation" } }` and a non-2xx status.

## Data shapes

`AppSnapshot`: `settings`, `connections: {gmailEmail: String?, hunterConnected: Bool}`, optional `resume`, `campaigns`, and optional `queuePaused`.

`OutreachSettings`: `senderName`, `subjectTemplate`, `bodyTemplate`, `maxContacts`, `sendIntervalSeconds`, `dailyLimit`, `recipientPreference`, `sendingMode`, `attachResume`.

- Recipient preference: `relevant`, `senior`, `executive`, or `recruiting`.
- Sending mode: `review` or `automatic`.
- Limits: 1–20 contacts; 5–3,600 seconds minimum spacing; 1–100 daily sends. These are app constraints, not assertions about Gmail deliverability or provider limits.
- Defaults: 5 contacts, 10 seconds, 10 daily sends, relevant contacts, review mode, no attachment.
- Supported placeholders: `{{first_name}}`, `{{company}}`, `{{job_title}}`, `{{job_url}}`, `{{sender_name}}`.

`ImportRequest`: optional `url`, `sharedText`, `title`, `company`, `domain`, `description`, `clientRequestID`. Without a URL, `title`, `company`, and a UUID `clientRequestID` are required. The client keeps that UUID across retries so a timeout cannot create duplicate manual imports. Nonempty canonical URLs also deduplicate imports. A LinkedIn URL alone is not a job description.

`Campaign`: `id`, `url` (empty when omitted), `title`, `company`, `domain`, `domainConfirmed`, `description`, `status`, `createdAt`, `contacts`, `messages`, optional `note`.

A user-supplied employer domain is confirmed when the details are saved. An inferred
domain remains unconfirmed and performs no contact search, even in automatic mode.
To confirm, submit `/research` with the exact displayed `confirmedDomain`. A stale or
different domain returns 409. An empty research body can retry missing setup but does
not imply confirmation. Company-domain matching can run before Gmail setup; contact
lookup and preparing Gmail messages still require Gmail and the saved sender name.

Templates omit a standalone `{{job_url}}` or `Job: {{job_url}}` line for manual jobs
without links. An inline `{{job_url}}` renders empty; other required values stay strict.

`Contact`: `id`, `email`, `firstName`, `lastName`, `position`, `department`, `verification`, `reason`.

`OutboundMessage`: `id`, `contactId`, `to`, `subject`, `body`, `status`, optional `gmailMessageId`, optional `error`.

`ResumeDocument`: `id`, `filename`, `byteCount`, `uploadedAt`. Downloadable PDF bytes and provider credentials are never included in the state response.

## Behavior that clients must preserve

- An imported job may be `needs_details` until source data and settings are complete. Show the reason and permit correction/research.
- Research consumes the configured Hunter lookup budget. Repeating an import or button tap must not create additional sends or silently spend another full budget.
- Prepared messages use saved settings and a specific resume/account snapshot. Later settings edits apply to future preparation.
- A message marked `submitted` has been accepted by Gmail's API. This is not proof of delivery or a reply.
- An `uncertain` send might already have reached Gmail. Never present automatic retry as harmless.
- Cancellation only affects messages that have not already started sending.
- The API may accept the import before the phone receives its response. Preserve pending local records until an acknowledged response and rely on server deduplication for repeated uploads.

The backend is a single-process implementation with encrypted persistent storage. Do not run multiple replicas against the same directory; use a transactional shared database and distributed queue when scaling.
