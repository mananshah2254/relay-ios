import { randomBytes } from 'node:crypto';
import { openSync, writeFileSync, closeSync } from 'node:fs';
import { resolve } from 'node:path';

const destination = resolve('.env');
let fd;
try { fd = openSync(destination, 'wx', 0o600); } catch (error) {
  if (error.code === 'EEXIST') { process.stdout.write('Existing .env preserved.\n'); process.exit(0); }
  throw error;
}
try {
  writeFileSync(fd, `STORE_KEY_HEX=${randomBytes(32).toString('hex')}\nDATA_DIR=./data\nHOST=127.0.0.1\nPORT=8787\nPUBLIC_BASE_URL=http://localhost:8787\nGOOGLE_CLIENT_ID=\nGOOGLE_CLIENT_SECRET=\n# Set your own test inbox addresses before a live pilot.\nTEST_RECIPIENT_ALLOWLIST=\n`);
} finally { closeSync(fd); }
process.stdout.write('Created private .env. Configure Google OAuth and a test recipient allowlist before live testing.\n');
