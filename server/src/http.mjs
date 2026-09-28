import { createServer } from 'node:http';
import { isIP } from 'node:net';
import { AppError } from './domain.mjs';

const BODY_LIMIT = 15 * 1024 * 1024;

async function readJSON(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] || '')) throw new AppError('content_type', 'Use application/json for request bodies.', 415);
  const length = Number(request.headers['content-length'] || 0);
  if (length > BODY_LIMIT) throw new AppError('body_too_large', 'Request exceeds 15 MiB.', 413);
  let bytes = 0;
  const chunks = [];
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > BODY_LIMIT) throw new AppError('body_too_large', 'Request exceeds 15 MiB.', 413);
    chunks.push(chunk);
  }
  let parsed;
  try { parsed = JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch { throw new AppError('invalid_json', 'The request body must contain valid JSON.'); }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new AppError('invalid_json', 'The request body must be a JSON object.');
  return parsed;
}

export function createHTTPServer(service, { onError = () => {}, trustLoopbackProxy = false } = {}) {
  const attempts = new Map();
  function rateLimit(key, maximum, duration) {
    const now = Date.now();
    const values = (attempts.get(key) || []).filter(time => time > now - duration);
    if (values.length >= maximum) throw new AppError('rate_limited', 'Too many requests. Try again later.', 429);
    values.push(now);
    attempts.set(key, values);
    if (attempts.size > 10000) for (const [bucket, times] of attempts) if (times.every(time => time <= now - 3600000)) attempts.delete(bucket);
  }
  const server = createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'no-referrer');
    try {
      const url = new URL(request.url, 'http://server.local');
      const route = url.pathname;
      const method = request.method;
      if (method === 'GET' && route === '/health') return send(response, service.halted ? 503 : 200, { ok: !service.halted });
      const socketAddress = request.socket.remoteAddress || 'unknown';
      const forwarded = request.headers['x-relay-client-ip'];
      // The supplied Caddy config overwrites this header. Never trust it from
      // public connections or when the operator has not enabled the local proxy.
      const remote = trustLoopbackProxy && ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(socketAddress)
        && typeof forwarded === 'string' && isIP(forwarded) ? forwarded : socketAddress;
      rateLimit(`requests:${remote}`, 300, 60000);
      if (method === 'GET' && route === '/v1/google/callback') {
        const destination = await service.finishGoogle({ state: url.searchParams.get('state'), code: url.searchParams.get('code'), error: url.searchParams.get('error') });
        response.writeHead(302, { Location: destination }); response.end(); return;
      }
      if (method === 'POST' && route === '/v1/session') {
        rateLimit(`sessions:${remote}`, 10, 3600000);
        await readJSON(request);
        return send(response, 201, service.createSession());
      }
      const authorization = request.headers.authorization || '';
      if (!authorization.startsWith('Bearer ')) throw new AppError('unauthorized', 'A valid app session is required.', 401);
      const userID = service.authenticate(authorization.slice(7));
      if (method === 'GET' && route === '/v1/state') return send(response, 200, service.getState(userID));
      let result;
      if (method === 'PUT' && route === '/v1/settings') result = await service.setSettings(userID, await readJSON(request));
      else if (method === 'POST' && route === '/v1/hunter') result = await service.connectHunter(userID, await readJSON(request));
      else if (method === 'DELETE' && route === '/v1/hunter') result = await service.disconnectHunter(userID);
      else if (method === 'POST' && route === '/v1/google/connect') { await readJSON(request); result = await service.connectGoogle(userID); }
      else if (method === 'DELETE' && route === '/v1/google') result = await service.disconnectGoogle(userID);
      else if (method === 'POST' && route === '/v1/resume') result = await service.setResume(userID, await readJSON(request));
      else if (method === 'DELETE' && route === '/v1/resume') result = await service.deleteResume(userID);
      else if (method === 'POST' && route === '/v1/jobs/preview') { rateLimit(`preview:${userID}`, 20, 60000); result = await service.previewJob(userID, await readJSON(request)); }
      else if (method === 'POST' && route === '/v1/companies/search') { rateLimit(`companies:${userID}`, 20, 60000); result = await service.searchCompanies(userID, await readJSON(request)); }
      else if (method === 'POST' && route === '/v1/jobs') { rateLimit(`research:${userID}`, 20, 60000); result = await service.importJob(userID, await readJSON(request)); }
      else if (method === 'POST' && route === '/v1/queue/pause') { await readJSON(request); result = await service.pauseQueue(userID, true); }
      else if (method === 'POST' && route === '/v1/queue/resume') { await readJSON(request); result = await service.pauseQueue(userID, false); }
      else if (method === 'DELETE' && route === '/v1/account') result = await service.deleteAccount(userID);
      else {
        const match = route.match(/^\/v1\/jobs\/([a-zA-Z0-9-]+)(?:\/(research|approve|cancel|diagnose))?$/);
        if (!match) throw new AppError('not_found', 'This endpoint does not exist.', 404);
        const [, campaignID, action] = match;
        if (method === 'PATCH' && !action) result = await service.patchJob(userID, campaignID, await readJSON(request));
        else if (method === 'POST' && action) {
          const input = await readJSON(request);
          if (action === 'research') { rateLimit(`research:${userID}`, 20, 60000); result = await service.researchJob(userID, campaignID, input); }
          else if (action === 'diagnose') result = await service.diagnoseJob(userID, campaignID);
          else if (action === 'approve') result = await service.approveJob(userID, campaignID);
          else result = await service.cancelJob(userID, campaignID);
        } else throw new AppError('method_not_allowed', 'This HTTP method is not supported.', 405);
      }
      send(response, 200, result);
    } catch (error) {
      if (!(error instanceof AppError)) onError(error);
      if (!response.headersSent) send(response, error instanceof AppError ? error.status : 500, { error: { code: error instanceof AppError ? error.code : 'internal_error', message: error instanceof AppError ? error.message : 'The server could not complete the request.' } });
      else response.end();
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  return server;
}

function send(response, status, data) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(data));
}
