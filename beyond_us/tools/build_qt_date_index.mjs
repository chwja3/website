// Q.T. PDF 텍스트에서 날짜별 초안 인덱스를 생성하는 도구
import fs from 'node:fs/promises';
import path from 'node:path';

const textJsonlPath = process.argv[2] || path.join('beyond_us', 'data', 'qt', 'extracted', 'page-text-full.jsonl');
const outDir = process.argv[3] || path.join('beyond_us', 'data', 'qt', 'extracted');

const WEEKDAY_KO = {
  SUNDAY: '주일',
  MONDAY: '월',
  TUESDAY: '화',
  WEDNESDAY: '수',
  THURSDAY: '목',
  FRIDAY: '금',
  SATURDAY: '토',
};

function csvEscape(value) {
  const text = String(value ?? '');
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function normalizeTitle(text) {
  return text
    .replace(/믿음에 행복을 더하는 큐티진/g, ' ')
    .replace(/_+\s*\d+\s*_+/g, ' ')
    .replace(/큰은혜QT/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .split(' ')
    .slice(-12)
    .join(' ');
}

function extractScriptureRef(rawText, marker) {
  const afterMarker = rawText.slice(marker.length).trim();
  const match = afterMarker.match(/^(.{1,60}?)\s+찬송가/);
  return match ? match[1].trim() : '';
}

const source = await fs.readFile(textJsonlPath, 'utf8');
const pages = source.trim().split(/\n/).filter(Boolean).map((line) => JSON.parse(line));
const entries = [];

for (const page of pages) {
  const text = page.text || '';
  const matches = [];
  const weekdayRegex = /\b(SUNDAY|MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY)\s+(\d{2})\s+(05|06)\b/g;
  const sermonRegex = /(2026)(05|06)(\d{2})\s*주일설교노트/g;

  for (const match of text.matchAll(weekdayRegex)) {
    const weekday = match[1];
    const day = match[2];
    const month = match[3];
    matches.push({
      index: match.index,
      date_key: `2026-${month}-${day}`,
      month,
      day,
      weekday_en: weekday,
      weekday_ko: WEEKDAY_KO[weekday] || '',
      marker: match[0],
      kind: 'qt',
    });
  }

  for (const match of text.matchAll(sermonRegex)) {
    const month = match[2];
    const day = match[3];
    matches.push({
      index: match.index,
      date_key: `2026-${month}-${day}`,
      month,
      day,
      weekday_en: 'SUNDAY',
      weekday_ko: WEEKDAY_KO.SUNDAY,
      marker: match[0],
      kind: 'sermon_note',
    });
  }

  matches.sort((a, b) => a.index - b.index);
  matches.forEach((match, idx) => {
    const next = matches[idx + 1];
    const prevText = text.slice(Math.max(0, match.index - 80), match.index);
    const bodyStart = match.index + match.marker.length;
    const bodyEnd = next ? next.index : text.length;
    const rawText = text.slice(match.index, bodyEnd).replace(/\s+/g, ' ').trim();
    entries.push({
      date_key: match.date_key,
      month: match.month,
      day: match.day,
      weekday_en: match.weekday_en,
      weekday_ko: match.weekday_ko,
      kind: match.kind,
      source_page: page.page,
      marker: match.marker,
      title_guess: normalizeTitle(prevText),
      scripture_ref_guess: extractScriptureRef(rawText, match.marker),
      raw_text: rawText,
    });
  });
}

entries.sort((a, b) => a.date_key.localeCompare(b.date_key) || a.source_page - b.source_page);
await fs.mkdir(outDir, { recursive: true });
await fs.writeFile(path.join(outDir, 'qt-date-index.json'), JSON.stringify(entries, null, 2), 'utf8');

const headers = ['date_key', 'weekday_ko', 'kind', 'source_page', 'title_guess', 'marker', 'raw_text'];
const csv = [
  headers.join(','),
  ...entries.map((entry) => headers.map((key) => csvEscape(entry[key])).join(',')),
].join('\n') + '\n';
await fs.writeFile(path.join(outDir, 'qt-date-index.csv'), csv, 'utf8');

const sheetHeaders = [
  'date_key',
  'title',
  'scripture_ref',
  'body',
  'is_open',
  'source_page',
  'source_page_pdf',
  'kind',
];
const sheetCsv = [
  sheetHeaders.join(','),
  ...entries.map((entry) => [
    entry.date_key,
    entry.title_guess,
    entry.scripture_ref_guess,
    entry.raw_text,
    'TRUE',
    entry.source_page,
    `qt-page-${String(entry.source_page).padStart(3, '0')}.pdf`,
    entry.kind,
  ].map(csvEscape).join(',')),
].join('\n') + '\n';
await fs.writeFile(path.join(outDir, 'qt-contents-sheet-draft.csv'), sheetCsv, 'utf8');

const missing = [];
for (const month of ['05', '06']) {
  const daysInMonth = month === '05' ? 31 : 30;
  for (let day = 1; day <= daysInMonth; day += 1) {
    const dateKey = `2026-${month}-${String(day).padStart(2, '0')}`;
    if (!entries.some((entry) => entry.date_key === dateKey)) missing.push(dateKey);
  }
}

console.log(JSON.stringify({
  totalEntries: entries.length,
  missing,
  outJson: path.join(outDir, 'qt-date-index.json'),
  outCsv: path.join(outDir, 'qt-date-index.csv'),
  outSheetCsv: path.join(outDir, 'qt-contents-sheet-draft.csv'),
  firstEntries: entries.slice(0, 8).map((entry) => ({
    date_key: entry.date_key,
    kind: entry.kind,
    source_page: entry.source_page,
    title_guess: entry.title_guess,
  })),
}, null, 2));
