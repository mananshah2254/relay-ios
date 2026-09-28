import { existsSync, statSync, accessSync, constants } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { emailValid } from '../src/domain.mjs';

// Read configuration without opening encrypted state, starting the queue,
// contacting providers, or printing any secret values.
const hosted = process.argv.includes('--hosted');
let failed = false;
function check(label, passes, help) {
  process.stdout.write(`${passes ? 'OK' : 'MISSING'}  ${label}${passes ? '' : ` — ${help}`}\n`);
  if (!passes) failed = true;
}
check('Node runtime', Number(process.versions.node.split('.')[0]) >= 22, 'Install Node 22 or newer.');
check('Storage encryption key', /^[a-f0-9]{64}$/i.test(process.env.STORE_KEY_HEX || ''), 'Run npm run setup; preserve the generated key.');
let publicURL;
try { publicURL = new URL(process.env.PUBLIC_BASE_URL); } catch { /* Report below. */ }
const publicOrigin = publicURL && !publicURL.username && !publicURL.password && !publicURL.search && !publicURL.hash && publicURL.pathname === '/';
const originOK = publicOrigin && (publicURL.protocol === 'https:' || (!hosted && publicURL.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(publicURL.hostname)));
check('Service origin', originOK, hosted ? 'Set PUBLIC_BASE_URL to the deployed HTTPS origin.' : 'Set PUBLIC_BASE_URL to a valid HTTPS or local development origin.');
check('Google OAuth client ID', Boolean(process.env.GOOGLE_CLIENT_ID?.endsWith('.apps.googleusercontent.com')), 'Configure a Google Web application OAuth client.');
check('Google OAuth client secret', Boolean(process.env.GOOGLE_CLIENT_SECRET?.trim()), 'Store the secret in the backend environment.');
const allowlist = String(process.env.TEST_RECIPIENT_ALLOWLIST || '').split(',').map(v => v.trim()).filter(Boolean);
check('Pilot test recipients', allowlist.length > 0 && allowlist.every(emailValid), 'Set TEST_RECIPIENT_ALLOWLIST to your designated test inboxes.');
if (hosted) {
  check('Persistent data location', isAbsolute(process.env.DATA_DIR || ''), 'Use an absolute persistent directory, such as /var/lib/relay.');
  check('Local reverse proxy binding', (process.env.HOST || '127.0.0.1') === '127.0.0.1', 'Keep the Node listener on loopback behind Caddy.');
  check('Trusted local proxy', process.env.TRUST_LOOPBACK_PROXY === 'true', 'Enable only with the supplied Caddy configuration.');
}
const dataPath = resolve(process.env.DATA_DIR || './data');
if (existsSync(dataPath)) {
  let accessible = false;
  try { accessSync(dataPath, constants.R_OK | constants.W_OK); accessible = statSync(dataPath).isDirectory(); } catch { /* Report below. */ }
  check('Data directory access', accessible, 'Give the Relay service user read/write access.');
}
if (originOK) process.stdout.write(`Register this Google callback: ${publicURL.origin}/v1/google/callback\n`);
process.stdout.write('Hunter keys are supplied in the iPhone app. This check does not read them or send email.\n');
process.exitCode = failed ? 1 : 0;
