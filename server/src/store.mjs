import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { mkdirSync, chmodSync, readFileSync, openSync, closeSync, writeFileSync, fsyncSync, renameSync, unlinkSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

/** One process owns this directory. The entire state (including credentials) is AES-256-GCM encrypted. */
export class EncryptedStore {
  constructor({ directory, keyHex }) {
    if (!/^[a-f0-9]{64}$/i.test(keyHex || '')) throw new Error('STORE_KEY_HEX must contain exactly 64 hexadecimal characters (32 random bytes).');
    this.key = Buffer.from(keyHex, 'hex');
    this.directory = resolve(directory);
    mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    // Tighten permissions even when an operator created the directory or
    // encrypted state file before starting this process.
    chmodSync(this.directory, 0o700);
    this.path = join(this.directory, 'state.enc');
    this.lockPath = join(this.directory, 'store.lock');
    this.acquireLock();
    try {
      if (existsSync(this.path)) chmodSync(this.path, 0o600);
      this.data = existsSync(this.path) ? this.decrypt(readFileSync(this.path)) : { version: 1, users: {}, sessions: {}, oauth: {} };
      if (this.data.version !== 1 || !this.data.users || !this.data.sessions || !this.data.oauth) throw new Error('Unsupported store version.');
    } catch (error) {
      this.close();
      throw new Error('Cannot open encrypted state. Verify STORE_KEY_HEX and preserve the data for recovery.', { cause: error });
    }
  }

  acquireLock() {
    if (existsSync(this.lockPath)) {
      const previousPID = Number(readFileSync(this.lockPath, 'utf8'));
      let alive = true;
      if (Number.isInteger(previousPID) && previousPID > 0) {
        try { process.kill(previousPID, 0); } catch (error) { if (error.code === 'ESRCH') alive = false; }
      }
      if (alive) throw new Error('The data directory is locked by another server. Run exactly one server per data directory.');
      unlinkSync(this.lockPath);
    }
    const fd = openSync(this.lockPath, 'wx', 0o600);
    try { writeFileSync(fd, String(process.pid)); fsyncSync(fd); } finally { closeSync(fd); }
    this.ownsLock = true;
  }

  decrypt(buffer) {
    const envelope = JSON.parse(buffer.toString());
    if (envelope.v !== 1) throw new Error('Unknown encryption format.');
    const decipher = createDecipheriv('aes-256-gcm', this.key, Buffer.from(envelope.iv, 'base64'));
    decipher.setAAD(Buffer.from('relay-referrals-store-v1'));
    decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
    return JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]).toString('utf8'));
  }

  save() {
    if (!this.ownsLock) throw new Error('The store is closed.');
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    cipher.setAAD(Buffer.from('relay-referrals-store-v1'));
    const ciphertext = Buffer.concat([cipher.update(JSON.stringify(this.data)), cipher.final()]);
    const output = JSON.stringify({ v: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), ciphertext: ciphertext.toString('base64') });
    const temporary = join(this.directory, `state.${randomBytes(12).toString('hex')}.tmp`);
    const fd = openSync(temporary, 'wx', 0o600);
    try { writeFileSync(fd, output); fsyncSync(fd); } finally { closeSync(fd); }
    renameSync(temporary, this.path);
    const directoryFD = openSync(this.directory, 'r');
    try { fsyncSync(directoryFD); } finally { closeSync(directoryFD); }
  }

  close() {
    if (this.ownsLock) {
      this.ownsLock = false;
      unlinkSync(this.lockPath);
    }
  }
}

export class MemoryStore {
  constructor(data) { this.data = data || { version: 1, users: {}, sessions: {}, oauth: {} }; this.saves = 0; }
  save() { this.saves++; }
  close() {}
}
