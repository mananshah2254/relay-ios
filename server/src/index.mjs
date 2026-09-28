import { resolve } from 'node:path';
import { EncryptedStore } from './store.mjs';
import { GoogleProvider, HunterProvider, JobResolver } from './providers.mjs';
import { ReferralService } from './service.mjs';
import { createHTTPServer } from './http.mjs';

const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || '127.0.0.1';
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be 1–65535.');
const publicURL = new URL(process.env.PUBLIC_BASE_URL || `http://localhost:${port}`);
const localhost = ['localhost', '127.0.0.1', '[::1]'].includes(publicURL.hostname);
if (publicURL.username || publicURL.password || publicURL.search || publicURL.hash || publicURL.pathname !== '/' || !(publicURL.protocol === 'https:' || (publicURL.protocol === 'http:' && localhost))) throw new Error('PUBLIC_BASE_URL must be an HTTPS origin, or an HTTP localhost origin for development.');
const store = new EncryptedStore({ directory: resolve(process.env.DATA_DIR || './data'), keyHex: process.env.STORE_KEY_HEX });
const google = new GoogleProvider({ clientID: process.env.GOOGLE_CLIENT_ID, clientSecret: process.env.GOOGLE_CLIENT_SECRET, publicBaseURL: publicURL.origin });
const service = new ReferralService({ store, google, hunter: new HunterProvider(), resolver: new JobResolver(), recipientAllowlist: String(process.env.TEST_RECIPIENT_ALLOWLIST || '').split(',') });
const server = createHTTPServer(service, { trustLoopbackProxy: process.env.TRUST_LOOPBACK_PROXY === 'true', onError: () => process.stderr.write('An internal request error occurred. Inspect storage and server configuration. Request data was not logged.\n') });
const interval = setInterval(() => { service.tick().catch(() => { service.halted = true; process.stderr.write('Queue stopped after an internal error. Restart only after checking storage.\n'); }); }, 1000);
interval.unref();
server.listen(port, host, () => process.stdout.write(`Relay backend listening on ${host}:${port}. Gmail OAuth is ${process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET ? 'configured' : 'not configured'}.\n`));
let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  clearInterval(interval);
  server.close();
  const wait = setInterval(() => {
    if (!service.ticking && !service.locks.size) {
      clearInterval(wait);
      store.close();
      process.exit(0);
    }
  }, 100);
  // A forced stop preserves in-flight state; the next start marks it uncertain.
  setTimeout(() => process.exit(1), 25000).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
server.on('error', () => { clearInterval(interval); store.close(); process.stderr.write('The HTTP server could not start. Check HOST and PORT.\n'); process.exitCode = 1; });
