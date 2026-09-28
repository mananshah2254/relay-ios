import { readFileSync, writeFileSync, renameSync, chmodSync, lstatSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseEnv } from 'node:util';
import { randomBytes } from 'node:crypto';

// Import Google's downloaded Web client JSON without logging its credentials.
// Existing secrets (especially the storage encryption key) are preserved.
export function configureGoogleOAuth(envText, document, expectedProject) {
  const client = document?.web;
  if (!client || client.project_id !== expectedProject) throw new Error('Expected a Web OAuth client from the specified Google project.');
  if (!/^[\w-]+\.apps\.googleusercontent\.com$/.test(client.client_id || '') ||
      !/^[\w-]+$/.test(client.client_secret || '')) throw new Error('Invalid OAuth credential format.');
  const existing = parseEnv(envText);
  const origin = new URL(existing.PUBLIC_BASE_URL);
  if (origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) throw new Error('PUBLIC_BASE_URL must be an origin.');
  const callback = `${origin.origin}/v1/google/callback`;
  if (!client.redirect_uris?.includes(callback)) throw new Error('Downloaded client does not include this backend callback.');
  const values = { GOOGLE_CLIENT_ID: client.client_id, GOOGLE_CLIENT_SECRET: client.client_secret };
  let output = envText;
  for (const [name, value] of Object.entries(values)) {
    if (existing[name] && existing[name] !== value) throw new Error('Existing OAuth configuration differs; no changes made.');
    const declaration = new RegExp(`^\\s*(?:export\\s+)?${name}\\s*=.*$`, 'gm');
    const matches = output.match(declaration) || [];
    if (matches.length > 1) throw new Error('Duplicate OAuth environment settings; no changes made.');
    output = matches.length ? output.replace(declaration, `${name}=${value}`) : `${output.trimEnd()}\n${name}=${value}\n`;
  }
  return output;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const [, , source, project] = process.argv;
    if (!source || !project) throw new Error('Usage: node scripts/import-google-oauth.mjs <download.json> <expected-project-id>');
    const target = resolve('.env');
    if (!lstatSync(target).isFile()) throw new Error('Expected an existing regular .env file.');
    const output = configureGoogleOAuth(readFileSync(target, 'utf8'), JSON.parse(readFileSync(source, 'utf8')), project);
    const temporary = `${target}.${randomBytes(12).toString('hex')}.tmp`;
    writeFileSync(temporary, output, { flag: 'wx', mode: 0o600 });
    renameSync(temporary, target);
    chmodSync(target, 0o600);
    process.stdout.write('Google OAuth imported into private backend .env. Existing storage key preserved. No emails sent. Restart the backend to use the configuration.\n');
  } catch (error) {
    // Avoid rendering JSON/parser errors that could include secret input.
    process.stderr.write(error instanceof SyntaxError ? 'Invalid configuration file; no changes made.\n' : `${error.message}\n`);
    process.exitCode = 1;
  }
}
