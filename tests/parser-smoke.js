const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const { DOMParser, Node } = require('@xmldom/xmldom');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'public', 'app.js'), 'utf8');
for (const fragment of ['DOMParser', 'CDATA_SECTION_NODE', 'findEmbeddedBusinessDocument', 'extractInvoiceData', 'AllowanceCharge', 'ChargeIndicator', 'MultiplierFactorNumeric', 'Subtotal bruto', 'Descuento %', 'AdditionalItemProperty', 'normalizePropertyName', 'informacionmoto', 'WithholdingTaxTotal', 'retentionTaxCodes', 'Retenciones', 'Seriales de motos', "'Motor', 'Chasis', 'VIN'", 'retencion:item.retention', 'vin:serial.vin', 'findDetailGroups', 'elementToJson', 'decodeXmlBuffer', 'TextDecoder', 'exportCsv', 'exportExcel', 'inferLineClassification', 'buildInvoiceClassificationTable', 'buildHomologationPanel', 'getCompanyMasterData', 'saveMasterRecord', 'purchaseFactor', 'addManualLine', 'saveManualDraft', 'nexo.purchaseDrafts', 'nexo.erpSession.v1', 'nexo.masterData.v1', 'initializeErpUi', 'selectCompany', 'runtimeMode', 'textContent']) {
  if (!appSource.includes(fragment)) throw new Error(`Falta la función requerida: ${fragment}`);
}
new vm.Script(appSource);

const parserStart = appSource.indexOf('function localName');
const parserEnd = appSource.indexOf('function inferType');
assert(parserStart >= 0 && parserEnd > parserStart, 'No fue posible aislar el analizador XML para las pruebas.');
const parserContext = { DOMParser, Node };
vm.createContext(parserContext);
vm.runInContext(`${appSource.slice(parserStart, parserEnd)}
this.parseXml = (source) => new DOMParser().parseFromString(source, 'application/xml');
this.parseInvoiceForTest = (source) => {
  const container = this.parseXml(source);
  const embedded = findEmbeddedBusinessDocument(container);
  return extractInvoiceData(embedded || container);
};`, parserContext);

const variantsFixture = `<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
 xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
 xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
 <cbc:ID>PRUEBA-VARIANTES</cbc:ID><cbc:IssueDate>2026-08-20</cbc:IssueDate><cbc:DocumentCurrencyCode>COP</cbc:DocumentCurrencyCode>
 <cac:WithholdingTaxTotal><cbc:TaxAmount currencyID="COP">125.00</cbc:TaxAmount><cac:TaxSubtotal><cbc:TaxableAmount currencyID="COP">10000.00</cbc:TaxableAmount><cbc:TaxAmount currencyID="COP">125.00</cbc:TaxAmount><cac:TaxCategory><cbc:Percent>1.25</cbc:Percent><cac:TaxScheme><cbc:ID>06</cbc:ID><cbc:Name>ReteRenta</cbc:Name></cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal></cac:WithholdingTaxTotal>
 <cac:LegalMonetaryTotal><cbc:LineExtensionAmount currencyID="COP">10000.00</cbc:LineExtensionAmount><cbc:TaxExclusiveAmount currencyID="COP">10000.00</cbc:TaxExclusiveAmount><cbc:TaxInclusiveAmount currencyID="COP">11900.00</cbc:TaxInclusiveAmount><cbc:PayableAmount currencyID="COP">11775.00</cbc:PayableAmount></cac:LegalMonetaryTotal>
 <cac:InvoiceLine><cbc:ID>1</cbc:ID><cbc:InvoicedQuantity unitCode="94">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="COP">3000.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Moto combinada</cbc:Description><cac:AdditionalItemProperty><cbc:Name>Chasis / Motor (Chassis / Engine)</cbc:Name><cbc:Value>9FLTESTCHASIS01/MOTORTEST01</cbc:Value></cac:AdditionalItemProperty></cac:Item><cac:Price><cbc:PriceAmount currencyID="COP">3000.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
 <cac:InvoiceLine><cbc:ID>2</cbc:ID><cbc:InvoicedQuantity unitCode="94">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="COP">3000.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Moto separada</cbc:Description><cac:AdditionalItemProperty><cbc:Name>Chasis</cbc:Name><cbc:Value>9FLTESTCHASIS02</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>Motor</cbc:Name><cbc:Value>MOTORTEST02</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>Color</cbc:Name><cbc:Value>NEGRO</cbc:Value></cac:AdditionalItemProperty></cac:Item><cac:Price><cbc:PriceAmount currencyID="COP">3000.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
 <cac:InvoiceLine><cbc:ID>3</cbc:ID><cbc:InvoicedQuantity unitCode="94">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="COP">4000.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Moto VIN</cbc:Description><cac:AdditionalItemProperty><cbc:Name>VIN</cbc:Name><cbc:Value>VINTEST00000000003</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>NumeroMotor</cbc:Name><cbc:Value>MOTORTEST03</cbc:Value></cac:AdditionalItemProperty></cac:Item><cac:Price><cbc:PriceAmount currencyID="COP">4000.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
</Invoice>`;

const variants = parserContext.parseInvoiceForTest(variantsFixture);
assert.strictEqual(variants.items.length, 3);
assert.deepStrictEqual(Array.from(variants.items[0].serials, (serial) => [serial.chassis, serial.motor]), [['9FLTESTCHASIS01', 'MOTORTEST01']]);
assert.deepStrictEqual(Array.from(variants.items[1].serials, (serial) => [serial.chassis, serial.motor, serial.color]), [['9FLTESTCHASIS02', 'MOTORTEST02', 'NEGRO']]);
assert.deepStrictEqual(Array.from(variants.items[2].serials, (serial) => [serial.vin, serial.motor]), [['VINTEST00000000003', 'MOTORTEST03']]);
assert.strictEqual(variants.retentions.length, 1);
assert.strictEqual(variants.retentions[0].amount, 125);
assert.strictEqual(variants.items.reduce((total, item) => total + item.retention, 0), 125);

const realSamplesDir = path.join(__dirname, '..', 'tmp', 'xml-samples');
if (fs.existsSync(realSamplesDir)) {
  const expected = {
    'ad08914101370072600107716.xml': { serials: 5, motor: '157FMJ-3AAHR036247', chassis: 'LC6JCK4PXV0017728' },
    'ad089090031702126E670173433.xml': { serials: 1, motor: 'BG7AV22D7955', chassis: '9FLT11259VEH28114' },
    'ad089090031702126F660064021.xml': { serials: 5, motor: '1P53FMIHT1195160', chassis: '9FLXCJTC2VHH08181' },
    'ad089090031702126E670172906.xml': { serials: 4, motor: 'RF5AV10A8568', chassis: '9FLT81006VDG66549' },
    'ad0901398813004265d0f80ce.xml': { serials: 1, motor: 'DYXWTA02525', vin: '9GJA76DY3VP033179' },
    'ad090143949300426df34dad4.xml': { serials: 1, motor: 'AZXWTA18308' },
  };
  for (const [fileName, expectation] of Object.entries(expected)) {
    const invoice = parserContext.parseInvoiceForTest(fs.readFileSync(path.join(realSamplesDir, fileName), 'utf8'));
    const serials = invoice.items.flatMap((item) => Array.from(item.serials));
    assert.strictEqual(serials.length, expectation.serials, `${fileName}: cantidad de motos`);
    assert(serials.some((serial) => serial.motor === expectation.motor), `${fileName}: motor ${expectation.motor}`);
    if (expectation.chassis) assert(serials.some((serial) => serial.chassis === expectation.chassis), `${fileName}: chasis ${expectation.chassis}`);
    if (expectation.vin) assert(serials.some((serial) => serial.vin === expectation.vin), `${fileName}: VIN ${expectation.vin}`);
  }
}

console.log('Pruebas correctas: compila y extrae variantes de motor, chasis, VIN e impuestos retenidos.');
