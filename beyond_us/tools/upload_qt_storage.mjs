// Q.T. 날짜별 PNG를 Supabase Storage에 업로드하는 도구
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultQtDir = path.resolve(scriptDir, '..', 'QT');
const args = new Set(process.argv.slice(2));
const apply = args.has('--apply');

function readArg(name, fallback) {
  const prefix = `${name}=`;
  const found = process.argv.slice(2).find(arg => arg.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectUrl = (
  process.env.BEYOND_US_SUPABASE_URL ||
  process.env.SUPABASE_PROJECT_URL ||
  process.env.SUPABASE_URL ||
  ''
).replace(/\/+$/, '');
const serviceRoleKey = (
  process.env.BEYOND_US_SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  ''
);
const bucket = readArg('--bucket', process.env.BEYOND_US_SUPABASE_STORAGE_BUCKET || 'beyond-us-photos');
const prefix = readArg('--prefix', 'QT').replace(/^\/+|\/+$/g, '');
const qtDir = path.resolve(readArg('--dir', defaultQtDir));

if (apply && (!projectUrl || !serviceRoleKey)) {
  console.error('Missing env. Set BEYOND_US_SUPABASE_URL and BEYOND_US_SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

function encodeStorageObjectPath(objectPath) {
  return objectPath.split('/').map(encodeURIComponent).join('/');
}

async function uploadFile(fileName) {
  const localPath = path.join(qtDir, fileName);
  const objectPath = `${prefix}/${fileName}`;
  if (!apply) {
    return { fileName, objectPath, dryRun: true };
  }

  const bytes = await fs.readFile(localPath);
  const res = await fetch(`${projectUrl}/storage/v1/object/${bucket}/${encodeStorageObjectPath(objectPath)}`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: bytes,
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`${fileName}: ${res.status} ${detail}`);
  }
  return { fileName, objectPath, uploaded: true };
}

const entries = await fs.readdir(qtDir, { withFileTypes: true });
const files = entries
  .filter(entry => entry.isFile() && /^\d{6}\.png$/i.test(entry.name))
  .map(entry => entry.name)
  .sort();

if (!files.length) {
  console.error(`No YYMMDD.png files found in ${qtDir}`);
  process.exit(1);
}

const results = [];
for (const fileName of files) {
  results.push(await uploadFile(fileName));
}

console.log(JSON.stringify({
  ok: true,
  dryRun: !apply,
  projectUrl,
  bucket,
  prefix,
  dir: qtDir,
  count: results.length,
  sample: results.slice(0, 5),
}, null, 2));
