import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { parseEnv } from 'node:util';

// Owner-only handoff artifact, never bundled in the application or logged.
const config = parseEnv(readFileSync(new URL('../.env.cloudflare', import.meta.url), 'utf8'));
if (!/^[A-Za-z0-9_-]{32,128}$/.test(config.ENROLLMENT_KEY || '')) throw new Error('Missing private invitation configuration.');
const output = new URL('../.env.invitation.txt', import.meta.url);
writeFileSync(output, `RELAY PRIVATE INVITATION\n\nPaste this code into Relay → Settings → Join Relay:\n\n${config.ENROLLMENT_KEY}\n\nShare only with your invited group. Everyone connects their own Gmail and Hunter key.\nAsk the administrator to add each Gmail address as a Google OAuth test user first.\nReview recipients carefully: this service permits real external outreach.\n`, { mode: 0o600 });
chmodSync(output, 0o600);
console.log('Private invitation prepared in server/.env.invitation.txt. Code not logged.');
