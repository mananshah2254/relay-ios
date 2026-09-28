import test from 'node:test';
import assert from 'node:assert/strict';
import { recipientAllowlist } from '../cloudflare/recipient-policy.mjs';

test('external recipients require explicit opt-in; missing policy fails closed', () => {
  assert.throws(() => recipientAllowlist({}));
  assert.throws(() => recipientAllowlist({ ALLOW_EXTERNAL_RECIPIENTS: 'false' }));
  assert.deepEqual(recipientAllowlist({ TEST_RECIPIENT_ALLOWLIST: ' owner@example.com ' }), ['owner@example.com']);
  assert.deepEqual(recipientAllowlist({ ALLOW_EXTERNAL_RECIPIENTS: 'true', TEST_RECIPIENT_ALLOWLIST: 'owner@example.com' }), []);
});
