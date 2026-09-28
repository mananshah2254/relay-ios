import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

// One Durable Object owns the private pilot. Chunking keeps PDFs below SQLite's
// per-row limit. A transaction replaces the entire encrypted snapshot atomically.
export class DurableStore {
  constructor(storage, keyHex) {
    if (!/^[a-f0-9]{64}$/i.test(keyHex || '')) throw new Error('Storage key is missing or invalid.');
    this.storage = storage;
    this.key = Buffer.from(keyHex, 'hex');
    storage.sql.exec('CREATE TABLE IF NOT EXISTS relay_state (part INTEGER PRIMARY KEY, value BLOB NOT NULL)');
    const rows = storage.sql.exec('SELECT part, value FROM relay_state ORDER BY part').toArray();
    this.data = { version: 1, users: {}, sessions: {}, oauth: {} };
    if (rows.length) {
      if (rows.some((row, index) => row.part !== index)) throw new Error('Incomplete encrypted state.');
      const encrypted = Buffer.concat(rows.map(row => Buffer.from(row.value)));
      const decipher = createDecipheriv('aes-256-gcm', this.key, encrypted.subarray(0, 12));
      decipher.setAAD(Buffer.from('relay-cloudflare-v1'));
      decipher.setAuthTag(encrypted.subarray(12, 28));
      this.data = JSON.parse(Buffer.concat([decipher.update(encrypted.subarray(28)), decipher.final()]).toString());
      if (this.data.version !== 1 || !this.data.users || !this.data.sessions || !this.data.oauth) throw new Error('Invalid stored state.');
    }
  }
  save() {
    const plain = Buffer.from(JSON.stringify(this.data));
    if (plain.length > 32 * 1024 * 1024) throw new Error('Private pilot storage capacity reached.');
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    cipher.setAAD(Buffer.from('relay-cloudflare-v1'));
    const body = Buffer.concat([cipher.update(plain), cipher.final()]);
    const encrypted = Buffer.concat([iv, cipher.getAuthTag(), body]);
    this.storage.transactionSync(() => {
      this.storage.sql.exec('DELETE FROM relay_state');
      for (let offset = 0, part = 0; offset < encrypted.length; offset += 512 * 1024, part++) {
        this.storage.sql.exec('INSERT INTO relay_state (part, value) VALUES (?, ?)', part, encrypted.subarray(offset, offset + 512 * 1024));
      }
    });
  }
}
