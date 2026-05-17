// Supabase 이관 JSON을 감사 테이블에 적재하는 CLI 도구
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_MAX_ROWS_PER_CHUNK = 250;
const DEFAULT_MAX_BYTES_PER_CHUNK = 1_500_000;

function parseArgs(argv) {
  const result = {
    file: '',
    apply: false,
    dryRun: true,
    chunkRows: DEFAULT_MAX_ROWS_PER_CHUNK,
    chunkBytes: DEFAULT_MAX_BYTES_PER_CHUNK,
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
      result.chunkRows = Number(argv[++i]) || DEFAULT_MAX_ROWS_PER_CHUNK;
    } else if (arg === '--chunk-bytes') {
      result.chunkBytes = Number(argv[++i]) || DEFAULT_MAX_BYTES_PER_CHUNK;
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
  if (result.chunkBytes < 50_000) throw new Error('--chunk-bytes is too small');
  return result;
}

function printHelp() {
  console.log(`Usage:
  node beyond_us/tools/supabase_import/import_legacy_rows.mjs --file <export.json> --dry-run
  node beyond_us/tools/supabase_import/import_legacy_rows.mjs --file <export.json> --apply

Environment variables for --apply:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
`);
}

async function readExportFile(filePath) {
  const absolutePath = path.resolve(filePath);
  const raw = await readFile(absolutePath, 'utf8');
  const data = JSON.parse(raw);
  validateExportPayload(data, absolutePath);
  return { data, absolutePath };
}

function validateExportPayload(data, absolutePath) {
  if (!data || typeof data !== 'object') {
    throw new Error(`Invalid export JSON: ${absolutePath}`);
  }
  if (data.exportVersion !== 1) {
    throw new Error(`Unsupported exportVersion: ${data.exportVersion}`);
  }
  if (data.sourceEnvironment !== 'dev' && data.sourceEnvironment !== 'prod') {
    throw new Error(`Invalid sourceEnvironment: ${data.sourceEnvironment}`);
  }
  if (!Array.isArray(data.sheets)) {
    throw new Error('Invalid export JSON: sheets must be an array');
  }
}

function flattenLegacyRows(data) {
  const rows = [];
  for (const sheet of data.sheets) {
    if (!sheet || typeof sheet !== 'object') continue;
    const sheetName = String(sheet.sheetName || '').trim();
    if (!sheetName || !Array.isArray(sheet.rows)) continue;

    for (const row of sheet.rows) {
      const rowNumber = Number(row.rowNumber) || 0;
      if (!rowNumber) continue;
      rows.push({
        source_environment: data.sourceEnvironment,
        sheet_name: sheetName,
        row_number: rowNumber,
        row_key: stringifyOptional(row.rowKey),
        source_hash: String(row.sourceHash || ''),
        row_payload: {
          sourceSnapshotLabel: data.sourceSnapshotLabel || '',
          headerRow: sheet.headerRow,
          dataStartRow: sheet.dataStartRow,
          headers: sheet.headers || [],
          values: row.values || [],
          object: row.object || {},
        },
      });
    }
  }
  return rows;
}

function stringifyOptional(value) {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text || null;
}

function summarizeExport(data, rows) {
  const calculatedRowCounts = {};
  for (const row of rows) {
    calculatedRowCounts[row.sheet_name] = (calculatedRowCounts[row.sheet_name] || 0) + 1;
  }

  return {
    ok: true,
    exportVersion: data.exportVersion,
    sourceEnvironment: data.sourceEnvironment,
    sourceSpreadsheetId: data.sourceSpreadsheetId || '',
    sourceSpreadsheetName: data.sourceSpreadsheetName || '',
    sourceSnapshotLabel: data.sourceSnapshotLabel || '',
    exportedAt: data.exportedAt || '',
    sheetCount: Array.isArray(data.sheets) ? data.sheets.length : 0,
    rowTotal: rows.length,
    rowCounts: data.rowCounts || calculatedRowCounts,
    calculatedRowCounts,
    missingSheets: data.missingSheets || [],
  };
}

function getSupabaseConfig() {
  const url = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const serviceRoleKey = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '');
  if (!url) throw new Error('Missing SUPABASE_URL');
  if (!serviceRoleKey) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
  return { url, serviceRoleKey };
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

  const text = await response.text();
  const body = text ? safeJson(text) : null;
  if (!response.ok) {
    const detail = typeof body === 'string' ? body : JSON.stringify(body);
    throw new Error(`Supabase request failed ${response.status} ${endpoint}: ${detail}`);
  }
  return body;
}

function safeJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function createMigrationBatch(config, data, rows) {
  const payload = {
    source_environment: data.sourceEnvironment,
    source_spreadsheet_id: data.sourceSpreadsheetId || null,
    source_snapshot_label: data.sourceSnapshotLabel || null,
    status: 'running',
    started_at: new Date().toISOString(),
    row_counts: data.rowCounts || summarizeExport(data, rows).calculatedRowCounts,
    notes: 'legacy_sheet_rows import',
  };

  const created = await supabaseFetch(config, 'migration_batches', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(payload),
  });
  if (!Array.isArray(created) || !created[0]?.id) {
    throw new Error('Could not create migration batch');
  }
  return created[0].id;
}

async function updateMigrationBatch(config, batchId, patch) {
  await supabaseFetch(config, `migration_batches?id=eq.${encodeURIComponent(batchId)}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify(patch),
  });
}

function attachBatchId(rows, batchId) {
  return rows.map((row) => ({
    ...row,
    batch_id: batchId,
  }));
}

function chunkRows(rows, maxRows, maxBytes) {
  const chunks = [];
  let current = [];
  let currentBytes = 2;

  for (const row of rows) {
    const rowBytes = Buffer.byteLength(JSON.stringify(row), 'utf8') + 1;
    const wouldExceedRows = current.length >= maxRows;
    const wouldExceedBytes = current.length > 0 && currentBytes + rowBytes > maxBytes;
    if (wouldExceedRows || wouldExceedBytes) {
      chunks.push(current);
      current = [];
      currentBytes = 2;
    }
    current.push(row);
    currentBytes += rowBytes;
  }

  if (current.length) chunks.push(current);
  return chunks;
}

async function upsertLegacyRows(config, rows, options) {
  const chunks = chunkRows(rows, options.chunkRows, options.chunkBytes);
  let imported = 0;

  for (let i = 0; i < chunks.length; i += 1) {
    const chunk = chunks[i];
    await supabaseFetch(
      config,
      'legacy_sheet_rows?on_conflict=source_environment,sheet_name,row_number',
      {
        method: 'POST',
        headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify(chunk),
      },
    );
    imported += chunk.length;
    process.stderr.write(`Imported chunk ${i + 1}/${chunks.length} (${imported}/${rows.length})\n`);
  }

  return { imported, chunks: chunks.length };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { data, absolutePath } = await readExportFile(args.file);
  const rows = flattenLegacyRows(data);
  const summary = summarizeExport(data, rows);

  if (args.dryRun) {
    console.log(JSON.stringify({
      ...summary,
      mode: 'dry-run',
      file: absolutePath,
      chunkRows: args.chunkRows,
      chunkBytes: args.chunkBytes,
    }, null, 2));
    return;
  }

  const config = getSupabaseConfig();
  const batchId = await createMigrationBatch(config, data, rows);
  try {
    const rowsWithBatch = attachBatchId(rows, batchId);
    const importResult = await upsertLegacyRows(config, rowsWithBatch, args);
    await updateMigrationBatch(config, batchId, {
      status: 'completed',
      completed_at: new Date().toISOString(),
    });
    console.log(JSON.stringify({
      ...summary,
      mode: 'apply',
      file: absolutePath,
      batchId,
      imported: importResult.imported,
      chunks: importResult.chunks,
    }, null, 2));
  } catch (error) {
    await updateMigrationBatch(config, batchId, {
      status: 'failed',
      completed_at: new Date().toISOString(),
      notes: `legacy_sheet_rows import failed: ${error.message}`,
    });
    throw error;
  }
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
