// One shared pacing rule for the queue worker and Durable Object alarm planner.
export const MIN_SEND_INTERVAL_SECONDS = 600;

export function sendIntervalMilliseconds(settings, snapshotSettings) {
  return Math.max(MIN_SEND_INTERVAL_SECONDS,
    settings?.sendIntervalSeconds || 0,
    snapshotSettings?.sendIntervalSeconds || 0) * 1000;
}

export function mailboxAvailableAt(box, settings, snapshotSettings) {
  const lastAttempt = box.attempts.length ? Math.max(...box.attempts, box.lastCompletedAt || 0) : (box.lastCompletedAt ?? null);
  return Math.max(box.nextSendAt || 0,
    lastAttempt === null ? 0 : lastAttempt + sendIntervalMilliseconds(settings, snapshotSettings));
}
