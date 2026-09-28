import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EncryptedStore } from '../src/store.mjs';

const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

test('encrypted store persists state and rejects a wrong key', () => {
  const directory = mkdtempSync(join(tmpdir(), 'relay-store-'));
  try {
    const first = new EncryptedStore({ directory, keyHex: key });
    first.data.users.example = { id: 'example', secret: 'not plaintext on disk' };
    first.save();
    first.close();
    const reopened = new EncryptedStore({ directory, keyHex: key });
    assert.equal(reopened.data.users.example.secret, 'not plaintext on disk');
    reopened.close();
    assert.throws(() => new EncryptedStore({ directory, keyHex: 'f'.repeat(64) }), /Cannot open encrypted state/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('encrypted store permits only one process owner for a data directory', () => {
  const directory = mkdtempSync(join(tmpdir(), 'relay-store-lock-'));
  try {
    const first = new EncryptedStore({ directory, keyHex: key });
    assert.throws(() => new EncryptedStore({ directory, keyHex: key }), /locked by another server/);
    first.close();
    const second = new EncryptedStore({ directory, keyHex: key });
    second.close();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
