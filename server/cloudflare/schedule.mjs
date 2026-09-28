import { mailboxAvailableAt } from '../src/pacing.mjs';

// Schedule only runnable work; paused/empty queues consume no periodic alarms.
export function nextSendTime(service, now = Date.now()) {
  if (service.halted) return null;
  let next = Infinity;
  for (const user of Object.values(service.store.data.users)) {
    if (user.queuePaused || !user.google) continue;
    for (const campaign of user.campaigns) {
      const snapshot = campaign.snapshot;
      if (!snapshot || !campaign.messages.some(message => message.status === 'queued')) continue;
      if (user.google.id !== snapshot.gmailAccountID || user.google.email !== snapshot.gmailEmail) continue;
      const box = service.mailbox(snapshot);
      if (box.paused) continue;
      const attempts = box.attempts.filter(time => time > now - 86400000).sort((a, b) => a - b);
      const limit = Math.min(user.settings.dailyLimit, snapshot.settings.dailyLimit);
      const available = attempts.length >= limit ? attempts[attempts.length - limit] + 86400000 + 1 : now;
      next = Math.min(next, Math.max(now + 1000, mailboxAvailableAt(box, user.settings, snapshot.settings), available));
    }
  }
  return Number.isFinite(next) ? next : null;
}
