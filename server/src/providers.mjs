import { createHash, randomBytes } from 'node:crypto';
import { AppError, hunterFilters, normalizeDomain, noNewline, emailValid } from './domain.mjs';

export const GOOGLE_SCOPES = ['openid', 'email', 'https://www.googleapis.com/auth/gmail.send'];
export const APP_CALLBACK = 'relayreferrals://oauth/complete';
const TIMEOUT_MS = 20000;
const MAX_PROVIDER_BODY = 2 * 1024 * 1024;

export class ProviderError extends AppError {
  constructor(provider, status = 502, ambiguous = false, timedOut = false) {
    const hunterMessage = status === 0 ? 'Hunter could not be reached or timed out. This is a connection failure, not a zero-contact result.' : status === 401 ? 'Hunter rejected the API key. Reconnect Hunter in Settings.' : status === 429 ? 'Hunter account usage limits were reached. Check your Hunter usage before trying again.' : status === 403 ? 'Hunter denied this request or rate-limited it. Wait before trying again; check account access if this persists.' : `Hunter returned HTTP ${status}. No contact search result was confirmed.`;
    const message = ambiguous ? `${provider} did not confirm whether the email was accepted. Check Gmail Sent before taking further action.` : provider === 'Hunter' ? hunterMessage : `${provider} request failed${status ? ` (HTTP ${status})` : ''}. Check the connection and account quota.`;
    super(ambiguous ? 'send_uncertain' : timedOut ? 'provider_timeout' : 'provider_error', timedOut && provider === 'Hunter' ? 'Hunter did not finish the lookup within 60 seconds. No search result was received. You can explicitly retry; Hunter credits may already have been used.' : message, 502);
    this.providerStatus = status;
    this.ambiguous = ambiguous;
  }
}

async function jsonRequest(fetchImpl, provider, url, options = {}, isSend = false) {
  let response;
  try {
    response = await fetchImpl(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(provider === 'Hunter' ? 60000 : TIMEOUT_MS) });
  } catch (error) {
    throw new ProviderError(provider, 0, isSend, provider === 'Hunter' && ['TimeoutError', 'AbortError'].includes(error?.name));
  }
  if (!response.ok) throw new ProviderError(provider, response.status, isSend && (response.status >= 500 || response.status === 408));
  try {
    const reader = response.body?.getReader();
    let text = '';
    if (reader) {
      let total = 0;
      const chunks = [];
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        total += value.length;
        if (total > MAX_PROVIDER_BODY) { await reader.cancel(); throw new Error('Response too large'); }
        chunks.push(Buffer.from(value));
      }
      text = Buffer.concat(chunks).toString('utf8');
    } else text = await response.text();
    return JSON.parse(text);
  } catch (error) {
    throw new ProviderError(provider, response.status, isSend, provider === 'Hunter' && ['TimeoutError', 'AbortError'].includes(error?.name));
  }
}

export class HunterProvider {
  constructor({ fetchImpl = fetch } = {}) { this.fetch = fetchImpl; }
  request(key, endpoint, params = {}) {
    const url = new URL(`https://api.hunter.io/v2/${endpoint}`);
    url.search = new URLSearchParams(params).toString();
    // Hunter supports header authentication; keep the secret out of URLs and logs.
    return jsonRequest(this.fetch, 'Hunter', url.toString(), { headers: { 'X-API-KEY': key } });
  }
  async validateKey(key) {
    const result = await this.request(key, 'account');
    if (!result.data) throw new ProviderError('Hunter', 502);
    return true;
  }
  async findDomain(key, company) {
    // Hunter documents Domain Finder as the canonical company-to-domain step.
    // Ask only for a perfect match and still verify the returned company name.
    const name = noNewline(String(company || '').trim(), 'Company name');
    if (name.length < 3) return null;
    const result = await this.request(key, 'domain-finder', { company: name, limit: '1', perfect_match: 'true' });
    const data = Array.isArray(result.data) ? result.data[0] : null;
    const returnedName = String(data?.company_name || '').trim();
    const normalizeName = value => value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    if (!returnedName || normalizeName(returnedName) !== normalizeName(name)) return null;
    try { return normalizeDomain(data?.domain || ''); } catch { return null; }
  }
  async findCompanies(key, query) {
    const name = noNewline(String(query || '').trim(), 'Company name');
    if (name.length < 3 || name.length > 100) throw new AppError('invalid_company', 'Enter 3–100 characters to search companies.');
    const result = await this.request(key, 'domain-finder', { company: name, limit: '10', perfect_match: 'false' });
    if (!Array.isArray(result.data)) throw new ProviderError('Hunter', 502);
    const seen = new Set();
    return result.data.slice(0, 10).flatMap(item => {
      try {
        const domain = normalizeDomain(item.domain);
        const company = noNewline(String(item.company_name || '').trim(), 'Company name');
        if (!company || company.length > 200 || seen.has(domain)) return [];
        seen.add(domain);
        return [{ company, domain }];
      } catch { return []; }
    });
  }
  async search(key, campaign, settings) {
    const result = await this.request(key, 'domain-search', { domain: campaign.domain, ...hunterFilters(settings, campaign.title) });
    if (!Array.isArray(result.data?.emails)) throw new ProviderError('Hunter', 502);
    // No pagination: the user pays for only one request of at most maxContacts addresses.
    if (result.data.emails.length > settings.maxContacts) throw new AppError('provider_limit_violation', 'Hunter returned more contacts than requested. This campaign has been stopped.', 502);
    return result.data.emails;
  }
  async diagnose(key, domain) {
    const result = await this.request(key, 'domain-search', { domain, type: 'personal', limit: '5', offset: '0' });
    if (!Array.isArray(result.data?.emails) || result.data.emails.length > 5) throw new ProviderError('Hunter', 502);
    const rows = result.data.emails;
    const count = status => rows.filter(row => row.verification?.status === status).length;
    return { message: `Hunter returned ${rows.length} personal addresses in this sample for ${domain}: ${count('valid')} verified, ${count('accept_all')} accept-all, ${rows.filter(row => !['valid', 'accept_all'].includes(row.verification?.status)).length} other/unverified. This sample is not the entire directory. No emails were queued or sent.` };
  }
}

function stripHTML(text = '') {
  return String(text).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/<\/(?:p|div|li|h\d)>/gi, '\n').replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim().slice(0, 40000);
}

export class JobResolver {
  constructor({ fetchImpl = fetch } = {}) { this.fetch = fetchImpl; }
  async resolve(job) {
    if (!job.url) return { ...job };
    const url = new URL(job.url);
    const parts = url.pathname.split('/').filter(Boolean);
    const result = { ...job };
    const greenhouse = ['boards.greenhouse.io', 'job-boards.greenhouse.io'].includes(url.hostname);
    if (greenhouse && parts.length === 3 && parts[1] === 'jobs' && /^[a-z0-9_-]+$/i.test(parts[0]) && /^\d+$/.test(parts[2])) {
      const endpoint = `https://boards-api.greenhouse.io/v1/boards/${encodeURIComponent(parts[0])}/jobs/${parts[2]}`;
      const data = await jsonRequest(this.fetch, 'Greenhouse', endpoint);
      result.title ||= String(data.title || '').trim().slice(0, 300);
      result.company ||= String(data.company_name || '').trim().slice(0, 200);
      result.description ||= stripHTML(data.content);
      // Only use the employer website when the job API explicitly provides it.
      if (!result.domain && data.absolute_url) {
        try { result.domain = normalizeDomain(new URL(data.absolute_url).hostname); } catch { /* Hosted ATS domain is not an employer domain. */ }
      }
    } else if (['jobs.lever.co', 'jobs.eu.lever.co'].includes(url.hostname) && parts.length >= 2 && /^[a-z0-9_-]+$/i.test(parts[0]) && /^[a-z0-9-]+$/i.test(parts[1])) {
      const host = url.hostname.includes('.eu.') ? 'api.eu.lever.co' : 'api.lever.co';
      const data = await jsonRequest(this.fetch, 'Lever', `https://${host}/v0/postings/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`);
      result.title ||= String(data.text || '').trim().slice(0, 300);
      result.description ||= stripHTML(data.descriptionPlain || data.description);
      // Lever does not return a reliable employer domain or display name. Ask the user.
    }
    // Never fetch arbitrary URLs, follow redirects, or scrape LinkedIn.
    return result;
  }
}

function encodedHeader(text) {
  noNewline(text, 'Email header');
  // Fold RFC 2047 encoded words at Unicode character boundaries, below 75 characters.
  const chunks = [];
  let chunk = '';
  for (const char of text) {
    if (Buffer.byteLength(chunk + char) > 42) { chunks.push(chunk); chunk = ''; }
    chunk += char;
  }
  if (chunk) chunks.push(chunk);
  return chunks.map(value => `=?UTF-8?B?${Buffer.from(value).toString('base64')}?=`).join('\r\n ');
}

const base64Lines = data => Buffer.from(data).toString('base64').match(/.{1,76}/g)?.join('\r\n') || '';

export function buildMIME({ senderName, senderEmail, message, resume, now = new Date() }) {
  if (!emailValid(senderEmail) || !emailValid(message.to)) throw new AppError('invalid_email', 'Invalid sender or recipient email.');
  const boundary = `relay_${randomBytes(18).toString('hex')}`;
  const headers = [
    `From: ${encodedHeader(senderName)} <${senderEmail}>`,
    `To: ${message.to}`,
    `Subject: ${encodedHeader(message.subject)}`,
    `Date: ${now.toUTCString()}`,
    `Message-ID: <${message.id}@relay.local>`,
    'MIME-Version: 1.0',
  ];
  const body = ['Content-Type: text/plain; charset=UTF-8', 'Content-Transfer-Encoding: base64', '', base64Lines(Buffer.from(message.body))];
  if (!resume) return Buffer.from([...headers, ...body].join('\r\n')).toString('base64url');
  const safeFilename = resume.filename.replace(/[^a-zA-Z0-9._-]/g, '_');
  const content = [
    ...headers, `Content-Type: multipart/mixed; boundary="${boundary}"`, '',
    `--${boundary}`, ...body, `--${boundary}`,
    `Content-Type: application/pdf; name="${safeFilename}"`,
    `Content-Disposition: attachment; filename="${safeFilename}"; filename*=UTF-8''${encodeURIComponent(resume.filename).replace(/'/g, '%27')}`,
    'Content-Transfer-Encoding: base64', '', base64Lines(Buffer.from(resume.dataBase64, 'base64')),
    `--${boundary}--`, '',
  ];
  return Buffer.from(content.join('\r\n')).toString('base64url');
}

export class GoogleProvider {
  constructor({ clientID, clientSecret, publicBaseURL, fetchImpl = fetch, now = () => Date.now() }) {
    this.clientID = clientID;
    this.clientSecret = clientSecret;
    this.redirectURI = `${publicBaseURL.replace(/\/$/, '')}/v1/google/callback`;
    this.fetch = fetchImpl;
    this.now = now;
  }
  assertConfigured() {
    if (!this.clientID || !this.clientSecret) throw new AppError('google_not_configured', 'The server needs a Google OAuth client ID and secret before Gmail can connect.', 503);
  }
  authorizationURL(state, verifier) {
    this.assertConfigured();
    const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    url.search = new URLSearchParams({ client_id: this.clientID, redirect_uri: this.redirectURI, response_type: 'code', scope: GOOGLE_SCOPES.join(' '), state, code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256', access_type: 'offline', prompt: 'consent', include_granted_scopes: 'false' }).toString();
    return url.toString();
  }
  async finish(code, verifier) {
    this.assertConfigured();
    const tokens = await jsonRequest(this.fetch, 'Google OAuth', 'https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ code, code_verifier: verifier, client_id: this.clientID, client_secret: this.clientSecret, redirect_uri: this.redirectURI, grant_type: 'authorization_code' }).toString(),
    });
    const scopes = new Set(String(tokens.scope || '').split(' '));
    if (!scopes.has('https://www.googleapis.com/auth/gmail.send')) throw new AppError('gmail_permission_missing', 'Gmail send permission was not granted.');
    if (!tokens.refresh_token || !tokens.access_token || !Number.isFinite(tokens.expires_in)) throw new AppError('google_token_missing', 'Google did not return an offline grant. Reconnect and grant the requested permissions.');
    const user = await jsonRequest(this.fetch, 'Google identity', 'https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: `Bearer ${tokens.access_token}` } });
    if (!user.sub || user.email_verified !== true || !emailValid(user.email)) throw new AppError('unverified_account', 'Google did not return a verified email account.');
    return { id: String(user.sub), email: user.email.toLowerCase(), accessToken: tokens.access_token, refreshToken: tokens.refresh_token, expiresAt: this.now() + tokens.expires_in * 1000 };
  }
  async refresh(account) {
    if (account.expiresAt > this.now() + 60000) return account;
    this.assertConfigured();
    const tokens = await jsonRequest(this.fetch, 'Google OAuth', 'https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ refresh_token: account.refreshToken, client_id: this.clientID, client_secret: this.clientSecret, grant_type: 'refresh_token' }).toString(),
    });
    if (!tokens.access_token || !Number.isFinite(tokens.expires_in)) throw new ProviderError('Google OAuth', 502);
    return { ...account, accessToken: tokens.access_token, expiresAt: this.now() + tokens.expires_in * 1000, refreshToken: tokens.refresh_token || account.refreshToken };
  }
  async send(account, snapshot, message) {
    const raw = buildMIME({ senderName: snapshot.settings.senderName, senderEmail: snapshot.gmailEmail, message, resume: snapshot.resume, now: new Date(this.now()) });
    const result = await jsonRequest(this.fetch, 'Gmail', 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
      method: 'POST', headers: { Authorization: `Bearer ${account.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ raw }),
    }, true);
    if (!result.id || typeof result.id !== 'string') throw new ProviderError('Gmail', 200, true);
    return result.id;
  }
  async revoke(account) {
    if (!account) return;
    try {
      await this.fetch('https://oauth2.googleapis.com/revoke', { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(TIMEOUT_MS), headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token: account.refreshToken }).toString() });
    } catch { /* Local deletion is still authoritative; Google settings can revoke grants independently. */ }
  }
}
