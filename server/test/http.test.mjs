import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { MemoryStore } from '../src/store.mjs';
import { ReferralService } from '../src/service.mjs';
import { createHTTPServer } from '../src/http.mjs';

async function fixture(t, options = {}) {
  const service = new ReferralService({
    store: new MemoryStore(), google: {},
    hunter: { validateKey: async () => true, findDomain: async () => 'example.com' },
    resolver: { resolve: async value => value },
  });
  const server = createHTTPServer(service, options);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeIdleConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, body, token, headers = {}) => fetch(base + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { service, request };
}

test('HTTP imports without a link and binds confirmation to the exact suggested website', async t => {
  const { service, request } = await fixture(t);
  const session = await (await request('/v1/session', {})).json();
  await service.connectHunter(session.userId, { apiKey: 'local-fake-key' });
  const input = { title: 'iOS Engineer', company: 'Example', clientRequestID: randomUUID() };
  const created = await (await request('/v1/jobs', input, session.token)).json();
  assert.equal(created.domain, 'example.com');
  assert.equal(created.domainConfirmed, false);
  const duplicate = await (await request('/v1/jobs', input, session.token)).json();
  assert.equal(duplicate.id, created.id);
  const stale = await request(`/v1/jobs/${created.id}/research`, { confirmedDomain: 'other.com' }, session.token);
  assert.equal(stale.status, 409);
  await stale.arrayBuffer();
  const confirmed = await (await request(`/v1/jobs/${created.id}/research`, { confirmedDomain: 'example.com' }, session.token)).json();
  assert.equal(confirmed.domainConfirmed, true);
  assert.match(confirmed.note, /Connect Gmail/);
  assert.deepEqual(confirmed.messages, []);
});

test('health returns HTTP 503 when durable sending has halted', async t => {
  const { service, request } = await fixture(t);
  assert.equal((await request('/health')).status, 200);
  service.halted = true;
  const halted = await request('/health');
  assert.equal(halted.status, 503);
  assert.deepEqual(await halted.json(), { ok: false });
});

test('client-IP headers cannot bypass enrollment limits when proxy trust is off', async t => {
  const { request } = await fixture(t);
  for (let i = 1; i <= 11; i++) {
    const result = await request('/v1/session', {}, null, { 'X-Relay-Client-IP': `192.0.2.${i}` });
    assert.equal(result.status, i <= 10 ? 201 : 429);
    await result.arrayBuffer();
  }
});

test('the explicitly trusted local proxy gives distinct phones separate enrollment limits', async t => {
  const { request } = await fixture(t, { trustLoopbackProxy: true });
  for (let i = 1; i <= 11; i++) {
    const result = await request('/v1/session', {}, null, { 'X-Relay-Client-IP': `192.0.2.${i}` });
    assert.equal(result.status, 201);
    await result.arrayBuffer();
  }
});
