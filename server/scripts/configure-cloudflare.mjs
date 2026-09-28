import { readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';

// Keep hosted secrets separate from local development. Never print their values.
const publicURL = process.argv[2];
if (publicURL !== 'https://relay-referrals-api.manan-hiren-shah.workers.dev') throw new Error('Unexpected deployment origin.');
const path = '.env.cloudflare';
if (!existsSync(path)) {
  const local = parseEnv(readFileSync('.env', 'utf8'));
  if (!local.GOOGLE_CLIENT_ID || !local.GOOGLE_CLIENT_SECRET || !local.TEST_RECIPIENT_ALLOWLIST) throw new Error('Local Google configuration and pilot recipient limit required.');
  const values = {
    PUBLIC_BASE_URL: publicURL,
    GOOGLE_CLIENT_ID: local.GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET: local.GOOGLE_CLIENT_SECRET,
    TEST_RECIPIENT_ALLOWLIST: local.TEST_RECIPIENT_ALLOWLIST,
    STORE_KEY_HEX: randomBytes(32).toString('hex'),
    ENROLLMENT_KEY: randomBytes(32).toString('base64url'),
  };
  writeFileSync(path, Object.entries(values).map(([k, v]) => `${k}=${v}\n`).join(''), { flag: 'wx', mode: 0o600 });
}
chmodSync(path, 0o600);
const values = parseEnv(readFileSync(path, 'utf8'));
if (values.PUBLIC_BASE_URL !== publicURL) throw new Error('Existing deployment origin differs.');
if (process.argv.includes('--upload')) {
  const result = spawnSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'secret', 'bulk'], { input: JSON.stringify(values), encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  // Wrangler reports secret names only. Avoid forwarding unreviewed output in an error.
  if (result.status !== 0) { process.stderr.write('Cloudflare secret upload failed; stored configuration preserved.\n'); process.exit(1); }
  process.stdout.write('Hosted configuration uploaded to Relay Worker. Secret values were not logged.\n');
} else process.stdout.write('Private hosted configuration prepared. No cloud changes made.\n');
