import { createHash, randomBytes } from 'node:crypto';
import { AppError, DEFAULT_SETTINGS, clone, id, iso, string, noNewline, normalizeDomain, parseJobInput, publicCampaign, publicResume, rankContacts, renderMessage, validateResume, validateSettings } from './domain.mjs';
import { APP_CALLBACK, ProviderError } from './providers.mjs';
import { employerEmailDomain } from './domain.mjs';
import { MIN_SEND_INTERVAL_SECONDS, mailboxAvailableAt, sendIntervalMilliseconds } from './pacing.mjs';

const DAY = 24 * 60 * 60 * 1000;
const COOLDOWN = 30 * DAY;
const hash = value => createHash('sha256').update(value).digest('hex');
const pendingStatuses = new Set(['draft', 'queued']);

export class ReferralService {
  constructor({ store, hunter, google, resolver, now = () => Date.now(), recipientAllowlist = [] }) {
    Object.assign(this, { store, hunter, google, resolver, now });
    this.recipientAllowlist = new Set(recipientAllowlist.map(email => email.trim().toLowerCase()).filter(Boolean));
    this.locks = new Map();
    this.ticking = false;
    this.halted = false;
    this.store.data.mailboxes ||= {};
    this.recover();
  }

  persist() {
    try { this.store.save(); } catch (error) { this.halted = true; throw error; }
  }

  recover() {
    let changed = false;
    for (const user of Object.values(this.store.data.users)) {
      // Upgrade legacy fast queues without changing content, approval, or pause state.
      if (!(user.settings.sendIntervalSeconds >= MIN_SEND_INTERVAL_SECONDS)) {
        user.settings.sendIntervalSeconds = MIN_SEND_INTERVAL_SECONDS;
        changed = true;
      }
      for (const campaign of user.campaigns) {
        if (campaign.snapshot && !(campaign.snapshot.settings.sendIntervalSeconds >= MIN_SEND_INTERVAL_SECONDS)) {
          campaign.snapshot.settings.sendIntervalSeconds = MIN_SEND_INTERVAL_SECONDS;
          changed = true;
        }
        for (const message of campaign.messages) {
          if (message.status === 'sending') {
            message.status = 'uncertain';
            message.error = 'The server restarted before Gmail acceptance was recorded. Check Gmail Sent; this message will not be retried.';
            user.queuePaused = true;
            if (campaign.snapshot) this.mailbox(campaign.snapshot).paused = true;
            changed = true;
          }
        }
        if (campaign.status === 'researching') {
          campaign.status = 'failed';
          campaign.note = 'Research was interrupted. The reserved Hunter lookup budget will not be spent again automatically.';
          changed = true;
        } else if (campaign.messages.length) this.updateCampaignStatus(campaign);
      }
    }
    for (const [key, pending] of Object.entries(this.store.data.oauth)) {
      if (pending.expiresAt < this.now()) { delete this.store.data.oauth[key]; changed = true; }
    }
    if (changed) this.persist();
  }

  async withUser(userID, action) {
    const prior = this.locks.get(userID) || Promise.resolve();
    let release;
    const held = new Promise(resolve => { release = resolve; });
    const tail = prior.catch(() => {}).then(() => held);
    this.locks.set(userID, tail);
    await prior.catch(() => {});
    try {
      if (this.halted) throw new AppError('storage_unavailable', 'Server storage needs attention. Sending has stopped.', 503);
      const user = this.store.data.users[userID];
      if (!user) throw new AppError('unauthorized', 'This session is no longer available. Connect again.', 401);
      return await action(user);
    } finally {
      release();
      if (this.locks.get(userID) === tail) this.locks.delete(userID);
    }
  }

  createSession() {
    if (this.halted) throw new AppError('storage_unavailable', 'Server storage is unavailable.', 503);
    if (Object.keys(this.store.data.users).length >= 1000) throw new AppError('capacity_limit', 'This pilot server has reached its account capacity.', 503);
    const userID = id();
    const token = randomBytes(32).toString('base64url');
    this.store.data.users[userID] = { id: userID, createdAt: iso(this.now()), settings: clone(DEFAULT_SETTINGS), hunterKey: null, google: null, resume: null, campaigns: [], queuePaused: false };
    this.store.data.sessions[hash(token)] = userID;
    this.persist();
    return { token, userId: userID };
  }

  authenticate(token) {
    if (typeof token !== 'string' || token.length < 32 || token.length > 256) throw new AppError('unauthorized', 'A valid app session is required.', 401);
    const userID = this.store.data.sessions[hash(token)];
    if (!userID || !this.store.data.users[userID]) throw new AppError('unauthorized', 'This app session is not valid.', 401);
    return userID;
  }

  getState(userID) {
    const user = this.store.data.users[userID];
    if (!user) throw new AppError('unauthorized', 'This app session is not valid.', 401);
    const mailbox = user.google && this.store.data.mailboxes[this.mailboxKey({ gmailAccountID: user.google.id, gmailEmail: user.google.email })];
    return clone({ settings: user.settings, connections: { gmailEmail: user.google?.email || null, hunterConnected: Boolean(user.hunterKey) }, resume: publicResume(user.resume), campaigns: user.campaigns.map(publicCampaign).reverse(), queuePaused: user.queuePaused || Boolean(mailbox?.paused) });
  }

  setSettings(userID, input) {
    return this.withUser(userID, user => { user.settings = validateSettings(input); this.persist(); return clone(user.settings); });
  }
  connectHunter(userID, input) {
    return this.withUser(userID, async user => {
      const key = noNewline(string(input.apiKey, 'Hunter API key', 512), 'Hunter API key');
      await this.hunter.validateKey(key);
      user.hunterKey = key;
      this.persist();
      return { connected: true };
    });
  }
  disconnectHunter(userID) {
    return this.withUser(userID, user => { user.hunterKey = null; this.persist(); return { connected: false }; });
  }
  setResume(userID, input) {
    return this.withUser(userID, user => { user.resume = validateResume(input, this.now()); this.persist(); return publicResume(user.resume); });
  }
  deleteResume(userID) {
    return this.withUser(userID, user => { user.resume = null; this.persist(); return { deleted: true }; });
  }

  connectGoogle(userID) {
    return this.withUser(userID, user => {
      const state = randomBytes(32).toString('base64url');
      const verifier = randomBytes(48).toString('base64url');
      const authorizationURL = this.google.authorizationURL(state, verifier);
      for (const [key, pending] of Object.entries(this.store.data.oauth)) if (pending.userID === user.id || pending.expiresAt < this.now()) delete this.store.data.oauth[key];
      this.store.data.oauth[hash(state)] = { userID: user.id, verifier, expiresAt: this.now() + 10 * 60 * 1000 };
      this.persist();
      return { authorizationURL };
    });
  }

  async finishGoogle({ state, code, error }) {
    if (typeof state !== 'string' || state.length > 256) throw new AppError('invalid_oauth_state', 'The Gmail connection request is missing or expired.');
    const key = hash(state);
    const pending = this.store.data.oauth[key];
    if (!pending || pending.expiresAt < this.now()) throw new AppError('invalid_oauth_state', 'The Gmail connection request is missing or expired.');
    // Consume before an external call. A callback cannot be replayed or raced.
    delete this.store.data.oauth[key];
    this.persist();
    if (error) return `${APP_CALLBACK}?result=denied`;
    if (typeof code !== 'string' || !code || code.length > 4096) throw new AppError('invalid_oauth_code', 'Google did not return an authorization code.');
    return this.withUser(pending.userID, async user => {
      const account = await this.google.finish(code, pending.verifier);
      if (user.google && (user.google.id !== account.id || user.google.email !== account.email)) this.cancelPending(user, 'Gmail account changed; create a new campaign for the new sender.');
      user.google = account;
      this.persist();
      return APP_CALLBACK;
    });
  }

  disconnectGoogle(userID) {
    return this.withUser(userID, async user => {
      const account = user.google;
      user.google = null;
      this.cancelPending(user, 'Gmail was disconnected.');
      for (const [key, pending] of Object.entries(this.store.data.oauth)) if (pending.userID === userID) delete this.store.data.oauth[key];
      this.persist();
      await this.google.revoke(account);
      return { connected: false };
    });
  }

  cancelPending(user, reason) {
    for (const campaign of user.campaigns) {
      for (const message of campaign.messages) if (pendingStatuses.has(message.status)) { message.status = 'canceled'; message.error = reason; }
      if (campaign.messages.length) { this.updateCampaignStatus(campaign); campaign.note = reason; }
    }
  }

  deleteAccount(userID) {
    return this.withUser(userID, async user => {
      const account = user.google;
      const accountKey = account && this.mailboxKey({ gmailAccountID: account.id, gmailEmail: account.email });
      for (const [key, owner] of Object.entries(this.store.data.sessions)) if (owner === userID) delete this.store.data.sessions[key];
      for (const [key, pending] of Object.entries(this.store.data.oauth)) if (pending.userID === userID) delete this.store.data.oauth[key];
      delete this.store.data.users[userID];
      if (accountKey && !Object.values(this.store.data.users).some(other => other.google?.id === account.id)) delete this.store.data.mailboxes[accountKey];
      this.persist();
      await this.google.revoke(account);
      return { deleted: true };
    });
  }

  findCampaign(user, campaignID) {
    const campaign = user.campaigns.find(value => value.id === campaignID);
    if (!campaign) throw new AppError('not_found', 'This job was not found.', 404);
    return campaign;
  }

  async diagnoseJob(userID, campaignID) {
    return this.withUser(userID, async user => {
      const campaign = this.findCampaign(user, campaignID);
      if (campaign.diagnostic) return campaign.diagnostic;
      if (!user.hunterKey) throw new AppError('hunter_required', 'Connect Hunter in Settings.');
      if (!campaign.domain || !campaign.domainConfirmed) throw new AppError('domain_required', 'Confirm the employer domain first.');
      // Persist before the paid request: retries return the saved result, never spend twice.
      campaign.diagnostic = { message: 'This diagnostic was started but its result was not confirmed. No automatic retry will be made.' };
      this.persist();
      try { campaign.diagnostic = await this.hunter.diagnose(user.hunterKey, campaign.domain); }
      catch (error) { campaign.diagnostic = { message: error instanceof AppError ? error.message : 'The diagnostic failed. No emails were queued.' }; }
      this.persist();
      return campaign.diagnostic;
    });
  }

  async searchCompanies(userID, input) {
    return this.withUser(userID, async user => {
      if (!user.hunterKey) throw new AppError('hunter_required', 'Connect Hunter in Settings to search companies.');
      return await this.hunter.findCompanies(user.hunterKey, input.query);
    });
  }

  async previewJob(userID, input) {
    if (!this.store.data.users[userID]) throw new AppError('unauthorized', 'Connect Relay first.', 401);
    const details = parseJobInput(input);
    try { return parseJobInput(await this.resolver.resolve(details)); }
    catch { return details; } // Manual input remains available during provider outages.
  }

  importJob(userID, input) {
    return this.withUser(userID, async user => {
      const details = parseJobInput(input);
      const clientRequestID = input.clientRequestID ?? null;
      if (clientRequestID !== null && (typeof clientRequestID !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(clientRequestID))) throw new AppError('invalid_request_id', 'Use a UUID for the import identifier.');
      if (!details.url && !clientRequestID) throw new AppError('request_id_required', 'A manual job needs a stable import identifier.');
      const existing = user.campaigns.find(campaign => (details.url && campaign.url === details.url) || (clientRequestID && campaign.clientRequestID === clientRequestID));
      if (existing) return publicCampaign(existing);
      if (user.campaigns.length >= 500) throw new AppError('campaign_limit', 'This pilot account has reached its 500-job limit.', 409);
      const campaign = { id: id(), ...details, clientRequestID, domainConfirmed: Boolean(details.domain), createdAt: iso(this.now()), status: 'needs_details', contacts: [], messages: [], budgetReserved: 0, snapshot: null };
      user.campaigns.push(campaign);
      this.persist();
      await this.prepare(user, campaign);
      return publicCampaign(campaign);
    });
  }

  patchJob(userID, campaignID, input) {
    return this.withUser(userID, async user => {
      const campaign = this.findCampaign(user, campaignID);
      const details = parseJobInput(input, campaign);
      const correction = campaign.status === 'failed' && campaign.fetchedCount === 0 && campaign.messages.length === 0 && campaign.contacts.length === 0 && input.domain !== undefined && details.domain && details.domain !== campaign.domain;
      if (!correction && (campaign.budgetReserved || campaign.snapshot || campaign.messages.length || !['needs_details', 'failed'].includes(campaign.status))) throw new AppError('campaign_locked', 'This lookup cannot be repeated. Only a confirmed zero-result lookup with a corrected email domain can be retried.', 409);
      if (details.url && user.campaigns.some(other => other.id !== campaign.id && other.url === details.url)) throw new AppError('duplicate_job', 'This job has already been shared.', 409);
      if (correction) {
        campaign.lookupHistory ||= [];
        campaign.lookupHistory.push({ domain: campaign.domain, fetchedCount: 0, budgetReserved: campaign.budgetReserved, correctedAt: iso(this.now()) });
        campaign.budgetReserved = 0;
        campaign.snapshot = null;
        delete campaign.fetchedCount;
        campaign.requireReview = true;
      }
      if (details.company !== campaign.company && input.domain === undefined) details.domain = '';
      campaign.domainConfirmed = Boolean(details.domain) && (input.domain !== undefined || (campaign.domainConfirmed === true && details.company === campaign.company));
      Object.assign(campaign, details);
      campaign.note = '';
      this.persist();
      await this.prepare(user, campaign);
      return publicCampaign(campaign);
    });
  }

  async prepare(user, campaign) {
    try {
      // Job-board enrichment is optional when the user already supplied the role.
      // A provider outage must not prevent a manually entered opportunity.
      if ((!campaign.title || !campaign.company || !campaign.description) && campaign.url) {
        try { Object.assign(campaign, await this.resolver.resolve(campaign)); }
        catch { /* Missing fields are handled below; supplied details survive outages. */ }
      }
      if (!campaign.title || !campaign.company) throw new AppError('job_details_missing', 'Confirm the job title and company to continue.');
      if (!user.hunterKey) throw new AppError('hunter_required', 'Connect Hunter in Settings to look up this company.');
      if (!campaign.domain && this.hunter.findDomain) {
        const domain = await this.hunter.findDomain(user.hunterKey, campaign.company);
        if (domain) { campaign.domain = employerEmailDomain(campaign.company, domain); campaign.domainConfirmed = false; }
      }
      if (campaign.domain && user.settings.autoConfirmCompany === true) campaign.domainConfirmed = true;
      if (!campaign.domain) {
        campaign.status = 'needs_details';
        campaign.note = 'No confident company match was found. Enter the employer website to continue.';
      } else if (campaign.domainConfirmed !== true) {
        campaign.status = 'needs_details';
        campaign.note = `Is ${campaign.domain} the website for ${campaign.company}? Confirm it before Relay searches for contacts.`;
      } else {
        await this.researchInternal(user, campaign);
      }
    } catch (error) {
      campaign.status = campaign.budgetReserved ? 'failed' : 'needs_details';
      campaign.lookupFailed = campaign.budgetReserved > 0 && campaign.fetchedCount === undefined;
      campaign.note = error instanceof AppError ? error.message : 'The job could not be processed. Check its details and try again.';
    }
    this.persist();
  }

  researchJob(userID, campaignID, input = {}) {
    return this.withUser(userID, async user => {
      const campaign = this.findCampaign(user, campaignID);
      if (['ready', 'queued', 'sending', 'completed', 'partial', 'uncertain', 'canceled'].includes(campaign.status)) return publicCampaign(campaign);
      if (input.retryLookup === true) {
        if (!publicCampaign(campaign).canRetryLookup) throw new AppError('retry_not_available', 'This lookup cannot be retried again.', 409);
        campaign.lookupHistory ||= [];
        campaign.lookupHistory.push({ domain: campaign.domain, budgetReserved: campaign.budgetReserved, failedAt: iso(this.now()), note: campaign.note });
        campaign.lookupRetryUsed = true;
        campaign.requireReview = true;
        campaign.budgetReserved = 0;
        campaign.snapshot = null;
        campaign.lookupFailed = false;
        this.persist();
      }
      if (input.broadenSearch === true) {
        if (campaign.status !== 'failed' || campaign.fetchedCount !== 0 || campaign.messages.length || campaign.contacts.length || campaign.broadenedSearch) throw new AppError('retry_not_available', 'A broader search is only available once after a confirmed zero-result lookup.', 409);
        campaign.lookupHistory ||= [];
        campaign.lookupHistory.push({ domain: campaign.domain, fetchedCount: 0, budgetReserved: campaign.budgetReserved, broadenedAt: iso(this.now()) });
        campaign.broadenedSearch = true;
        campaign.requireReview = true;
        campaign.budgetReserved = 0;
        campaign.snapshot = null;
        delete campaign.fetchedCount;
        this.persist();
      }
      if (campaign.budgetReserved) throw new AppError('lookup_budget_spent', 'This job’s Hunter request has already been attempted. It will not consume another contact lookup budget.', 409);
      if (input.confirmedDomain !== undefined) {
        const confirmed = normalizeDomain(input.confirmedDomain);
        if (!confirmed || confirmed !== campaign.domain) throw new AppError('company_changed', 'The company website changed. Review the latest details before confirming.', 409);
        campaign.domainConfirmed = true;
      }
      await this.prepare(user, campaign);
      return publicCampaign(campaign);
    });
  }

  async researchInternal(user, campaign) {
    if (!campaign.title || !campaign.company || !campaign.domain) throw new AppError('job_details_missing', 'Add the title, company, and employer website domain.');
    if (campaign.domainConfirmed !== true) throw new AppError('company_confirmation_required', 'Confirm the employer website before finding contacts.');
    if (!user.hunterKey) throw new AppError('hunter_required', 'Connect Hunter in Settings > Connected accounts, then research this job again.');
    if (!user.google) throw new AppError('gmail_required', 'Connect Gmail in Settings > Connected accounts, then research this job again.');
    if (!user.settings.senderName) throw new AppError('sender_required', 'Open Templates, enter your Sender name at the top, and tap Save. Then research this job again.');
    if (user.settings.attachResume && !user.resume) throw new AppError('resume_required', 'Upload a résumé PDF or switch off the attachment, then research again.');
    if (campaign.budgetReserved) throw new AppError('lookup_budget_spent', 'The contact lookup budget is already reserved for this job.', 409);
    // Reserve the entire budget before the request; a timeout cannot silently cause a second paid lookup.
    campaign.budgetReserved = user.settings.maxContacts;
    campaign.snapshot = clone({ settings: user.settings, resume: user.settings.attachResume ? user.resume : null, gmailAccountID: user.google.id, gmailEmail: user.google.email });
    if (campaign.requireReview) campaign.snapshot.settings.sendingMode = 'review';
    if (campaign.broadenedSearch) campaign.snapshot.settings.recipientPreference = 'any';
    campaign.status = 'researching';
    campaign.note = 'Finding contacts within your saved lookup limit.';
    this.persist();
    const emails = await this.hunter.search(user.hunterKey, campaign, campaign.snapshot.settings);
    campaign.fetchedCount = emails.length;
    campaign.contacts = rankContacts(emails, campaign, campaign.snapshot.settings).filter(contact => !this.suppressed(campaign.snapshot, contact.email, campaign.id));
    campaign.messages = campaign.contacts.map(contact => renderMessage(campaign, contact, campaign.snapshot.settings));
    if (!campaign.messages.length) {
      campaign.status = 'failed';
      campaign.note = emails.length === 0
        ? (campaign.broadenedSearch ? `Hunter returned no verified, named personal addresses for ${campaign.domain}, even without department or seniority filters. No emails were queued.` : `No contacts matched this search at ${campaign.domain}. Try a broader verified search or check your contact preference. No emails were queued.`)
        : `Hunter returned ${emails.length} of at most ${campaign.budgetReserved} contacts, but none passed Relay’s verification, relevance, and duplicate checks. No additional contacts were fetched.`;
    } else {
      campaign.status = 'ready';
      campaign.note = `${campaign.contacts.length} eligible contacts from ${emails.length} addresses fetched (limit ${campaign.budgetReserved}). ${campaign.snapshot.resume ? `Résumé: ${campaign.snapshot.resume.filename}. ` : ''}Sender: ${campaign.snapshot.gmailEmail}.`;
      if (campaign.snapshot.settings.sendingMode === 'automatic') this.approveInternal(user, campaign);
    }
  }

  approveJob(userID, campaignID) {
    return this.withUser(userID, user => {
      const campaign = this.findCampaign(user, campaignID);
      if (campaign.approvedAt) return publicCampaign(campaign);
      this.approveInternal(user, campaign);
      this.persist();
      return publicCampaign(campaign);
    });
  }

  approveInternal(user, campaign) {
    if (campaign.status !== 'ready' || !campaign.snapshot || !campaign.messages.length) throw new AppError('campaign_not_ready', 'This campaign is not ready to schedule.', 409);
    if (!user.google || user.google.id !== campaign.snapshot.gmailAccountID || user.google.email !== campaign.snapshot.gmailEmail) throw new AppError('sender_changed', 'Reconnect the same Gmail account used for these drafts.', 409);
    for (const message of campaign.messages) {
      if (message.status !== 'draft') throw new AppError('invalid_campaign', 'This campaign has already changed.', 409);
      // Recompute from the frozen values to catch an incomplete or corrupted stored draft.
      const contact = campaign.contacts.find(contact => contact.id === message.contactId);
      if (!contact || contact.verification !== 'valid') throw new AppError('invalid_recipient', 'A recipient is no longer valid.', 409);
      const rendered = renderMessage(campaign, contact, campaign.snapshot.settings);
      if (message.to !== rendered.to || message.subject !== rendered.subject || message.body !== rendered.body) throw new AppError('snapshot_changed', 'The saved email snapshot is inconsistent. Sending has stopped.', 409);
    }
    for (const message of campaign.messages) {
      if (this.suppressed(campaign.snapshot, message.to, campaign.id)) {
        message.status = 'canceled'; message.error = 'This recipient is already queued or was contacted within 30 days.';
      } else if (this.recipientAllowlist.size && !this.recipientAllowlist.has(message.to)) {
        message.status = 'canceled'; message.error = 'The server’s test recipient allowlist excludes this address.';
      } else message.status = 'queued';
    }
    campaign.approvedAt = iso(this.now());
    this.updateCampaignStatus(campaign);
  }

  cancelJob(userID, campaignID) {
    return this.withUser(userID, user => {
      const campaign = this.findCampaign(user, campaignID);
      for (const message of campaign.messages) if (pendingStatuses.has(message.status)) message.status = 'canceled';
      if (campaign.messages.length) this.updateCampaignStatus(campaign); else campaign.status = 'canceled';
      campaign.note = 'Remaining emails canceled. Email already submitted to Gmail cannot be recalled.';
      this.persist();
      return publicCampaign(campaign);
    });
  }

  pauseQueue(userID, paused) {
    return this.withUser(userID, user => {
      user.queuePaused = paused;
      if (user.google) this.mailbox({ gmailAccountID: user.google.id, gmailEmail: user.google.email }).paused = paused;
      this.persist();
      return { queuePaused: paused };
    });
  }

  mailboxKey(snapshot) { return hash(`${snapshot.gmailAccountID}\n${snapshot.gmailEmail}`); }
  mailbox(snapshot) {
    return this.store.data.mailboxes[this.mailboxKey(snapshot)] ||= { nextSendAt: 0, attempts: [], contacted: {}, paused: false };
  }

  suppressed(snapshot, email, excludingCampaignID) {
    const box = this.mailbox(snapshot);
    if (box.contacted[email] && box.contacted[email] > this.now() - COOLDOWN) return true;
    return Object.values(this.store.data.users).some(user => user.campaigns.some(campaign => campaign.id !== excludingCampaignID && campaign.snapshot && this.mailboxKey(campaign.snapshot) === this.mailboxKey(snapshot) && campaign.messages.some(message => message.to === email && ['queued', 'sending', 'uncertain'].includes(message.status))));
  }

  updateCampaignStatus(campaign) {
    const statuses = campaign.messages.map(message => message.status);
    if (!statuses.length) return;
    if (statuses.includes('uncertain')) campaign.status = 'uncertain';
    else if (statuses.includes('sending')) campaign.status = 'sending';
    else if (statuses.includes('queued')) campaign.status = 'queued';
    else if (statuses.includes('draft')) campaign.status = 'ready';
    else if (statuses.every(status => status === 'submitted')) campaign.status = 'completed';
    else if (statuses.includes('submitted')) campaign.status = 'partial';
    else if (statuses.every(status => status === 'canceled')) campaign.status = 'canceled';
    else campaign.status = 'failed';
  }

  async tick() {
    if (this.ticking || this.halted) return;
    this.ticking = true;
    try {
      // One global worker: serialized account updates and sends, including duplicate sessions for one mailbox.
      for (const userID of Object.keys(this.store.data.users)) {
        await this.withUser(userID, async user => {
          if (user.queuePaused || !user.google) return;
          const candidates = user.campaigns.filter(campaign => campaign.snapshot && campaign.messages.some(message => message.status === 'queued'));
          for (const campaign of candidates) {
            const box = this.mailbox(campaign.snapshot);
            if (box.paused || mailboxAvailableAt(box, user.settings, campaign.snapshot.settings) > this.now()) continue;
            if (user.google.id !== campaign.snapshot.gmailAccountID || user.google.email !== campaign.snapshot.gmailEmail) continue;
            box.attempts = box.attempts.filter(time => time > this.now() - DAY);
            const dailyLimit = Math.min(user.settings.dailyLimit, campaign.snapshot.settings.dailyLimit);
            if (box.attempts.length >= dailyLimit) continue;
            const message = campaign.messages.find(value => value.status === 'queued');
            if (box.contacted[message.to] && box.contacted[message.to] > this.now() - COOLDOWN) {
              message.status = 'canceled'; message.error = 'This mailbox contacted the recipient within 30 days.';
              this.updateCampaignStatus(campaign); this.persist(); continue;
            }
            if (this.recipientAllowlist.size && !this.recipientAllowlist.has(message.to)) {
              message.status = 'canceled'; message.error = 'Excluded by the server’s test recipient allowlist.';
              this.updateCampaignStatus(campaign); this.persist(); continue;
            }
            // Refresh failures occur before Gmail sending and are therefore definite failures.
            try { user.google = await this.google.refresh(user.google); } catch (error) {
              user.queuePaused = true; box.paused = true;
              campaign.note = 'Gmail needs reconnection. The queue is paused and no message was sent.';
              this.persist(); break;
            }
            message.status = 'sending';
            message.attemptAt = iso(this.now());
            campaign.status = 'sending';
            box.attempts.push(this.now());
            // Mark before send to block duplicates after an unknown result or process crash.
            box.contacted[message.to] = this.now();
            box.nextSendAt = this.now() + sendIntervalMilliseconds(user.settings, campaign.snapshot.settings);
            this.persist();
            try {
              message.gmailMessageId = await this.google.send(user.google, campaign.snapshot, message);
              message.status = 'submitted';
            } catch (error) {
              if (!(error instanceof ProviderError) || error.ambiguous) {
                message.status = 'uncertain';
                message.error = 'Gmail acceptance could not be confirmed. Check Gmail Sent. This message will not be retried automatically.';
                user.queuePaused = true; box.paused = true;
              } else {
                message.status = 'failed';
                message.error = error.message;
                delete box.contacted[message.to];
                if ([401, 403, 429].includes(error.providerStatus)) { user.queuePaused = true; box.paused = true; }
              }
            }
            // Enforce a full interval after completion, even if a provider response took longer than the interval.
            box.lastCompletedAt = this.now();
            box.nextSendAt = this.now() + sendIntervalMilliseconds(user.settings, campaign.snapshot.settings);
            this.updateCampaignStatus(campaign);
            this.persist();
            break; // At most one send attempt per user per tick.
          }
        });
      }
    } finally { this.ticking = false; }
  }
}
