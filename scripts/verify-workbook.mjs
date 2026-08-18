import fs from 'node:fs/promises';
import path from 'node:path';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const [inputPath, previewDir] = process.argv.slice(2);
if (!inputPath || !previewDir) throw new Error('Uso: node verify-workbook.mjs <archivo.xlsx> <directorio-preview>');

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
await fs.mkdir(previewDir, { recursive: true });
const sheets = workbook.worksheets.items;

for (let index = 0; index < sheets.length; index += 1) {
  const sheet = sheets[index];
  const range = sheet.name === 'Resumen' ? 'A1:D8' : 'A1:N12';
  const inspection = await workbook.inspect({ kind: 'table', sheetId: sheet.name, range, include: 'values,formulas', tableMaxRows: 6, tableMaxCols: 14, maxChars: 2500 });
  console.log(`HOJA ${index + 1}: ${sheet.name}`);
  console.log(inspection.ndjson);
  const preview = await workbook.render({ sheetName: sheet.name, range, scale: 1, format: 'png' });
  await fs.writeFile(path.join(previewDir, `${String(index + 1).padStart(2, '0')}-${sheet.name.replace(/[^a-z0-9]+/gi, '-')}.png`), new Uint8Array(await preview.arrayBuffer()));
}

const errors = await workbook.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A', options: { useRegex: true, maxResults: 300 }, summary: 'final formula error scan' });
console.log('ERRORES');
console.log(errors.ndjson);
