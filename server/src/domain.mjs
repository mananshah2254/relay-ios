import { randomUUID } from 'node:crypto';
import { isIP } from 'node:net';

export class AppError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

export const DEFAULT_SETTINGS = Object.freeze({
  senderName: '',
  subjectTemplate: 'Referral request — {{job_title}} at {{company}}',
  bodyTemplate: 'Hi {{first_name}},\n\nMy name is {{sender_name}}, and I’m interested in the {{job_title}} role at {{company}}. I’d welcome the chance to discuss how my background could contribute to your team.\n\nIf you think my background could be a fit, would you be open to referring me or pointing me toward the right person? I’d be happy to share more about my experience.\n\nJob: {{job_url}}\n\nThank you for your time,\n{{sender_name}}',
  maxContacts: 5,
  sendIntervalSeconds: 600,
  dailyLimit: 10,
  recipientPreference: 'relevant',
  sendingMode: 'review',
  autoConfirmCompany: false,
  attachResume: false,
});

const PLACEHOLDERS = new Set(['first_name', 'company', 'job_title', 'job_url', 'sender_name']);
export const id = () => randomUUID();
export const clone = value => structuredClone(value);
export const iso = milliseconds => new Date(milliseconds).toISOString();
export const emailValid = value => typeof value === 'string' && value.length <= 254 && /^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9.-]*[A-Z0-9])?\.[A-Z]{2,63}$/i.test(value);

export function string(value, label, max = 200, empty = false) {
  if (typeof value !== 'string' || value.length > max || (!empty && !value.trim())) {
    throw new AppError('invalid_input', `${label} must be ${empty ? 'text' : 'non-empty text'} of at most ${max} characters.`);
  }
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) throw new AppError('invalid_input', `${label} contains unsupported control characters.`);
  return value.trim();
}

export function noNewline(value, label) {
  if (/[\r\n]/.test(value)) throw new AppError('invalid_input', `${label} must be a single line.`);
  return value;
}

export function validateTemplate(template, label) {
  const withoutKnown = template.replace(/{{\s*([a-z_]+)\s*}}/g, (token, name) => {
    if (!PLACEHOLDERS.has(name)) throw new AppError('invalid_template', `Unsupported template field: ${name}.`);
    return '';
  });
  if (withoutKnown.includes('{{') || withoutKnown.includes('}}')) throw new AppError('invalid_template', `${label} has an incomplete template field.`);
  return template;
}

export function validateSettings(input) {
  const settings = {};
  settings.senderName = noNewline(string(input.senderName, 'Sender name', 120, true), 'Sender name');
  settings.subjectTemplate = validateTemplate(noNewline(string(input.subjectTemplate, 'Subject', 200), 'Subject'), 'Subject');
  settings.bodyTemplate = validateTemplate(string(input.bodyTemplate, 'Email template', 20000), 'Email template');
  for (const [key, minimum, maximum] of [['maxContacts', 1, 20], ['dailyLimit', 1, 100], ['sendIntervalSeconds', 600, 3600]]) {
    if (!Number.isInteger(input[key]) || input[key] < minimum || input[key] > maximum) throw new AppError('invalid_settings', `${key} must be between ${minimum} and ${maximum}.`);
    settings[key] = input[key];
  }
  if (!['relevant', 'senior', 'executive', 'recruiting'].includes(input.recipientPreference)) throw new AppError('invalid_settings', 'Unknown recipient preference.');
  settings.recipientPreference = input.recipientPreference;
  if (!['review', 'automatic'].includes(input.sendingMode)) throw new AppError('invalid_settings', 'Choose review or automatic sending.');
  settings.sendingMode = input.sendingMode;
  if (input.autoConfirmCompany != null && typeof input.autoConfirmCompany !== 'boolean') throw new AppError('invalid_settings', 'Automatic company confirmation must be a boolean.');
  settings.autoConfirmCompany = input.autoConfirmCompany === true;
  const roles = ['general', 'software', 'support', 'ai'];
  if (input.selectedTemplate != null && !roles.includes(input.selectedTemplate)) throw new AppError('invalid_settings', 'Unknown template role.');
  settings.selectedTemplate = input.selectedTemplate || 'general';
  settings.roleTemplates = {};
  if (input.roleTemplates != null) {
    if (typeof input.roleTemplates !== 'object' || Array.isArray(input.roleTemplates)) throw new AppError('invalid_settings', 'Invalid role templates.');
    for (const [role, template] of Object.entries(input.roleTemplates)) {
      if (!roles.includes(role) || !template || typeof template !== 'object') throw new AppError('invalid_settings', 'Unknown template role.');
      settings.roleTemplates[role] = {
        subject: validateTemplate(noNewline(string(template.subject, 'Role subject', 200), 'Role subject'), 'Role subject'),
        body: validateTemplate(string(template.body, 'Role message', 20000), 'Role message'),
      };
    }
  }
  if (typeof input.attachResume !== 'boolean') throw new AppError('invalid_settings', 'attachResume must be a boolean.');
  settings.attachResume = input.attachResume;
  return settings;
}

export function normalizeDomain(input) {
  let domain = string(input, 'Company domain', 253, true).toLowerCase();
  if (!domain) return '';
  if (domain.includes('://')) {
    const url = new URL(domain);
    if (url.username || url.password || url.port || !['https:', 'http:'].includes(url.protocol)) throw new AppError('invalid_domain', 'Enter a company website domain.');
    domain = url.hostname;
  }
  domain = domain.replace(/^www\./, '').replace(/\.$/, '');
  if (isIP(domain) || !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(domain) || /\.(local|localhost|internal|test|invalid)$/.test(domain)) {
    throw new AppError('invalid_domain', 'Enter a public company website domain, such as company.com.');
  }
  if (domain.endsWith('.greenhouse.io') || ['linkedin.com', 'lnkd.in', 'lever.co', 'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com'].some(blocked => domain === blocked || domain.endsWith(`.${blocked}`))) {
    throw new AppError('invalid_domain', 'Use the employer’s own website domain.');
  }
  return domain;
}

// Greenhouse's official press kit at greenhouse.com/press-kit publishes
// @greenhouse.io contacts. Do not infer arbitrary .com/.io equivalence.
export function employerEmailDomain(company, domain) {
  return /^(greenhouse|greenhouse software)(,? inc\.?)?$/i.test(company.trim()) && domain === 'greenhouse.com' ? 'greenhouse.io' : domain;
}

export function canonicalJobURL(raw) {
  let url;
  try { url = new URL(string(raw, 'Job URL', 4096)); } catch { throw new AppError('invalid_url', 'Enter a valid HTTPS job URL.'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) throw new AppError('invalid_url', 'Enter a public HTTPS job URL without credentials or a custom port.');
  if (isIP(url.hostname) || !url.hostname.includes('.') || /\.(localhost|local|internal)$/.test(url.hostname)) throw new AppError('invalid_url', 'A public job URL is required.');
  url.hash = '';
  const linkedIn = url.hostname === 'linkedin.com' || url.hostname.endsWith('.linkedin.com');
  const linkedInID = linkedIn && (url.pathname.match(/\/jobs\/view\/(?:[^/]*-)?(\d+)\/?$/)?.[1] || url.searchParams.get('currentJobId'));
  if (linkedInID && /^\d+$/.test(linkedInID)) return `https://www.linkedin.com/jobs/view/${linkedInID}`;
  for (const key of [...url.searchParams.keys()]) if (/^(utm_|trk$|trackingId$|refId$|ref$|source$|sourceId$)/i.test(key)) url.searchParams.delete(key);
  url.searchParams.sort();
  url.pathname = url.pathname.replace(/\/$/, '') || '/';
  return url.toString();
}

export function parseJobInput(input, current = {}) {
  const result = {};
  const rawURL = string(input.url ?? current.url ?? '', 'Job URL', 4096, true);
  result.url = rawURL ? canonicalJobURL(rawURL) : '';
  for (const [field, max] of [['title', 300], ['company', 200], ['description', 40000], ['sharedText', 40000]]) {
    result[field] = string(input[field] ?? current[field] ?? '', field, max, true);
    if (['title', 'company'].includes(field)) noNewline(result[field], field);
  }
  result.domain = normalizeDomain(input.domain ?? current.domain ?? '');
  // Parse explicit labels only. A URL or a company slug is not proof of an employer.
  const text = result.sharedText;
  const share = text.match(/(?:check out this job at|job at)\s+([^:\n]{1,200}):\s*([^\n]{1,300})/i);
  if (share) {
    result.company ||= share[1].trim();
    result.title ||= share[2].replace(/https?:\/\/\S+/g, '').trim();
  }
  result.title ||= text.match(/^(?:job title|role|title):\s*(.{1,300})$/im)?.[1]?.trim() || '';
  result.company ||= text.match(/^company:\s*(.{1,200})$/im)?.[1]?.trim() || '';
  // Standard shared page titles, not guesses from URL slugs.
  const pageTitle = text.match(/^([^\n|]{1,200}?) hiring ([^\n|]{1,300}?)(?: in [^\n|]+)?\s*\|\s*LinkedIn\s*$/im);
  if (pageTitle) { result.company ||= pageTitle[1].trim(); result.title ||= pageTitle[2].trim(); }
  result.domain = employerEmailDomain(result.company, result.domain);
  if (!result.url && (!result.title || !result.company)) throw new AppError('job_details_missing', 'Enter the job title and company, or share a job link.');
  return result;
}

export function roleDepartment(title) {
  const rules = [
    [/engineer|developer|software|data|security|technical|\bit\b|infrastructure/i, 'it'],
    [/design|ux|ui\b/i, 'design'], [/product/i, 'product'], [/sales|account executive/i, 'sales'],
    [/marketing|growth/i, 'marketing'], [/recruit|talent|human resource/i, 'hr'],
    [/finance|accountant/i, 'finance'], [/legal|counsel/i, 'legal'], [/research|scientist/i, 'research'],
    [/support|customer success/i, 'support'], [/operation/i, 'operations'],
  ];
  return rules.find(([pattern]) => pattern.test(title))?.[1] || null;
}

export function hunterFilters(settings, title) {
  const filters = { limit: String(settings.maxContacts), offset: '0', type: 'personal', required_field: settings.recipientPreference === 'any' ? 'full_name' : 'full_name,position', verification_status: 'valid' };
  if (settings.recipientPreference === 'executive') filters.seniority = 'executive';
  else if (settings.recipientPreference === 'recruiting') filters.department = 'hr';
  else if (settings.recipientPreference === 'senior') {
    filters.seniority = 'senior,executive';
  } else if (settings.recipientPreference === 'relevant') {
    filters.department = [...new Set([roleDepartment(title), 'hr', 'executive', 'management'].filter(Boolean))].join(',');
  }
  return filters;
}

export function rankContacts(emails, campaign, settings) {
  const seen = new Set();
  const department = roleDepartment(campaign.title);
  return emails.slice(0, settings.maxContacts).flatMap(person => {
    const email = String(person.value || '').trim().toLowerCase();
    const verified = person.verification?.status;
    if (!emailValid(email) || seen.has(email) || person.type !== 'personal' || verified !== 'valid') return [];
    if (email.split('@')[1] !== campaign.domain && !email.split('@')[1].endsWith(`.${campaign.domain}`)) return [];
    const firstName = String(person.first_name || '').trim();
    const lastName = String(person.last_name || '').trim();
    const position = String(person.position || '').trim();
    if (!firstName || (settings.recipientPreference !== 'any' && !position) || /[\r\n]/.test(firstName + lastName + position)) return [];
    if (settings.recipientPreference === 'executive' && person.seniority !== 'executive') return [];
    if (settings.recipientPreference === 'recruiting' && person.department !== 'hr') return [];
    if (settings.recipientPreference === 'senior' && !['senior', 'executive'].includes(person.seniority)) return [];
    if (settings.recipientPreference === 'relevant' && ![department, 'hr', 'executive', 'management'].filter(Boolean).includes(person.department)) return [];
    seen.add(email);
    const matched = department && person.department === department;
    const score = (matched ? 50 : 0) + (person.seniority === 'senior' ? 20 : 10) + Math.min(100, Number(person.confidence) || 0) / 10;
    const category = matched ? 'Role-department contact' : person.department === 'hr' ? 'Recruiting / HR contact' : ['executive', 'management'].includes(person.department) ? 'Leadership contact' : 'Company colleague';
    const reason = `${category}; Hunter reports this email as valid. Hiring or referral responsibility is not confirmed.`;
    return [{ id: id(), email, firstName, lastName, position, department: String(person.department || ''), verification: 'valid', reason, score }];
  }).sort((a, b) => b.score - a.score).map(({ score, ...contact }) => contact);
}

export function renderMessage(campaign, contact, settings) {
  const values = { first_name: contact.firstName, last_name: contact.lastName, company: campaign.company, job_title: campaign.title, job_url: campaign.url, sender_name: settings.senderName, position: contact.position };
  const render = source => (campaign.url ? source : source.replace(/^[\t ]*(?:Job(?: link)?[\t ]*:[\t ]*)?{{\s*job_url\s*}}[\t ]*(?:\r?\n|$)/gim, '')).replace(/{{\s*([a-z_]+)\s*}}/g, (_, key) => {
    const value = values[key];
    if (key === 'job_url' && !campaign.url) return '';
    if (!value) throw new AppError('incomplete_template', `Template field ${key} has no value.`);
    return value;
  });
  const subject = noNewline(render(settings.subjectTemplate), 'Rendered subject');
  const body = render(settings.bodyTemplate);
  if (subject.length > 900 || body.length > 50000 || /{{|}}/.test(subject + body)) throw new AppError('invalid_template', 'The rendered email is too long or has unresolved fields.');
  return { id: id(), contactId: contact.id, to: contact.email, subject, body, status: 'draft' };
}

export function validateResume(input, now) {
  const filename = noNewline(string(input.filename, 'PDF filename', 180), 'PDF filename');
  if (!filename.toLowerCase().endsWith('.pdf') || /[/\\]/.test(filename)) throw new AppError('invalid_resume', 'Upload a PDF with a simple filename.');
  if (typeof input.dataBase64 !== 'string' || input.dataBase64.length > 14_000_000 || !/^[A-Za-z0-9+/]*={0,2}$/.test(input.dataBase64)) throw new AppError('invalid_resume', 'Upload a PDF no larger than 10 MiB.');
  const data = Buffer.from(input.dataBase64, 'base64');
  if (data.length < 5 || data.length > 10 * 1024 * 1024 || !data.subarray(0, 1024).includes(Buffer.from('%PDF-'))) throw new AppError('invalid_resume', 'The file is not a recognizable PDF, or exceeds 10 MiB.');
  return { id: id(), filename, byteCount: data.length, uploadedAt: iso(now), dataBase64: data.toString('base64') };
}

export function publicResume(resume) {
  if (!resume) return null;
  const { dataBase64, ...metadata } = resume;
  return metadata;
}

export function publicCampaign(campaign) {
  const { id, url, title, company, domain, description, status, createdAt, contacts, messages, note, domainConfirmed } = campaign;
  const canRetryLookup = status === 'failed' && campaign.budgetReserved > 0 && campaign.fetchedCount === undefined && !messages.length && !contacts.length && !campaign.lookupRetryUsed && (campaign.lookupFailed === true || /^Hunter (request failed|could not be reached|did not finish)/.test(note || ''));
  return clone({ id, url, title, company, domain, description, status, createdAt, contacts, canRetryLookup, canBroadenSearch: status === 'failed' && campaign.fetchedCount === 0 && messages.length === 0 && contacts.length === 0 && !campaign.broadenedSearch, domainConfirmed: domainConfirmed === true, messages: messages.map(({ attemptAt, ...message }) => message), ...(note ? { note } : {}) });
}
