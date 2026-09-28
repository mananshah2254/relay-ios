// Missing configuration remains fail-closed. External outreach is opt-in.
export function recipientAllowlist(env) {
  if (env.ALLOW_EXTERNAL_RECIPIENTS === 'true') return [];
  const addresses = String(env.TEST_RECIPIENT_ALLOWLIST || '').split(',').map(s => s.trim()).filter(Boolean);
  if (!addresses.length) throw new Error('Recipient policy must be configured.');
  return addresses;
}
