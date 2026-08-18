import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(process.argv[2]));
for (const term of process.argv.slice(3)) {
  const result = await workbook.inspect({
    kind: 'match',
    searchTerm: term,
    options: { useRegex: false, maxResults: 20 },
    summary: `Buscar ${term}`,
    maxChars: 6000,
  });
  console.log(`BUSQUEDA: ${term}`);
  console.log(result.ndjson);
}
