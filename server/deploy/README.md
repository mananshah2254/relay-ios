# Prepared phone-pilot deployment

These files prepare the existing single-process service for one Linux VM (including
Google Compute Engine) with a persistent disk. They are not a deployed service or a
Cloud Run/database migration. The operator must supply the project, billing budget,
domain, and OAuth client before provisioning. No cloud resources have been created.

The iPhone works through HTTPS with the Mac turned off. The VM runs Node 22 or newer
at `/usr/bin/node`; Caddy owns HTTPS on ports 80/443 and proxies to Node on
127.0.0.1:8787. Firewall rules must keep port 8787 private. Caddy overwrites the
client-IP header so rate limits distinguish phones; Relay trusts it only from the
explicitly enabled local proxy.

## Installation after the hosting account is chosen

1. Provision one supported Debian/Ubuntu VM with persistent disk and a reserved IP.
   Set an approved spending budget and monitoring; this is a paid service, and cost
   must be confirmed before provisioning. Point the selected DNS name at its IP.
2. Install Node 22+ and Caddy from official sources. Create a dedicated `relay` system
   user. Place the release's `src`, `scripts`, and `package.json` under
   `/opt/relay/releases/<version>`; point `/opt/relay/current` at that release.
   Keep code root-owned and read-only to `relay`.
3. Create `/etc/relay/relay.env` with mode 0600, owned by root. Put a freshly generated
   `STORE_KEY_HEX`, `PUBLIC_BASE_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and
   `TEST_RECIPIENT_ALLOWLIST` in it. This file is read by systemd; provider secrets
   never go into the app binary, repository, archive, or web root. Keep a separate
   secure backup of the storage key.
4. Install `relay.service` into `/etc/systemd/system/relay.service`. systemd creates
   `/var/lib/relay` with private permissions. Run exactly one Node process; do not use
   containers, replicas, autoscaling, or a shared network filesystem with this store.
5. Replace the placeholder domain in `Caddyfile.example`, validate with
   `caddy validate --config /etc/caddy/Caddyfile`, then enable/reload Caddy. Its normal
   automatic HTTPS flow needs reachable ports 80/443 and working DNS. Do not enable
   query/body/access logs that could record OAuth codes or credentials.
6. Start Relay with `systemctl daemon-reload` and `systemctl enable --now relay`.
   Check `https://<domain>/health` returns HTTP 200 and `{"ok":true}`.
7. Register `https://<domain>/v1/google/callback` in the Google Web OAuth client. Put
   the same HTTPS origin into `RELAY_BACKEND_URL` for the iOS build.
8. Test from a real iPhone on cellular: connect Gmail, paste Hunter's key in Settings,
   save a job without a link, confirm the company, review the rendered email, and send
   only to the configured test inboxes after approval. Check the PDF in Gmail Sent.

## Backups and updates

Back up `/var/lib/relay/state.enc` to private, separate storage. Each write uses an
atomic replacement, so copying that file gets one complete encrypted snapshot.
Never copy a running `store.lock` as part of a restore. Preserve the matching key
separately; test a restore into an isolated directory with no live Gmail sending.

For updates, stop `relay`, wait for shutdown, take a backup, install a new versioned
release, change `current`, and start it. Keep the previous release for rollback.
Do not replace the data directory or encryption key. An interrupted email is held
as uncertain and must be checked in Gmail Sent before any retry. A `/health` 503
means the queue halted; investigate storage rather than looping restarts blindly.

This is a controlled phone pilot. Public enrollment still needs recoverable user
accounts, database/queue scaling, monitoring and backup recovery verification, Google
verification, and review of the final App Store feature set. TestFlight itself can
require Apple review; it is not a way around App Review rules.

References: [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy),
[Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https),
[Compute Engine snapshots](https://docs.cloud.google.com/compute/docs/disks/snapshot-best-practices).
