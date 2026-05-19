// 기존 Users 시트 비밀번호 해시를 Supabase legacy_auth_hashes에 적재하는 CLI 도구
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_CHUNK_ROWS = 200;

function parseArgs(argv) {
  const result = {
    file: '',
    apply: false,
    dryRun: true,
    chunkRows: DEFAULT_CHUNK_ROWS,
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
    } else if (arg === '--chunk-rows') {
      result.chunkRows = Number(argv[++i]) || DEFAULT_CHUNK_ROWS;
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else if (!result.file && !arg.startsWith('--')) {
      result.file = arg;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!result.file) throw new Error('Missing required --file <export.json>');
  if (result.chunkRows < 1) throw new Error('--chunk-rows must be greater than 0');
  return result;
}

function printHelp() {
  console.log(`Usage:
  node beyond_us/tools/supabase_import/import_legacy_auth_hashes.mjs --file <export.json> --dry-run
  node beyond_us/tools/supabase_import/import_legacy_auth_hashes.mjs --file <export.json> --apply

Environment variables for --apply:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
`);
}

async function readExportFile(filePath) {
  const absolutePath = path.resolve(filePath);
  const raw = await readFile(absolutePath, 'utf8');
  const data = JSON.parse(raw);
  if (!data || data.exportVersion !== 1 || !Array.isArray(data.sheets)) {
    throw new Error(`Invalid export JSON: ${absolutePath}`);
  }
  return { data, absolutePath };
}

function extractPasswordHashes(data) {
  const usersSheet = data.sheets.find((sheet) => sheet.sheetName === 'Users');
  if (!usersSheet || !Array.isArray(usersSheet.rows)) {
    throw new Error('Export JSON has no Users sheet');
  }

  const rows = [];
  const issues = [];
  for (const row of usersSheet.rows) {
    const object = row.object || {};
    const loginId = text(object['닉네임']);
    const passwordHash = text(object['비밀번호']);
    if (!loginId) {
      issues.push({ rowNumber: row.rowNumber, issue: 'missing_login_id' });
      continue;
    }
    if (!passwordHash) {
      issues.push({ rowNumber: row.rowNumber, loginId, issue: 'missing_password_hash' });
      continue;
    }
    if (!passwordHash.startsWith('pwv1$')) {
      issues.push({ rowNumber: row.rowNumber, loginId, issue: 'unsupported_password_hash' });
      continue;
    }
    rows.push({
      login_id: loginId,
      hash_version: 'pwv1',
      password_hash: passwordHash,
      migrated_at: null,
      failed_attempts: 0,
      locked_until: null,
      last_attempt_at: null,
    });
  }
  return { rows, issues };
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
  url.pathname = url.pathname.replace(/\/rest\/v1\/?$/i, '');
  url.pathname = url.pathname.replace(/\/+$/, '');
  url.search = '';
  url.hash = '';
  return url.toString().replace(/\/+$/, '');
}

async function supabaseFetch(config, endpoint, options = {}) {
  const response = await fetch(`${config.url}/rest/v1/${endpoint}`, {
    ...options,
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });

  const textBody = await response.text();
  const body = textBody ? safeJson(textBody) : null;
  if (!response.ok) {
    const detail = typeof body === 'string' ? body : JSON.stringify(body);
    throw new Error(`Supabase request failed ${response.status} ${endpoint}: ${detail}`);
  }
  return body;
}

async function fetchProfileMap(config) {
  const profiles = await fetchAll(config, 'profiles?select=id,login_id&order=participant_no.asc');
  const map = new Map();
  for (const profile of profiles) {
    map.set(profile.login_id, profile.id);
  }
  return map;
}

async function fetchAll(config, endpoint, pageSize = 1000) {
  const results = [];
  for (let offset = 0; ; offset += pageSize) {
    const separator = endpoint.includes('?') ? '&' : '?';
    const page = await supabaseFetch(config, `${endpoint}${separator}limit=${pageSize}&offset=${offset}`);
    if (!Array.isArray(page) || !page.length) break;
    results.push(...page);
    if (page.length < pageSize) break;
  }
  return results;
}

async function applyRows(config, rows, chunkRows) {
  const profileMap = await fetchProfileMap(config);
  const existingLegacyMap = await fetchExistingLegacyHashMap(config);
  const missingProfiles = [];
  const skippedMigrated = [];
  const payloadRows = [];

  for (const row of rows) {
    const profileId = profileMap.get(row.login_id);
    if (!profileId) {
      missingProfiles.push(row.login_id);
      continue;
    }
    const existingLegacy = existingLegacyMap.get(profileId);
    if (existingLegacy && existingLegacy.migrated_at) {
      skippedMigrated.push(row.login_id);
      continue;
    }
    payloadRows.push({
      profile_id: profileId,
      login_id: row.login_id,
      hash_version: row.hash_version,
      password_hash: row.password_hash,
      migrated_at: row.migrated_at,
      failed_attempts: row.failed_attempts,
      locked_until: row.locked_until,
      last_attempt_at: row.last_attempt_at,
    });
  }

  let chunks = 0;
  for (const chunk of chunkArray(payloadRows, chunkRows)) {
    await supabaseFetch(config, 'legacy_auth_hashes?on_conflict=profile_id', {
      method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(chunk),
    });
    chunks += 1;
  }

  return {
    imported: payloadRows.length,
    chunks,
    missingProfiles,
    skippedMigrated,
  };
}

async function fetchExistingLegacyHashMap(config) {
  const rows = await fetchAll(config, 'legacy_auth_hashes?select=profile_id,migrated_at');
  const map = new Map();
  for (const row of rows) {
    map.set(row.profile_id, row);
  }
  return map;
}

function text(value) {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

function safeJson(value) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function chunkArray(rows, size) {
  const chunks = [];
  for (let index = 0; index < rows.length; index += size) {
    chunks.push(rows.slice(index, index + size));
  }
  return chunks;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { data, absolutePath } = await readExportFile(args.file);
  const { rows, issues } = extractPasswordHashes(data);

  if (args.dryRun) {
    console.log(JSON.stringify({
      ok: issues.length === 0,
      mode: 'dry-run',
      file: absolutePath,
      sourceEnvironment: data.sourceEnvironment,
      sourceSnapshotLabel: data.sourceSnapshotLabel || '',
      hashesPlanned: rows.length,
      issues,
    }, null, 2));
    return;
  }

  if (issues.length) {
    throw new Error(`Cannot apply with password hash issues: ${JSON.stringify(issues.slice(0, 10))}`);
  }

  const config = getSupabaseConfig();
  const result = await applyRows(config, rows, args.chunkRows);
  console.log(JSON.stringify({
    ok: result.missingProfiles.length === 0,
    mode: 'apply',
    sourceEnvironment: data.sourceEnvironment,
    sourceSnapshotLabel: data.sourceSnapshotLabel || '',
    imported: result.imported,
    chunks: result.chunks,
    missingProfiles: result.missingProfiles,
    skippedMigrated: result.skippedMigrated,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
