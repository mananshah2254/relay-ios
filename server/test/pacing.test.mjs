import test from 'node:test';
import assert from 'node:assert/strict';
import { mailboxAvailableAt, sendIntervalMilliseconds } from '../src/pacing.mjs';
import { nextSendTime } from '../cloudflare/schedule.mjs';

test('pacing uses the slowest limit and never shortens a persisted completion delay', () => {
  assert.equal(sendIntervalMilliseconds({ sendIntervalSeconds: 5 }, { sendIntervalSeconds: 10 }), 600000);
  assert.equal(sendIntervalMilliseconds({ sendIntervalSeconds: 900 }, { sendIntervalSeconds: 1200 }), 1200000);
  assert.equal(mailboxAvailableAt({ attempts: [1000], nextSendAt: 1500000 }, {}, {}), 1500000);
  assert.equal(mailboxAvailableAt({ attempts: [], nextSendAt: 0 }, {}, {}), 0);
});

test('alarm planner upgrades a legacy fast due date instead of repeatedly waking early', () => {
  const now = 1000000;
  const box = { attempts: [now - 1000], nextSendAt: now + 4000, paused: false };
  const user = { google: { id: 'g', email: 'a@example.com' }, settings: { dailyLimit: 10, sendIntervalSeconds: 600 }, campaigns: [{ snapshot: { gmailAccountID: 'g', gmailEmail: 'a@example.com', settings: { dailyLimit: 10, sendIntervalSeconds: 5 } }, messages: [{ status: 'queued' }] }] };
  const service = { store: { data: { users: { a: user } } }, mailbox: () => box };
  assert.equal(nextSendTime(service, now), now + 599000);
  user.settings.sendIntervalSeconds = 1200;
  assert.equal(nextSendTime(service, now), now + 1199000);
});
