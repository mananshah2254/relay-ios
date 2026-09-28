import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { MemoryStore } from '../src/store.mjs';
import { ProviderError } from '../src/providers.mjs';
import { ReferralService } from '../src/service.mjs';

const job = { url: 'https://example.com/jobs/ios', title: 'iOS Engineer', company: 'Example Studio', domain: 'example.com' };
const account = { id: 'google-user', email: 'sender@example.com', accessToken: 'access', refreshToken: 'refresh', expiresAt: Number.MAX_SAFE_INTEGER };

test('ten-minute pacing is shared across jobs and sessions with no catch-up burst', async () => {
  let now = Date.now();
  const { service, store, calls } = makeService({ now: () => now });
  const first = await readyAccount(service, store, { sendingMode: 'automatic' });
  const second = await readyAccount(service, store, { sendingMode: 'automatic' });
  let contact = 0;
  service.hunter.search = async () => [{ value: `person${++contact}@example.com`, type: 'personal', first_name: 'Morgan', last_name: 'Lee', position: 'Engineering Manager', department: 'it', seniority: 'senior', confidence: 99, verification: { status: 'valid' } }];
  for (let i = 0; i < 8; i++) {
    await service.importJob(i % 2 ? first.userId : second.userId, { ...job, url: `https://example.com/jobs/${i}` });
  }
  const start = now;
  for (let minute = 0; minute < 60; minute++) {
    now = start + minute * 60000;
    await service.tick();
    assert.equal(calls.sends, Math.floor(minute / 10) + 1);
  }
  assert.equal(calls.sends, 6);
  now += 3 * 3600000;
  await service.tick();
  await service.tick();
  assert.equal(calls.sends, 7, 'A delayed alarm must not send a catch-up burst');
});

test('longer current settings slow old queued jobs and completion starts the gap', async () => {
  let now = Date.now();
  const { service, store, calls } = makeService({ now: () => now, send: async () => { now += 30000; return 'gmail-id'; } });
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  const campaign = await service.importJob(session.userId, job);
  const saved = store.data.users[session.userId].campaigns[0];
  saved.messages.push({ ...saved.messages[0], id: randomUUID(), to: 'second@example.com' });
  await service.tick();
  const completion = now;
  await service.setSettings(session.userId, { ...service.getState(session.userId).settings, sendIntervalSeconds: 1200 });
  now = completion + 600000;
  await service.tick();
  assert.equal(calls.sends, 1);
  now = completion + 1199999;
  await service.tick();
  assert.equal(calls.sends, 1);
  now = completion + 1200000;
  await service.tick();
  assert.equal(calls.sends, 2);
  assert.equal(service.getState(session.userId).campaigns[0].id, campaign.id);
});

test('legacy fast settings migrate without sending, unpausing, or accelerating longer delays', async () => {
  let now = Date.now();
  const { service, store, calls } = makeService({ now: () => now });
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  await service.importJob(session.userId, job);
  const user = store.data.users[session.userId];
  user.settings.sendIntervalSeconds = 10;
  user.campaigns[0].snapshot.settings.sendIntervalSeconds = 5;
  const box = service.mailbox(user.campaigns[0].snapshot);
  box.attempts = [now - 1000];
  box.nextSendAt = now + 900000;
  box.paused = true;
  service.recover();
  assert.equal(user.settings.sendIntervalSeconds, 600);
  assert.equal(user.campaigns[0].snapshot.settings.sendIntervalSeconds, 600);
  assert.equal(box.nextSendAt, now + 900000);
  assert.equal(box.paused, true);
  assert.equal(user.campaigns[0].messages[0].status, 'queued');
  await service.tick();
  assert.equal(calls.sends, 0);
  await assert.rejects(service.setSettings(session.userId, { ...user.settings, sendIntervalSeconds: 599 }), /600/);
});

test('failed lookup has one explicit recovery attempt which forces review', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  const search = service.hunter.search;
  service.hunter.search = async () => { throw new ProviderError('Hunter', 0, false, true); };
  const failed = await service.importJob(session.userId, job);
  assert.equal(failed.canRetryLookup, true);
  service.hunter.search = search;
  const recovered = await service.researchJob(session.userId, failed.id, { retryLookup: true });
  assert.equal(recovered.status, 'ready');
  assert.ok(recovered.messages.every(message => message.status === 'draft'));
  assert.equal(recovered.canRetryLookup, false);
  assert.equal(calls.sends, 0);
});

test('repeated transport failure cannot repeat paid recovery indefinitely', async () => {
  const { service, store } = makeService();
  const session = await readyAccount(service, store);
  service.hunter.search = async () => { throw new ProviderError('Hunter', 0); };
  const failed = await service.importJob(session.userId, job);
  await service.researchJob(session.userId, failed.id, { retryLookup: true });
  await assert.rejects(service.researchJob(session.userId, failed.id, { retryLookup: true }), /cannot be retried/);
});

test('diagnostic is one-shot and never queues or sends even in automatic mode', async () => {
  const { service, store, calls } = makeService({ search: [] });
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  service.hunter.search = async () => [];
  const campaign = await service.importJob(session.userId, job);
  let diagnostics = 0;
  service.hunter.diagnose = async () => { diagnostics++; return { message: 'sample counts only' }; };
  assert.deepEqual(await service.diagnoseJob(session.userId, campaign.id), { message: 'sample counts only' });
  await service.diagnoseJob(session.userId, campaign.id);
  assert.equal(diagnostics, 1);
  assert.equal(calls.sends, 0);
  assert.equal(store.data.users[session.userId].campaigns[0].messages.length, 0);
});

test('confirmed zero-result domain correction retries explicitly and forces email review', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  const originalSearch = service.hunter.search;
  service.hunter.search = async () => [];
  const failed = await service.importJob(session.userId, { ...job, domain: 'wrong.example.com' });
  assert.equal(failed.status, 'failed');
  assert.match(failed.note, /No contacts matched this search at wrong.example.com/);
  await assert.rejects(service.patchJob(session.userId, failed.id, { domain: 'wrong.example.com' }), /cannot be repeated/);
  service.hunter.search = originalSearch;
  const corrected = await service.patchJob(session.userId, failed.id, { domain: 'example.com' });
  assert.equal(corrected.status, 'ready');
  assert.equal(corrected.messages[0].status, 'draft');
  assert.equal(calls.sends, 0);
  assert.equal(store.data.users[session.userId].campaigns[0].lookupHistory[0].domain, 'wrong.example.com');
  await assert.rejects(service.patchJob(session.userId, failed.id, { domain: 'another.example.com' }), /cannot be repeated/);
});

test('ambiguous or failed Hunter requests cannot reset budget through domain editing', async () => {
  const { service, store } = makeService({ search: new ProviderError('Hunter', 503) });
  const session = await readyAccount(service, store);
  const failed = await service.importJob(session.userId, job);
  await assert.rejects(service.patchJob(session.userId, failed.id, { domain: 'another.example.com' }), /cannot be repeated/);
});

test('broader recovery is bounded and never automatically sends', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  const search = service.hunter.search;
  service.hunter.search = async () => [];
  const failed = await service.importJob(session.userId, job);
  assert.equal(failed.canBroadenSearch, true);
  service.hunter.search = async (key, campaign, settings) => {
    assert.equal(settings.recipientPreference, 'any');
    assert.equal(settings.maxContacts, 5);
    return search(key, campaign, settings);
  };
  const recovered = await service.researchJob(session.userId, failed.id, { broadenSearch: true });
  assert.equal(recovered.status, 'ready');
  assert.equal(recovered.messages[0].status, 'draft');
  assert.equal(recovered.canBroadenSearch, false);
  await service.researchJob(session.userId, failed.id, { broadenSearch: true });
  assert.equal(calls.searches, 1);
  assert.equal(calls.sends, 0);
});

test('broader lookup is offered once and cannot retry an ambiguous failure', async () => {
  const { service, store } = makeService();
  const session = await readyAccount(service, store);
  service.hunter.search = async () => [];
  const failed = await service.importJob(session.userId, job);
  const retried = await service.researchJob(session.userId, failed.id, { broadenSearch: true });
  assert.equal(retried.canBroadenSearch, false);
  await assert.rejects(service.researchJob(session.userId, failed.id, { broadenSearch: true }), /only available once/);
  const second = makeService({ search: new ProviderError('Hunter', 503) });
  const other = await readyAccount(second.service, second.store);
  const uncertain = await second.service.importJob(other.userId, job);
  assert.equal(uncertain.canBroadenSearch, false);
  await assert.rejects(second.service.researchJob(other.userId, uncertain.id, { broadenSearch: true }), /only available once/);
});

test('opt-in company confirmation plus automatic sending queues without another approval', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { autoConfirmCompany: true, sendingMode: 'automatic' });
  const campaign = await service.importJob(session.userId, { ...job, domain: '' });
  assert.equal(campaign.domainConfirmed, true);
  assert.equal(campaign.status, 'queued');
  assert.equal(calls.searches, 1);
  assert.equal(calls.sends, 0);
});

test('company auto-confirm alone preserves email review and unmatched company still stops', async () => {
  const { service, store } = makeService();
  const session = await readyAccount(service, store, { autoConfirmCompany: true });
  const campaign = await service.importJob(session.userId, { ...job, domain: '' });
  assert.equal(campaign.status, 'ready');
  assert.equal(campaign.messages[0].status, 'draft');
  const missing = makeService({ resolvedDomain: '' });
  const other = await readyAccount(missing.service, missing.store, { autoConfirmCompany: true, sendingMode: 'automatic' });
  const unresolved = await missing.service.importJob(other.userId, { ...job, domain: '' });
  assert.equal(unresolved.status, 'needs_details');
  assert.equal(missing.calls.searches, 0);
});

test('preview is read-only and never spends Hunter credits or sends', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { autoConfirmCompany: true, sendingMode: 'automatic' });
  const result = await service.previewJob(session.userId, { url: 'https://www.linkedin.com/jobs/view/123', sharedText: 'Check out this job at Example Studio: Software Engineer' });
  assert.equal(result.title, 'Software Engineer');
  assert.equal(result.company, 'Example Studio');
  assert.equal(store.data.users[session.userId].campaigns.length, 0);
  assert.deepEqual(calls, { searches: 0, sends: 0, domains: 0 });
});

function makeService({ send = async () => 'gmail-message-1', search = null, now = () => Date.now(), recipientAllowlist = [], resolvedDomain = 'example.com' } = {}) {
  const calls = { searches: 0, sends: 0, domains: 0 };
  const hunter = {
    async validateKey() { return true; },
    async findDomain() { calls.domains += 1; return resolvedDomain; },
    async search() {
      calls.searches += 1;
      if (search) throw search;
      return [{ value: 'manager@example.com', type: 'personal', first_name: 'Morgan', last_name: 'Lee', position: 'Engineering Manager', department: 'it', seniority: 'senior', confidence: 90, verification: { status: 'valid' } }];
    },
  };
  const google = {
    authorizationURL: () => 'https://accounts.google.com/o/oauth2/v2/auth?state=test',
    async refresh(value) { return value; },
    async send(...args) { calls.sends += 1; return send(...args); },
    async revoke() {},
  };
  const resolver = { async resolve(value) { return value; } };
  const store = new MemoryStore();
  const service = new ReferralService({ store, hunter, google, resolver, now, recipientAllowlist });
  return { service, store, calls };
}

async function readyAccount(service, store, settings = {}) {
  const session = service.createSession();
  store.data.users[session.userId].google = { ...account };
  await service.connectHunter(session.userId, { apiKey: 'hunter-test-key' });
  await service.setSettings(session.userId, {
    senderName: 'Taylor',
    subjectTemplate: 'Referral for {{job_title}}',
    bodyTemplate: 'Hi {{first_name}},\n\nCould you refer me for {{company}}? {{job_url}}\n\n{{sender_name}}',
    maxContacts: 5, sendIntervalSeconds: 600, dailyLimit: 10,
    recipientPreference: 'relevant', sendingMode: 'review', attachResume: false,
    ...settings,
  });
  return session;
}

test('import is idempotent and automatic mode queues then sends one message', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  const first = await service.importJob(session.userId, job);
  assert.equal(first.status, 'queued');
  assert.equal(first.messages[0].status, 'queued');
  const duplicate = await service.importJob(session.userId, { ...job, url: `${job.url}?utm_source=linkedin` });
  assert.equal(duplicate.id, first.id);
  assert.equal(calls.searches, 1);
  await service.tick();
  const after = service.getState(session.userId).campaigns[0];
  assert.equal(after.messages[0].status, 'submitted');
  assert.equal(after.status, 'completed');
  assert.equal(calls.sends, 1);
});

test('review mode freezes message snapshot and never sends before approval', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store);
  const campaign = await service.importJob(session.userId, job);
  assert.equal(campaign.status, 'ready');
  assert.equal(campaign.messages[0].status, 'draft');
  await service.tick();
  assert.equal(calls.sends, 0);
  const approved = await service.approveJob(session.userId, campaign.id);
  assert.equal(approved.messages[0].status, 'queued');
  await service.tick();
  assert.equal(service.getState(session.userId).campaigns[0].messages[0].status, 'submitted');
});

test('an ambiguous provider result pauses the queue and is never retried automatically', async () => {
  const { service, store, calls } = makeService({ send: async () => { throw new ProviderError('Gmail', 503, true); } });
  const session = await readyAccount(service, store);
  const campaign = await service.importJob(session.userId, job);
  await service.approveJob(session.userId, campaign.id);
  await service.tick();
  const state = service.getState(session.userId);
  assert.equal(state.queuePaused, true);
  assert.equal(state.campaigns[0].messages[0].status, 'uncertain');
  await service.tick();
  assert.equal(calls.sends, 1);
});

test('a failed research attempt reserves its Hunter budget and cannot be silently repeated', async () => {
  let now = Date.now();
  const { service, store } = makeService({ now: () => now, search: new Error('Hunter unavailable') });
  const session = await readyAccount(service, store);
  const campaign = await service.importJob(session.userId, { ...job, url: 'https://example.com/jobs/2' });
  assert.equal(campaign.status, 'failed');
  assert.equal(store.data.users[session.userId].campaigns[0].budgetReserved, 5);
  now += 1000;
  await assert.rejects(() => service.researchJob(session.userId, campaign.id), /already been attempted|not consume/);
});

test('manual jobs need no URL, retry by stable identifier, and do not merge unrelated jobs', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store);
  const input = { ...job, url: '', clientRequestID: randomUUID() };
  const first = await service.importJob(session.userId, input);
  const retry = await service.importJob(session.userId, input);
  assert.equal(first.id, retry.id);
  assert.equal(first.status, 'ready');
  assert.equal(first.url, '');
  assert.equal(calls.searches, 1);
  assert.doesNotMatch(first.messages[0].body, /undefined|null|{{/);
  const second = await service.importJob(session.userId, { ...input, clientRequestID: randomUUID(), title: 'Platform Engineer' });
  assert.notEqual(first.id, second.id);
  await assert.rejects(() => service.importJob(session.userId, { ...input, clientRequestID: null }), /stable import identifier/);
});

test('automatic sending cannot cross an unconfirmed company suggestion', async () => {
  const { service, store, calls } = makeService();
  const session = await readyAccount(service, store, { sendingMode: 'automatic' });
  const campaign = await service.importJob(session.userId, { ...job, domain: '' });
  assert.equal(campaign.domain, 'example.com');
  assert.equal(campaign.domainConfirmed, false);
  assert.equal(campaign.status, 'needs_details');
  await service.researchJob(session.userId, campaign.id);
  await service.tick();
  assert.equal(calls.domains, 1);
  assert.equal(calls.searches, 0);
  assert.equal(calls.sends, 0);
  await assert.rejects(() => service.researchJob(session.userId, campaign.id, { confirmedDomain: 'wrong.com' }), /website changed/);
  const confirmed = await service.researchJob(session.userId, campaign.id, { confirmedDomain: 'example.com' });
  assert.equal(confirmed.domainConfirmed, true);
  assert.equal(confirmed.status, 'queued');
  assert.equal(calls.searches, 1);
  await service.tick();
  assert.equal(calls.sends, 1);
});

test('company matching works before Gmail setup and unmatched companies spend no contact budget', async () => {
  const { service, store, calls } = makeService({ resolvedDomain: null });
  const session = service.createSession();
  await service.connectHunter(session.userId, { apiKey: 'test-key' });
  const campaign = await service.importJob(session.userId, { ...job, domain: '' });
  assert.equal(calls.domains, 1);
  assert.equal(calls.searches, 0);
  assert.equal(campaign.status, 'needs_details');
  assert.match(campaign.note, /No confident company match/);
  assert.equal(store.data.users[session.userId].campaigns[0].budgetReserved, 0);
});

test('an edited company cannot retain a previous automatic domain suggestion', async () => {
  const { service } = makeService();
  const session = service.createSession();
  // No providers configured: user-supplied details are saved for later setup.
  const first = await service.importJob(session.userId, job);
  const edited = await service.patchJob(session.userId, first.id, { company: 'Another Company' });
  assert.equal(edited.domain, '');
  assert.equal(edited.domainConfirmed, false);
});
