# Job prefill, automation, and role templates

## Contact discovery and recovery

Relevant search now includes the role department, HR, executive, and management
departments rather than requiring an exact department AND seniority intersection.
Explicit senior/executive/recruiting preferences remain strict. Personal address,
valid verification, employer-domain, and duplicate checks remain enforced.

For a recorded zero-result response, a one-time **Broaden verified search** action
removes department, seniority, and position requirements, while retaining names,
personal type, and valid verification. It reserves a new bounded lookup, records
history, and forces review even if automatic sending is enabled. There is no
automatic pagination, unverified fallback, or retry after an ambiguous response.
No result is a statement about that filtered Hunter response, not a claim that the
company has no employee addresses. Valid-only coverage may still be empty.

Keyboard toolbars provide Done on all editable app screens; scrolling dismisses
interactively. Share extension fields use FocusState instead of UIApplication.

## Website versus email domain

Greenhouse Software's website is greenhouse.com, but its official press kit
(https://www.greenhouse.com/press-kit) publishes @greenhouse.io contacts. Relay
maps that exact company/domain pair to greenhouse.io for contact lookup. The root
employer domain is accepted; hosted job-board subdomains remain rejected.
This does not guarantee that Hunter has verified contacts matching the filters.

Only failed lookups with a recorded response of exactly zero contacts and no
messages/contacts can be retried through Edit job details with a changed domain.
The old lookup is recorded in history, a new lookup budget is reserved, and
recovered messages require review regardless of automatic sending preferences.
Ambiguous failures, unchanged domains, and existing message snapshots stay locked.

## Job prefill

Sharing a job reads the title/text supplied by the source app, then requests a
read-only preview. Known LinkedIn share text and labeled title/company text can
fill fields. A bare LinkedIn URL is not scraped and may require manual details.
Greenhouse and Lever links use their official public job APIs for available fields
and descriptions. Lever does not provide a reliable company display name in this
adapter; missing fields stay empty, never guessed from a URL slug.

In Add Job, paste a link and tap **Fill from link**. Existing nonempty fields are
preserved. You can paste shared text into the description field and repeat the
lookup. Preview does not create a campaign, use Hunter credits, or send messages.
Unsupported links can be saved from the share sheet and completed later in Relay.

References: https://docs.greenhouse.io/job-board.html and
https://github.com/lever/postings-api

## Explicit automation

Settings → Outreach controls has two independent options:

- Automatically confirm company website: trust a successful Hunter match.
- Send automatically when research is ready: queue prepared messages without approval.

Enable both and save for share-to-queue behavior. Existing accounts retain their
current sending preference; company auto-confirm defaults off. Missing title,
company, website, account connections, or sender name still block research.
No match is guessed. A wrong company-name match can contact the wrong employer;
the UI discloses this risk. Saving settings alone does not reprocess old jobs.

## Role templates

General, Software Engineer, Support Engineer, and AI Engineer have separate editable
subjects and messages. Switching saves the current draft in memory; Save persists
all role drafts and the selected role with the account. The selected template
applies to newly researched jobs and share-sheet imports. Existing frozen email
previews are unchanged. Templates are selected by the user, not guessed from titles.
Starter text introduces the sender without inventing qualifications; users should
add a truthful experience summary. Existing customized templates are preserved.
# Company selection (September 22 update)

Connection recovery update: Hunter requests now have a 60-second deadline (Google remains at 20 seconds). Timeout errors are distinguished from other fetch failures, including response-body timeouts. Failed contact requests with no received results offer one explicitly confirmed retry, warn about possible duplicate Hunter charges, and force recovered drafts into review even when automatic sending is enabled. Existing legacy Hunter connection-failure records also qualify. A successful diagnostic alone does not establish that the filtered outreach query completes inside this deadline.

Live check on the user's iPhone: one explicitly approved Amazon diagnostic retrieved five personal addresses, all five `accept_all`, zero `valid`. No messages were drafted or queued. This establishes live connectivity and explains why these sampled addresses do not satisfy the verified-only policy; it does not prove that Amazon has no valid addresses anywhere in Hunter or explain a past transport failure. Job actions now include an explicitly confirmed, once-per-job diagnostic (up to five addresses, credits may apply). It stores aggregate counts only and never calls the outreach preparation or approval path.

Add Job and Edit Job now offer **Find company website** after at least three characters. An authenticated, rate-limited endpoint queries Hunter Domain Finder for up to ten non-exact suggestions. Choosing one fills the company and actual domain; no `.com` suffix is invented. Editing a selected name clears that selection's domain, and stale responses are discarded. Browsing does not create a campaign or queue messages. Saving retains existing outreach preferences, so automatic sending can still apply to a new job.

These are Hunter suggestions, not a complete prefix-search directory. Manual domains remain available. Domain Finder is documented as free, but requires a working Hunter key and available account search quota. A company match does not guarantee verified contact availability.

Hunter transport failures, rejected keys, rate limits and usage limits now have separate messages. Header authentication is supported by Hunter and retained so keys never enter request URLs. Tests use mocked contacts; a successful test suite is not proof of live Amazon/Walmart coverage. Existing historical campaign messages are not rewritten by deployment.
