import test from 'node:test';
import assert from 'node:assert/strict';
import { AppError, DEFAULT_SETTINGS, canonicalJobURL, normalizeDomain, parseJobInput, rankContacts, renderMessage, validateResume, validateSettings, hunterFilters } from '../src/domain.mjs';
import { buildMIME, HunterProvider, JobResolver } from '../src/providers.mjs';

test('Greenhouse employer email domain is distinct from hosted job-board domains', () => {
  assert.equal(normalizeDomain('greenhouse.io'), 'greenhouse.io');
  assert.throws(() => normalizeDomain('boards.greenhouse.io'));
  assert.throws(() => normalizeDomain('job-boards.greenhouse.io'));
  assert.equal(parseJobInput({ title: 'Engineer', company: 'Greenhouse', domain: 'greenhouse.com' }).domain, 'greenhouse.io');
  assert.equal(parseJobInput({ title: 'Engineer', company: 'Other company', domain: 'greenhouse.com' }).domain, 'greenhouse.com');
});

test('role templates validate and old settings keep automatic confirmation off', () => {
  assert.equal(validateSettings(DEFAULT_SETTINGS).autoConfirmCompany, false);
  const roleTemplates = { software: { subject: 'Hello {{job_title}}', body: 'My name is {{sender_name}}.' } };
  const saved = validateSettings({ ...DEFAULT_SETTINGS, roleTemplates, selectedTemplate: 'software' });
  assert.deepEqual(saved.roleTemplates, roleTemplates);
  assert.throws(() => validateSettings({ ...DEFAULT_SETTINGS, autoConfirmCompany: 'yes' }));
  assert.throws(() => validateSettings({ ...DEFAULT_SETTINGS, roleTemplates: { software: { subject: 'Bad\nHeader', body: 'Hello' } } }));
});

test('shared LinkedIn page titles fill explicit fields but bare links do not invent details', () => {
  const result = parseJobInput({ url: 'https://www.linkedin.com/jobs/view/123', sharedText: 'Example Studio hiring Software Engineer in Seattle | LinkedIn' });
  assert.equal(result.company, 'Example Studio');
  assert.equal(result.title, 'Software Engineer');
  assert.equal(parseJobInput({ url: result.url }).company, '');
});

test('supported board lookup fills job description and title without arbitrary URL fetches', async () => {
  const calls = [];
  const resolver = new JobResolver({ fetchImpl: async url => {
    calls.push(url);
    return new Response(JSON.stringify({ title: 'Software Engineer', company_name: 'Example', content: '<p>Build useful software.</p>' }), { status: 200 });
  } });
  const details = await resolver.resolve({ url: 'https://job-boards.greenhouse.io/example/jobs/123' });
  assert.equal(details.title, 'Software Engineer');
  assert.equal(details.company, 'Example');
  assert.match(details.description, /Build useful software/);
  assert.equal(calls[0], 'https://boards-api.greenhouse.io/v1/boards/example/jobs/123');
  await resolver.resolve({ url: 'https://untrusted.example/jobs/123' });
  assert.equal(calls.length, 1);
});

test('canonical job URLs remove tracking and preserve a stable LinkedIn job key', () => {
  assert.equal(canonicalJobURL('https://www.linkedin.com/jobs/view/senior-ios-4281234567/?trk=abc'), 'https://www.linkedin.com/jobs/view/4281234567');
  assert.equal(canonicalJobURL('https://jobs.example.com/apply?gh_jid=42&utm_source=linkedin&team=mobile#description'), 'https://jobs.example.com/apply?gh_jid=42&team=mobile');
  assert.throws(() => canonicalJobURL('http://example.com/job/1'), AppError);
  assert.throws(() => canonicalJobURL('https://example.com:8443/job/1'), AppError);
});

test('job parsing needs explicit details and rejects hosted domains', () => {
  const parsed = parseJobInput({
    url: 'https://www.linkedin.com/posts/example_hiring-123?utm_source=share',
    sharedText: 'Check out this job at Example Studio: Product Designer',
  });
  assert.equal(parsed.company, 'Example Studio');
  assert.equal(parsed.title, 'Product Designer');
  assert.equal(parsed.domain, '');
  assert.throws(() => normalizeDomain('jobs.lever.co'), AppError);
});

test('contact ranking is bounded, verified, employer-domain scoped, and preference aware', () => {
  const campaign = { title: 'iOS Engineer', company: 'Example', domain: 'example.com' };
  const contacts = rankContacts([
    { value: 'senior@example.com', type: 'personal', first_name: 'Sam', last_name: 'Lee', position: 'Engineering Manager', department: 'it', seniority: 'senior', confidence: 90, verification: { status: 'valid' } },
    { value: 'other@outside.com', type: 'personal', first_name: 'Out', last_name: 'Side', position: 'Engineering Manager', department: 'it', seniority: 'senior', verification: { status: 'valid' } },
    { value: 'junior@example.com', type: 'personal', first_name: 'J', last_name: 'R', position: 'Developer', department: 'it', seniority: 'junior', verification: { status: 'valid' } },
    { value: 'bad@example.com', type: 'personal', first_name: 'Bad', last_name: 'Email', position: 'Engineering Manager', department: 'it', seniority: 'senior', verification: { status: 'unknown' } },
  ], campaign, { ...DEFAULT_SETTINGS, maxContacts: 5, recipientPreference: 'relevant' });
  assert.equal(contacts.length, 2);
  assert.equal(contacts[0].email, 'senior@example.com');
  assert.equal(contacts[0].verification, 'valid');
});

test('relevant filters include role, recruiting and leadership; broad filters preserve verification', () => {
  const filters = hunterFilters(DEFAULT_SETTINGS, 'Software Engineer');
  assert.equal(filters.department, 'it,hr,executive,management');
  assert.equal(filters.seniority, undefined);
  const settings = { ...DEFAULT_SETTINGS, recipientPreference: 'any' };
  const broad = hunterFilters(settings, 'Software Engineer');
  assert.equal(broad.department, undefined);
  assert.equal(broad.seniority, undefined);
  assert.equal(broad.required_field, 'full_name');
  assert.equal(broad.verification_status, 'valid');
  assert.equal(broad.limit, '5');
  const person = { value: 'recruiter@example.com', type: 'personal', first_name: 'Morgan', last_name: 'Lee', position: 'Recruiter', department: 'hr', verification: { status: 'valid' } };
  const campaign = { title: 'Software Engineer', domain: 'example.com' };
  assert.equal(rankContacts([person], campaign, DEFAULT_SETTINGS).length, 1);
  assert.equal(rankContacts([{ ...person, position: null, department: null }], campaign, settings).length, 1);
  for (const status of ['accept_all', 'unknown', 'invalid']) assert.equal(rankContacts([{ ...person, verification: { status } }], campaign, settings).length, 0);
});

test('template rendering and PDF validation reject unsafe input', () => {
  const campaign = { url: 'https://example.com/jobs/1', title: 'Designer', company: 'Example' };
  const contact = { id: 'c1', email: 'sam@example.com', firstName: 'Sam', lastName: 'Lee', position: 'Manager' };
  const settings = { ...DEFAULT_SETTINGS, senderName: 'Taylor' };
  const message = renderMessage(campaign, contact, settings);
  assert.match(message.body, /Sam/);
  assert.throws(() => renderMessage(campaign, { ...contact, firstName: '' }, settings), AppError);
  assert.doesNotThrow(() => validateResume({ filename: 'resume.pdf', dataBase64: Buffer.from('%PDF-1.7\n').toString('base64') }, Date.now()));
  assert.throws(() => validateResume({ filename: 'resume.pdf', dataBase64: Buffer.from('PNG').toString('base64') }, Date.now()), AppError);
  assert.doesNotThrow(() => validateSettings(settings));
});

test('MIME encoding contains a plain text body and optional PDF attachment', () => {
  const raw = buildMIME({
    senderName: 'Taylor', senderEmail: 'taylor@example.com',
    message: { id: 'message-1', to: 'sam@example.com', subject: 'Hello', body: 'A résumé note' },
    resume: { filename: 'résumé.pdf', dataBase64: Buffer.from('%PDF-1.7\n').toString('base64') },
  });
  const decoded = Buffer.from(raw, 'base64url').toString();
  assert.match(decoded, /multipart\/mixed/);
  assert.match(decoded, /application\/pdf/);
  assert.match(decoded, /filename\*=UTF-8''r%C3%A9sum%C3%A9.pdf/);
  assert.match(decoded, /Content-Transfer-Encoding: base64/);
});

test('Hunter company lookup returns a domain only for an exact organization match', async () => {
  const seen = [];
  const provider = new HunterProvider({ fetchImpl: async (url) => {
    seen.push(String(url));
    return new Response(JSON.stringify({ data: [{ company_name: 'Example Studio', domain: 'www.example.com' }] }), { status: 200 });
  } });
  assert.equal(await provider.findDomain('hunter-key', 'Example Studio'), 'example.com');
  assert.equal(new URL(seen[0]).searchParams.get('company'), 'Example Studio');
  assert.equal(new URL(seen[0]).searchParams.get('perfect_match'), 'true');

  const mismatch = new HunterProvider({ fetchImpl: async () => new Response(JSON.stringify({ data: [{ company_name: 'Example Studios', domain: 'example.com' }] }), { status: 200 }) });
  assert.equal(await mismatch.findDomain('hunter-key', 'Example Studio'), null);
});

test('company picker keeps actual suffixes, deduplicates domains and uses documented authentication', async () => {
  const provider = new HunterProvider({ fetchImpl: async (url, options) => {
    const params = new URL(url).searchParams;
    assert.equal(params.get('api_key'), null);
    assert.equal(options.headers['X-API-KEY'], 'test-secret');
    assert.equal(params.get('perfect_match'), 'false');
    assert.equal(params.get('limit'), '10');
    return Response.json({ data: [
      { company_name: 'Interface', domain: 'interface.ai' },
      { company_name: 'Interface duplicate', domain: 'interface.ai' },
      { company_name: 'Other Interface', domain: 'interface.co.uk' },
      { company_name: 'Invalid', domain: 'https://linkedin.com/company/test' }
    ] });
  } });
  assert.deepEqual(await provider.findCompanies('test-secret', 'Interface'), [
    { company: 'Interface', domain: 'interface.ai' },
    { company: 'Other Interface', domain: 'interface.co.uk' }
  ]);
  await assert.rejects(provider.findCompanies('test-secret', 'ab'), /3–100/);
});

test('Hunter failures distinguish network, key, and quota without leaking secrets', async () => {
  const timeout = new HunterProvider({ fetchImpl: async () => { throw new DOMException('secret URL must not leak', 'TimeoutError'); } });
  await assert.rejects(timeout.validateKey('secret-value'), error => error.code === 'provider_timeout' && /60 seconds/.test(error.message) && !error.message.includes('secret-value'));
  for (const [status, message] of [[401, /API key/], [429, /limits/], [403, /denied/]]) {
    const provider = new HunterProvider({ fetchImpl: async () => new Response('', { status }) });
    await assert.rejects(provider.validateKey('secret-value'), error => message.test(error.message) && !error.message.includes('secret-value'));
  }
  const provider = new HunterProvider({ fetchImpl: async url => { throw new Error(url); } });
  await assert.rejects(provider.validateKey('secret-value'), error => /connection failure/.test(error.message) && !error.message.includes('secret-value'));
});

test('a job without a link renders the default template without an empty Job line', async () => {
  const campaign = parseJobInput({ title: 'iOS Engineer', company: 'Example Studio' });
  const contact = { id: 'c1', email: 'sam@example.com', firstName: 'Sam' };
  const rendered = renderMessage(campaign, contact, { ...DEFAULT_SETTINGS, senderName: 'Taylor' });
  assert.doesNotMatch(rendered.body, /Job:|undefined|{{/);
  assert.match(rendered.body, /iOS Engineer/);
  let calls = 0;
  const resolver = new JobResolver({ fetchImpl: async () => { calls++; throw new Error('should not fetch'); } });
  assert.deepEqual(await resolver.resolve(campaign), campaign);
  assert.equal(calls, 0);
  assert.throws(() => parseJobInput({ title: 'iOS Engineer' }), /job title and company/);
});
