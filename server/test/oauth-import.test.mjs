import test from 'node:test';
import assert from 'node:assert/strict';
import { configureGoogleOAuth } from '../scripts/import-google-oauth.mjs';

const env = 'STORE_KEY_HEX=preserve-me\nPUBLIC_BASE_URL=http://localhost:8787\nGOOGLE_CLIENT_ID=\nGOOGLE_CLIENT_SECRET=\n';
const document = { web: { project_id: 'test-project', client_id: 'fake-client.apps.googleusercontent.com', client_secret: 'fake-secret', redirect_uris: ['http://localhost:8787/v1/google/callback'] } };
test('OAuth import preserves existing storage key and is idempotent', () => {
  const result = configureGoogleOAuth(env, document, 'test-project');
  assert.match(result, /STORE_KEY_HEX=preserve-me/);
  assert.match(result, /GOOGLE_CLIENT_SECRET=fake-secret/);
  assert.equal(configureGoogleOAuth(result, document, 'test-project'), result);
});
test('OAuth import rejects a different project or callback', () => {
  assert.throws(() => configureGoogleOAuth(env, document, 'other-project'), /specified Google project/);
  assert.throws(() => configureGoogleOAuth(env.replace('8787', '8888'), document, 'test-project'), /callback/);
});
test('OAuth import cannot silently replace existing credentials', () => {
  assert.throws(() => configureGoogleOAuth(env.replace('GOOGLE_CLIENT_SECRET=', 'GOOGLE_CLIENT_SECRET=existing'), document, 'test-project'), /differs/);
});
test('OAuth import rejects duplicate settings and malformed credentials', () => {
  assert.throws(() => configureGoogleOAuth(`${env}GOOGLE_CLIENT_ID=\n`, document, 'test-project'), /Duplicate/);
  assert.throws(() => configureGoogleOAuth(env, { web: { ...document.web, client_secret: 'bad\nINJECT=true' } }, 'test-project'), /format/);
});
