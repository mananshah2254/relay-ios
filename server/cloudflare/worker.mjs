import { DurableObject } from 'cloudflare:workers';
import { createHash, timingSafeEqual } from 'node:crypto';
import { DurableStore } from './store.mjs';
import { nextSendTime } from './schedule.mjs';
import { recipientAllowlist } from './recipient-policy.mjs';
import { ReferralService } from '../src/service.mjs';
import { GoogleProvider, HunterProvider, JobResolver } from '../src/providers.mjs';
import { AppError } from '../src/domain.mjs';

const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers });
const digest = value => createHash('sha256').update(value).digest();
const same = (a, b) => timingSafeEqual(digest(a), digest(b));

export default {
  async fetch(request, env) {
    try {
      // A URL fragment is never transmitted by browsers; the app sends this
      // private enrollment value as a header only when creating a new session.
      const path = new URL(request.url).pathname;
      if (path === '/v1/session' && (!env.ENROLLMENT_KEY || !same(request.headers.get('X-Relay-Enrollment') || '', env.ENROLLMENT_KEY))) {
        return json({ error: { code: 'invite_required', message: 'Use your private Relay setup link to connect.' } }, 403);
      }
      return await env.RELAY.get(env.RELAY.idFromName('private-pilot-v1')).fetch(request);
    } catch {
      return json({ error: { code: 'service_unavailable', message: 'Relay is temporarily unavailable. Please try again later.' } }, 503);
    }
  },
};

export class RelayPilot extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.tail = Promise.resolve();
    this.ready = ctx.blockConcurrencyWhile(async () => {
      const origin = new URL(env.PUBLIC_BASE_URL);
      if (origin.protocol !== 'https:' || origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) throw new Error('HTTPS origin required.');
      const allowlist = recipientAllowlist(env);
      this.store = new DurableStore(ctx.storage, env.STORE_KEY_HEX);
      // Workers supports manual/follow only. Provider code rejects all non-2xx
      // responses, so manual preserves the no-redirect credential boundary.
      const fetchImpl = (input, init) => fetch(input, { ...init, redirect: 'manual' });
      const google = new GoogleProvider({ clientID: env.GOOGLE_CLIENT_ID, clientSecret: env.GOOGLE_CLIENT_SECRET, publicBaseURL: origin.origin, fetchImpl });
      // Explicitly wait for the pre-send marker to be durable before contacting Gmail.
      const send = google.send.bind(google);
      google.send = async (...args) => { await ctx.storage.sync(); return send(...args); };
      this.service = new ReferralService({ store: this.store, google, hunter: new HunterProvider({ fetchImpl }), resolver: new JobResolver({ fetchImpl }), recipientAllowlist: allowlist });
      ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS relay_limits (key TEXT PRIMARY KEY, start INTEGER, count INTEGER)');
    });
  }
  async exclusive(action) {
    const prior = this.tail;
    let release;
    this.tail = new Promise(resolve => { release = resolve; });
    await prior;
    try { await this.ready; return await action(); } finally { release(); }
  }
  limit(key, maximum, duration) {
    const now = Date.now();
    const sql = this.ctx.storage.sql;
    const row = sql.exec('SELECT start, count FROM relay_limits WHERE key = ?', key).toArray()[0];
    if (row && row.start + duration > now && row.count >= maximum) throw new AppError('rate_limited', 'Please try again later.', 429);
    sql.exec('INSERT OR REPLACE INTO relay_limits VALUES (?, ?, ?)', key, row && row.start + duration > now ? row.start : now, row && row.start + duration > now ? row.count + 1 : 1);
    sql.exec('DELETE FROM relay_limits WHERE start < ?', now - 86400000);
  }
  async schedule() {
    const time = nextSendTime(this.service);
    if (time === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(time);
  }
  async fetch(request) {
    return this.exclusive(async () => {
      try {
        const url = new URL(request.url), route = url.pathname, method = request.method;
        const s = this.service;
        if (route === '/health' && method === 'GET') return json({ ok: !s.halted }, s.halted ? 503 : 200);
        this.limit('requests', 300, 60000);
        // A recovery wake-up survives eviction after an interrupted request.
        if (method !== 'GET') await this.ctx.storage.setAlarm(Date.now() + 60000);
        const result = await this.dispatch(request, url);
        await this.schedule();
        await this.ctx.storage.sync();
        return result;
      } catch (error) {
        if (!(error instanceof AppError)) this.service.halted = true;
        return json({ error: { code: error instanceof AppError ? error.code : 'service_unavailable', message: error instanceof AppError ? error.message : 'Relay needs attention. Sending has paused.' } }, error instanceof AppError ? error.status : 503);
      }
    });
  }
  async alarm() {
    return this.exclusive(async () => {
      if (this.service.halted) return;
      // Keep a recovery alarm while Gmail is in flight. Recovered sending markers
      // become uncertain, so alarm retries cannot duplicate an accepted message.
      await this.ctx.storage.setAlarm(Date.now() + 60000);
      try { await this.service.tick(); await this.schedule(); await this.ctx.storage.sync(); }
      catch { this.service.halted = true; throw new Error('Queue paused after storage failure.'); }
    });
  }
  async dispatch(request, url) {
    const s = this.service, route = url.pathname, method = request.method;
    if (method === 'GET' && route === '/v1/google/callback') {
      const location = await s.finishGoogle({ state: url.searchParams.get('state'), code: url.searchParams.get('code'), error: url.searchParams.get('error') });
      return new Response(null, { status: 302, headers: { ...headers, Location: location } });
    }
    if (method === 'POST' && route === '/v1/session') {
      this.limit('enrollment', 10, 3600000);
      await body(request);
      return json(s.createSession(), 201);
    }
    const auth = request.headers.get('Authorization') || '';
    if (!auth.startsWith('Bearer ')) throw new AppError('unauthorized', 'A valid app session is required.', 401);
    const user = s.authenticate(auth.slice(7));
    if (method === 'GET' && route === '/v1/state') return json(s.getState(user));
    if (method === 'POST' && route === '/v1/jobs/preview') {
      this.limit(`preview:${user}`, 20, 60000);
      return json(await s.previewJob(user, await body(request)));
    }
    if (method === 'POST' && route === '/v1/companies/search') {
      this.limit(`companies:${user}`, 20, 60000);
      return json(await s.searchCompanies(user, await body(request)));
    }
    let result;
    if (method === 'PUT' && route === '/v1/settings') result = await s.setSettings(user, await body(request));
    else if (method === 'POST' && route === '/v1/hunter') result = await s.connectHunter(user, await body(request));
    else if (method === 'DELETE' && route === '/v1/hunter') result = await s.disconnectHunter(user);
    else if (method === 'POST' && route === '/v1/google/connect') { await body(request); result = await s.connectGoogle(user); }
    else if (method === 'DELETE' && route === '/v1/google') result = await s.disconnectGoogle(user);
    else if (method === 'POST' && route === '/v1/resume') result = await s.setResume(user, await body(request));
    else if (method === 'DELETE' && route === '/v1/resume') result = await s.deleteResume(user);
    else if (method === 'POST' && route === '/v1/jobs') result = await s.importJob(user, await body(request));
    else if (method === 'POST' && ['/v1/queue/pause', '/v1/queue/resume'].includes(route)) { await body(request); result = await s.pauseQueue(user, route.endsWith('/pause')); }
    else if (method === 'DELETE' && route === '/v1/account') result = await s.deleteAccount(user);
    else {
      const match = route.match(/^\/v1\/jobs\/([a-zA-Z0-9-]+)(?:\/(research|approve|cancel|diagnose))?$/);
      if (!match) throw new AppError('not_found', 'This endpoint does not exist.', 404);
      const [, id, action] = match;
      if (method === 'PATCH' && !action) result = await s.patchJob(user, id, await body(request));
      else if (method === 'POST' && action) {
        const input = await body(request);
        if (action === 'research') result = await s.researchJob(user, id, input);
        else if (action === 'diagnose') result = await s.diagnoseJob(user, id);
        else if (action === 'approve') result = await s.approveJob(user, id);
        else result = await s.cancelJob(user, id);
      } else throw new AppError('method_not_allowed', 'Unsupported method.', 405);
    }
    return json(result);
  }
}

async function body(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('Content-Type') || '')) throw new AppError('content_type', 'Use application/json.', 415);
  const reader = request.body?.getReader();
  let length = 0; const chunks = [];
  if (reader) for (;;) {
    const { done, value } = await reader.read(); if (done) break;
    length += value.length;
    if (length > 15 * 1024 * 1024) { await reader.cancel(); throw new AppError('body_too_large', 'Request exceeds 15 MiB.', 413); }
    chunks.push(Buffer.from(value));
  }
  let data;
  try { data = JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch { throw new AppError('invalid_json', 'Invalid JSON.'); }
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new AppError('invalid_json', 'Expected an object.');
  return data;
}
