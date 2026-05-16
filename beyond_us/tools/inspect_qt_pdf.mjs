// Q.T. 원본 PDF의 페이지 수와 텍스트 추출 상태를 확인하는 도구
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const pdfPath = process.argv[2];
const outDir = process.argv[3] || path.join('beyond_us', 'data', 'qt', 'extracted');

if (!pdfPath) {
  console.error('Usage: node inspect_qt_pdf.mjs <pdfPath> [outDir]');
  process.exit(1);
}

const pdfjsPath = pathToFileURL(path.resolve('.codex-pdf-tools/node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href;
const pdfWorkerPath = pathToFileURL(path.resolve('.codex-pdf-tools/node_modules/pdfjs-dist/legacy/build/pdf.worker.mjs')).href;
const pdfjs = await import(pdfjsPath);
pdfjs.GlobalWorkerOptions.workerSrc = pdfWorkerPath;

const data = new Uint8Array(await fs.readFile(pdfPath));
const doc = await pdfjs.getDocument({ data, disableWorker: true }).promise;
await fs.mkdir(outDir, { recursive: true });

const pages = [];
for (let pageNo = 1; pageNo <= doc.numPages; pageNo += 1) {
  const page = await doc.getPage(pageNo);
  const content = await page.getTextContent();
  const text = content.items
    .map((item) => ('str' in item ? item.str : ''))
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
  pages.push({ page: pageNo, text });
}

const result = {
  source: pdfPath,
  pageCount: doc.numPages,
  pages: pages.map((page) => ({
    page: page.page,
    textLength: page.text.length,
    preview: page.text.slice(0, 240),
  })),
};

await fs.writeFile(path.join(outDir, 'page-text-preview.json'), JSON.stringify(result, null, 2), 'utf8');
await fs.writeFile(
  path.join(outDir, 'page-text-full.jsonl'),
  pages.map((page) => JSON.stringify(page)).join('\n') + '\n',
  'utf8',
);
console.log(JSON.stringify({
  pageCount: doc.numPages,
  previewPath: path.join(outDir, 'page-text-preview.json'),
  fullTextPath: path.join(outDir, 'page-text-full.jsonl'),
  firstPages: result.pages.slice(0, 5),
}, null, 2));
