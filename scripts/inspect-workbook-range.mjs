import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(process.argv[2]));
const result = await workbook.inspect({
  kind: 'table',
  sheetId: process.argv[3],
  range: process.argv[4],
  include: 'values,formulas',
  tableMaxRows: 200,
  tableMaxCols: 10,
  tableMaxCellChars: 2000,
  maxChars: 30000,
});
console.log(result.ndjson);
