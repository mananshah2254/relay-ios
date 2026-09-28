# Relay interface refresh — September 23

## Second redesign: native information architecture

- Jobs is now a grouped list with large navigation title, compact tappable Review/Active/Attention counts, status segments, company/title/domain search, and newest/oldest/company sorting. Unknown future statuses remain visible under All.
- Outreach is a grouped inbox with per-message Drafts/Queued/Attention filters and company/recipient/subject search. Fixed the old behavior that included completed messages merely because another message in their campaign matched the filter.
- Templates uses native grouped From/Subject/Message sections, animated role selection, and a collapsed personalization panel. Settings uses short navigation rows for connections, sending preferences, templates, and privacy instead of one long card stack.
- Activity uses an indeterminate paper-plane/connection animation. Native backgrounds now adapt consistently to system light/dark appearance.
- Installed successfully on the physical iPhone after USB reconnection. Inspected Jobs, Outreach, Templates, Settings, and sending preferences using offline samples. The template editor's Done control cleared focus and restored unobstructed tab access (Device Hub used hardware keyboard mode). Full software-keyboard coverage on every form is not claimed.

## Conservative sending schedule

- Default and minimum spacing is now ten minutes, up to six attempts per hour per Gmail mailbox; users can choose longer delays up to an hour. The existing rolling 24-hour cap is retained (default ten).
- The server migrates legacy fast user settings and campaign snapshots to 600 seconds while preserving longer delays, content, approval, and pause state. Current longer preferences slow already queued jobs, and campaign snapshots cannot bypass the minimum.
- Queue and Cloudflare alarm planning share one timing rule. Both respect previous attempts, send completion, persisted delays, and the daily cap. There is no catch-up burst after a delayed alarm or restart.
- Settings and Outreach explain the cadence and hourly maximum. No claim that pacing guarantees inbox placement, and no randomized timing to disguise automation.
- Verification: 35 Swift tests and 51 backend tests pass, including fake-clock hourly/cross-session pacing, legacy migration, completion delays, and local Workers restart checks. Debug device and unsigned Release builds pass. No real email sends or paid Hunter lookups were used for verification.
- Backend deployed as version `a6a71c2a-1332-4b4d-ad4e-0172e94c4079`; updated app installed successfully on the iPhone (installation database sequence 2412).

## First refresh

- Native semantic light/dark surfaces, a blue accent, SF typography, quieter borders, consistent rounded cards, and clear disabled buttons.
- Activity overlays now live inside Add/Edit sheets as well as the tab root. Previously the root spinner could be obscured by a presented sheet.
- A small animated connection motif, provider-specific copy, and elapsed waiting text replace the generic spinner. It is indeterminate, never fabricated progress or a claim of delivery. Reduce Motion disables its motion and press/selection transitions.
- Inline activity for company suggestions and job-link prefill; obsolete company responses are discarded when the query changes or the view closes.
- Template selection uses a shared animated highlight. Job list supports company/title search. Save confirmations are visible and dismissible.
- The returned campaign is merged immediately into the local snapshot before refreshing. A failed subsequent refresh cannot erase a confirmed result or leave navigation pointing at a missing campaign.
- Busy forms block repeated submissions and dismissal; submit dismisses the keyboard. Add/Edit display inline errors as well as the existing root error handling.
- DEBUG-only offline preview arguments permit visual QA without credentials, provider traffic, or sending: `--relay-preview=activity`, `--relay-preview=templates`, `--relay-preview-light`. Relaunch without arguments to restore the normal account. These flags do not alter stored credentials/settings.

Verification: physical iPhone build and 29 Swift / 46 backend tests pass. Dark activity and light-theme screens inspected on the phone using offline samples. Device Hub stopped accepting coordinate interactions during further checks, so keyboard interaction and detailed animated-template interaction were not fully re-verified. No live emails or paid Hunter lookups were used for this refresh.

Provider coverage/timeouts remain a separate issue: a visual refresh does not guarantee Hunter will return verified contacts. Existing review and sending controls are preserved.
