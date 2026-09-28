import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { nextSendTime } from '../cloudflare/schedule.mjs';
import { DEFAULT_SETTINGS } from '../src/domain.mjs';

test('alarm scheduling honors spacing, daily limits and paused queues', () => {
  const now = 100000000;
  const box = { paused: false, nextSendAt: now + 10000, attempts: [now - 5000] };
  const user = { google: { id: 'g', email: 'a@example.com' }, settings: { dailyLimit: 1 }, campaigns: [{ snapshot: { gmailAccountID: 'g', gmailEmail: 'a@example.com', settings: { dailyLimit: 1 } }, messages: [{ status: 'queued' }] }] };
  const service = { store: { data: { users: { a: user } } }, mailbox: () => box };
  assert.equal(nextSendTime(service, now), now - 5000 + 86400000 + 1);
  box.attempts = [];
  assert.equal(nextSendTime(service, now), now + 10000);
  box.paused = true;
  assert.equal(nextSendTime(service, now), null);
  box.paused = false;
  user.campaigns[0].messages[0].status = 'uncertain';
  assert.equal(nextSendTime(service, now), null);
});

test('real alarms submit once and keep remaining mail queued across restart', { timeout: 45000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'relay-alarm-test-'));
  const sends = [];
  const bindings = { PUBLIC_BASE_URL: 'https://relay.example.com', STORE_KEY_HEX: randomBytes(32).toString('hex'), ENROLLMENT_KEY: randomBytes(32).toString('base64url'), TEST_RECIPIENT_ALLOWLIST: 'one@example.com,two@example.com', GOOGLE_CLIENT_ID: 'fake.apps.googleusercontent.com', GOOGLE_CLIENT_SECRET: 'fake' };
  const outboundService = async request => {
    const url = new URL(request.url);
    if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 'fake-access', refresh_token: 'fake-refresh', expires_in: 3600, scope: 'https://www.googleapis.com/auth/gmail.send' });
    if (url.hostname === 'openidconnect.googleapis.com') return Response.json({ sub: 'fake-user', email: 'owner@example.com', email_verified: true });
    if (url.hostname === 'api.hunter.io') return Response.json(url.pathname.endsWith('/account') ? { data: {} } : { data: { emails: ['one', 'two'].map(name => ({ value: `${name}@example.com`, type: 'personal', first_name: name, last_name: 'Test', position: 'Engineering Manager', department: 'it', seniority: 'senior', confidence: 99, verification: { status: 'valid' } })) } });
    if (url.hostname === 'gmail.googleapis.com') {
      sends.push(Date.now());
      return sends.length === 1 ? Response.json({ id: 'test-gmail-id' }) : Response.json({ error: 'ambiguous test response' }, { status: 503 });
    }
    throw new Error('Unexpected outbound request in isolated test.');
  };
  const options = () => ({ ...convertV4MiniflareOptions({ name: 'relay-alarm-test', modules: true, scriptPath: 'cloudflare-dist/worker.js', compatibilityDate: '2026-09-16', compatibilityFlags: ['nodejs_compat'], durableObjects: { RELAY: { className: 'RelayPilot', useSQLite: true } }, bindings, outboundService }), resourcePersistencePath: directory });
  let mf = new Miniflare(options());
  let token;
  const call = (path, method = 'GET', data) => mf.dispatchFetch(`https://relay.example.com${path}`, { method, redirect: 'manual', headers: { 'Content-Type': 'application/json', 'X-Relay-Enrollment': bindings.ENROLLMENT_KEY, ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(data === undefined ? {} : { body: JSON.stringify(data) }) });
  const waitUntil = async predicate => { for (let i = 0; i < 120; i++) { if (await predicate()) return; await new Promise(resolve => setTimeout(resolve, 100)); } assert.fail('Alarm did not reach expected state.'); };
  try {
    token = (await (await call('/v1/session', 'POST', {})).json()).token;
    const start = await (await call('/v1/google/connect', 'POST', {})).json();
    const state = new URL(start.authorizationURL).searchParams.get('state');
    const callback = await call(`/v1/google/callback?state=${state}&code=fake`);
    assert.equal(callback.status, 302, await callback.text());
    assert.equal((await call('/v1/hunter', 'POST', { apiKey: 'fake-key' })).status, 200);
    assert.equal((await call('/v1/settings', 'PUT', { ...DEFAULT_SETTINGS, senderName: 'Test', sendIntervalSeconds: 600 })).status, 200);
    const campaign = await (await call('/v1/jobs', 'POST', { title: 'Engineer', company: 'Example', domain: 'example.com', clientRequestID: randomUUID() })).json();
    assert.equal(campaign.status, 'ready');
    assert.equal(sends.length, 0);
    await call(`/v1/jobs/${campaign.id}/approve`, 'POST', {});
    await waitUntil(() => sends.length === 1);
    await waitUntil(async () => (await (await call('/v1/state')).json()).campaigns[0].messages[0].status === 'submitted');
    await mf.dispose();
    mf = new Miniflare(options());
    // Wake storage after cold start; the persisted alarm still owns the queue.
    await call('/health');
    const recovered = await (await call('/v1/state')).json();
    assert.deepEqual(recovered.campaigns[0].messages.map(message => message.status), ['submitted', 'queued']);
    assert.equal(recovered.queuePaused, false);
    assert.equal(recovered.settings.sendIntervalSeconds, 600);
    await new Promise(resolve => setTimeout(resolve, 1200));
    assert.equal(sends.length, 1);
  } finally { await mf.dispose(); await rm(directory, { recursive: true, force: true }); }
});

test('Workers runtime persists encrypted PDF chunks, isolates sessions and refuses uninvited enrollment', { timeout: 60000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'relay-worker-test-'));
  const bindings = { PUBLIC_BASE_URL: 'https://relay.example.com', STORE_KEY_HEX: randomBytes(32).toString('hex'), ENROLLMENT_KEY: randomBytes(32).toString('base64url'), TEST_RECIPIENT_ALLOWLIST: 'test@example.com' };
  const options = { modules: true, scriptPath: 'cloudflare-dist/worker.js', compatibilityDate: '2026-09-16', compatibilityFlags: ['nodejs_compat'], durableObjects: { RELAY: { className: 'RelayPilot', useSQLite: true } }, durableObjectsPersist: directory, bindings };
  const runtimeOptions = () => ({ ...convertV4MiniflareOptions(options), resourcePersistencePath: directory });
  let mf = new Miniflare(runtimeOptions());
  const call = (path, method = 'GET', data, token, invited = true) => mf.dispatchFetch(`https://relay.example.com${path}`, {
    method, headers: { 'Content-Type': 'application/json', ...(invited ? { 'X-Relay-Enrollment': bindings.ENROLLMENT_KEY } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data === undefined ? {} : { body: JSON.stringify(data) }),
  });
  try {
    assert.equal((await call('/health')).status, 200);
    assert.equal((await call('/v1/session', 'POST', {}, null, false)).status, 403);
    const session = await (await call('/v1/session', 'POST', {})).json();
    assert.ok(session.token);
    assert.equal((await call('/v1/state', 'GET', undefined, 'wrong')).status, 401);
    const pdf = Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.alloc(3 * 1024 * 1024, 65)]);
    assert.equal((await call('/v1/resume', 'POST', { filename: 'resume.pdf', dataBase64: pdf.toString('base64') }, session.token)).status, 200);
    const job = await (await call('/v1/jobs', 'POST', { title: 'Engineer', company: 'Example', clientRequestID: randomUUID() }, session.token)).json();
    assert.ok(job.id);
    const other = await (await call('/v1/session', 'POST', {})).json();
    assert.equal((await (await call('/v1/state', 'GET', undefined, other.token)).json()).resume, null);
    assert.equal((await call(`/v1/jobs/${job.id}/cancel`, 'POST', {}, other.token)).status, 404);
    await mf.dispose();
    mf = new Miniflare(runtimeOptions());
    const recoveryResponse = await call('/v1/state', 'GET', undefined, session.token);
    const recovered = await recoveryResponse.json();
    assert.equal(recoveryResponse.status, 200, JSON.stringify(recovered));
    assert.equal(recovered.resume.byteCount, pdf.length);
    assert.equal(recovered.campaigns[0].id, job.id);
    assert.equal(recovered.resume.dataBase64, undefined);
    assert.equal((await call('/v1/account', 'DELETE', undefined, session.token)).status, 200);
    assert.equal((await call('/v1/state', 'GET', undefined, session.token)).status, 401);
  } finally { await mf.dispose(); await rm(directory, { recursive: true, force: true }); }
});
