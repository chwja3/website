// Q.T. 원본 PDF를 페이지별 PDF 파일로 분리하는 도구
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const pdfPath = process.argv[2];
const outDir = process.argv[3] || path.join('beyond_us', 'data', 'qt', 'pages');

if (!pdfPath) {
  console.error('Usage: node split_qt_pdf_pages.mjs <pdfPath> [outDir]');
  process.exit(1);
}

const require = createRequire(import.meta.url);
const { PDFDocument } = require(path.resolve('.codex-pdf-tools/node_modules/pdf-lib'));

const sourceBytes = await fs.readFile(pdfPath);
const sourcePdf = await PDFDocument.load(sourceBytes);
await fs.mkdir(outDir, { recursive: true });

for (let i = 0; i < sourcePdf.getPageCount(); i += 1) {
  const outPdf = await PDFDocument.create();
  const [page] = await outPdf.copyPages(sourcePdf, [i]);
  outPdf.addPage(page);
  const bytes = await outPdf.save();
  const fileName = `qt-page-${String(i + 1).padStart(3, '0')}.pdf`;
  await fs.writeFile(path.join(outDir, fileName), bytes);
}

console.log(JSON.stringify({
  source: pdfPath,
  pageCount: sourcePdf.getPageCount(),
  outDir,
}, null, 2));
