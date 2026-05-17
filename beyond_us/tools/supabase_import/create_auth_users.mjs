// Supabase profiles를 Auth 사용자로 생성하고 연결하는 CLI 도구
import crypto from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_PAGE_SIZE = 1000;
const SYNTHETIC_EMAIL_DOMAIN = 'auth.beyond-us.local';

function parseArgs(argv) {
  const result = {
    file: '',
    apply: false,
    dryRun: true,
    loginId: '',
    limit: 0,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--file') {
      result.file = argv[++i] || '';
    } else if (arg === '--apply') {
      result.apply = true;
      result.dryRun = false;
    } else if (arg === '--dry-run') {
      result.apply = false;
      result.dryRun = true;
    } else if (arg === '--login-id') {
      result.loginId = argv[++i] || '';
    } else if (arg === '--limit') {
      result.limit = Number(argv[++i]) || 0;
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else if (!result.file && !arg.startsWith('--')) {
      result.file = arg;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (result.dryRun && !result.file && !process.env.SUPABASE_URL) {
    throw new Error('Dry-run needs either --file <export.json> or SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY');
  }
  return result;
}

function printHelp() {
  console.log(`Usage:
  node beyond_us/tools/supabase_import/create_auth_users.mjs --file <export.json> --dry-run
  node beyond_us/tools/supabase_import/create_auth_users.mjs --dry-run
  node beyond_us/tools/supabase_import/create_auth_users.mjs --apply

Options:
  --login-id <id>   Limit to one profile.
  --limit <number>  Limit processed profiles for staged testing.

Environment variables for DB/Auth dry-run and apply:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
`);
}

async function readProfilesForDryRunFromFile(filePath) {
  const absolutePath = path.resolve(filePath);
  const raw = await readFile(absolutePath, 'utf8');
  const data = JSON.parse(raw);
  if (!Array.isArray(data.sheets)) throw new Error('Invalid export JSON: sheets must be an array');
  const usersSheet = data.sheets.find((sheet) => sheet.sheetName === 'Users');
  if (!usersSheet || !Array.isArray(usersSheet.rows)) throw new Error('Export JSON has no Users sheet');

  return usersSheet.rows
    .map((row, index) => {
      const object = row.object || {};
      const loginId = text(object['닉네임']);
      if (!loginId) return null;
      return {
        id: `dry-run-profile-${index + 1}`,
        participant_no: index + 1,
        login_id: loginId,
        name: text(object['이름']) || loginId,
        parish: text(object['소속']) || '미분류',
        role: bool(object['isDev(개발자)']) ? 'dev' : (bool(object.isStaff) ? 'admin' : 'user'),
        account_status: bool(object.inactive) ? 'inactive' : 'active',
        is_dev: bool(object['isDev(개발자)']),
        auth_user_id: null,
        password_migration_required: true,
      };
    })
    .filter(Boolean);
}

async function readProfilesForDryRunFromDb(config) {
  return fetchAll(config, 'profiles?select=id,participant_no,login_id,name,parish,role,account_status,is_dev,auth_user_id,password_migration_required&order=participant_no.asc');
}

function summarizePlan(profiles, existingAuthByEmail) {
  let alreadyLinked = 0;
  let linkExisting = 0;
  let createMissing = 0;

  const preview = profiles.slice(0, 20).map((profile) => {
    const email = syntheticEmail(profile.login_id);
    const existing = existingAuthByEmail.get(email);
    let action = 'create_auth_user';
    if (profile.auth_user_id) {
      action = 'already_linked';
      alreadyLinked += 1;
    } else if (existing) {
      action = 'link_existing_auth_user';
      linkExisting += 1;
    } else {
      createMissing += 1;
    }
    return {
      login_id: profile.login_id,
      name: profile.name,
      role: profile.role,
      account_status: profile.account_status,
      synthetic_email: email,
      action,
    };
  });

  for (const profile of profiles.slice(20)) {
    const email = syntheticEmail(profile.login_id);
    if (profile.auth_user_id) alreadyLinked += 1;
    else if (existingAuthByEmail.get(email)) linkExisting += 1;
    else createMissing += 1;
  }

  return {
    profileCount: profiles.length,
    alreadyLinked,
    linkExisting,
    createMissing,
    preview,
  };
}

function filterProfiles(profiles, args) {
  let filtered = profiles;
  if (args.loginId) {
    filtered = filtered.filter((profile) => profile.login_id === args.loginId);
  }
  if (args.limit > 0) {
    filtered = filtered.slice(0, args.limit);
  }
  return filtered;
}

function getSupabaseConfig() {
  const url = normalizeSupabaseUrl(process.env.SUPABASE_URL);
  const serviceRoleKey = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '');
  if (!url) throw new Error('Missing SUPABASE_URL');
  if (!serviceRoleKey) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
  return { url, serviceRoleKey };
}

function normalizeSupabaseUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error('Invalid SUPABASE_URL. Use the project URL like https://<project-ref>.supabase.co');
  }
  url.pathname = url.pathname.replace(/\/(rest|auth)\/v1\/?$/i, '');
  url.pathname = url.pathname.replace(/\/+$/, '');
  url.search = '';
  url.hash = '';
  return url.toString().replace(/\/+$/, '');
}

async function supabaseRestFetch(config, endpoint, options = {}) {
  const response = await fetch(`${config.url}/rest/v1/${endpoint}`, {
    ...options,
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  return parseResponse(response, `rest/v1/${endpoint}`);
}

async function supabaseAuthFetch(config, endpoint, options = {}) {
  const response = await fetch(`${config.url}/auth/v1/${endpoint}`, {
    ...options,
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  return parseResponse(response, `auth/v1/${endpoint}`);
}

async function parseResponse(response, endpoint) {
  const textBody = await response.text();
  const body = textBody ? safeJson(textBody) : null;
  if (!response.ok) {
    const detail = typeof body === 'string' ? body : JSON.stringify(body);
    throw new Error(`Supabase request failed ${response.status} ${endpoint}: ${detail}`);
  }
  return body;
}

async function fetchAll(config, endpoint, pageSize = DEFAULT_PAGE_SIZE) {
  const results = [];
  for (let offset = 0; ; offset += pageSize) {
    const separator = endpoint.includes('?') ? '&' : '?';
    const page = await supabaseRestFetch(config, `${endpoint}${separator}limit=${pageSize}&offset=${offset}`);
    if (!Array.isArray(page) || !page.length) break;
    results.push(...page);
    if (page.length < pageSize) break;
  }
  return results;
}

async function listAuthUsers(config) {
  const users = [];
  for (let page = 1; ; page += 1) {
    const body = await supabaseAuthFetch(config, `admin/users?page=${page}&per_page=${DEFAULT_PAGE_SIZE}`);
    const pageUsers = Array.isArray(body) ? body : (Array.isArray(body.users) ? body.users : []);
    if (!pageUsers.length) break;
    users.push(...pageUsers);
    if (pageUsers.length < DEFAULT_PAGE_SIZE) break;
  }
  return users;
}

function makeAuthUserMap(users) {
  const map = new Map();
  for (const user of users) {
    if (user && user.email) map.set(String(user.email).toLowerCase(), user);
  }
  return map;
}

async function createAuthUser(config, profile) {
  const email = syntheticEmail(profile.login_id);
  const body = await supabaseAuthFetch(config, 'admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email,
      password: crypto.randomBytes(32).toString('base64url'),
      email_confirm: true,
      user_metadata: {
        login_id: profile.login_id,
        display_name: profile.login_id,
        name: profile.name,
        parish: profile.parish,
      },
      app_metadata: {
        source: 'beyond_us_migration',
        role: profile.role,
        profile_id: profile.id,
      },
    }),
  });
  const user = body && body.user ? body.user : body;
  if (!user || !user.id) throw new Error(`Auth user create returned no id for ${profile.login_id}`);
  return user;
}

async function linkProfile(config, profileId, authUserId) {
  await supabaseRestFetch(config, `profiles?id=eq.${encodeURIComponent(profileId)}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      auth_user_id: authUserId,
      password_migration_required: true,
    }),
  });
}

async function applyAuthUserPlan(config, profiles) {
  const authUsers = await listAuthUsers(config);
  const existingAuthByEmail = makeAuthUserMap(authUsers);
  const results = [];

  for (const profile of profiles) {
    const email = syntheticEmail(profile.login_id);
    if (profile.auth_user_id) {
      results.push({ login_id: profile.login_id, action: 'already_linked', auth_user_id: profile.auth_user_id });
      continue;
    }

    let user = existingAuthByEmail.get(email);
    let action = 'link_existing_auth_user';
    if (!user) {
      user = await createAuthUser(config, profile);
      existingAuthByEmail.set(email, user);
      action = 'created_auth_user';
    }

    await linkProfile(config, profile.id, user.id);
    results.push({ login_id: profile.login_id, action, auth_user_id: user.id });
  }

  return results;
}

function syntheticEmail(loginId) {
  const hash = crypto.createHash('sha256').update(String(loginId).trim()).digest('hex');
  return `u_${hash}@${SYNTHETIC_EMAIL_DOMAIN}`;
}

function text(value) {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

function bool(value) {
  if (value === true || value === 1) return true;
  if (value === false || value === 0 || value === null || value === undefined || value === '') return false;
  const normalized = String(value).trim().toLowerCase();
  return ['true', '1', 'yes', 'y', 'checked', '✓'].includes(normalized);
}

function safeJson(value) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = args.file && args.dryRun && !process.env.SUPABASE_URL ? null : getSupabaseConfig();
  const profiles = filterProfiles(
    config ? await readProfilesForDryRunFromDb(config) : await readProfilesForDryRunFromFile(args.file),
    args,
  );
  const existingAuthByEmail = config ? makeAuthUserMap(await listAuthUsers(config)) : new Map();

  if (args.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      mode: 'dry-run',
      source: config ? 'supabase_profiles' : 'export_json',
      ...summarizePlan(profiles, existingAuthByEmail),
    }, null, 2));
    return;
  }

  const results = await applyAuthUserPlan(config, profiles);
  console.log(JSON.stringify({
    ok: true,
    mode: 'apply',
    processed: results.length,
    summary: results.reduce((acc, row) => {
      acc[row.action] = (acc[row.action] || 0) + 1;
      return acc;
    }, {}),
    results: results.slice(0, 50),
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
