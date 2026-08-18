const fs = require('fs');
const path = require('path');
const vm = require('vm');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'public', 'app.js'), 'utf8');
for (const fragment of ['DOMParser', 'CDATA_SECTION_NODE', 'findEmbeddedBusinessDocument', 'extractInvoiceData', 'AllowanceCharge', 'ChargeIndicator', 'MultiplierFactorNumeric', 'Subtotal bruto', 'Descuento %', 'AdditionalItemProperty', 'normalizePropertyName', 'informacionmoto', 'Seriales de motos', 'Chasis / VIN', 'findDetailGroups', 'elementToJson', 'decodeXmlBuffer', 'TextDecoder', 'exportCsv', 'exportExcel', 'inferLineClassification', 'buildInvoiceClassificationTable', 'buildHomologationPanel', 'getCompanyMasterData', 'saveMasterRecord', 'purchaseFactor', 'addManualLine', 'saveManualDraft', 'nexo.purchaseDrafts', 'nexo.erpSession.v1', 'nexo.masterData.v1', 'initializeErpUi', 'selectCompany', 'runtimeMode', 'textContent']) {
  if (!appSource.includes(fragment)) throw new Error(`Falta la función requerida: ${fragment}`);
}
new vm.Script(appSource);
console.log('Smoke test correcto: el cliente compila y contiene el flujo completo de análisis.');
