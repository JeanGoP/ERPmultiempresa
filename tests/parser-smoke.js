const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const { DOMParser, Node } = require('@xmldom/xmldom');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'public', 'app.js'), 'utf8');
const indexSource = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
for (const fragment of ['DOMParser', 'CDATA_SECTION_NODE', 'findEmbeddedBusinessDocument', 'extractInvoiceData', 'collectPartyXmlFields', 'supplierApiPayload', 'persistAnalyzedSupplier', 'master-data/suppliers/from-xml', 'confirmado en SQL Server', 'pendingApiMasterData', 'AllowanceCharge', 'ChargeIndicator', 'MultiplierFactorNumeric', 'Subtotal bruto', 'Descuento %', 'AdditionalItemProperty', 'normalizePropertyName', 'informacionmoto', 'inferColorFromDescription', 'inferModelYearFromVin', 'Modelo (año)', 'WithholdingTaxTotal', 'retentionTaxCodes', 'Retenciones', 'Seriales de motos', "'Motor', 'Chasis', 'VIN'", 'retencion:item.retention', 'vin:serial.vin', 'paymentCondition', 'creditDays', 'externalProductCode', 'crearArticulosFaltantes', 'findDetailGroups', 'elementToJson', 'decodeXmlBuffer', 'TextDecoder', 'exportCsv', 'exportExcel', 'inferLineClassification', 'buildInvoiceClassificationTable', 'buildHomologationPanel', 'getCompanyMasterData', 'saveMasterRecord', 'masterEditingSupplierId', 'purchaseFactor', 'addManualLine', 'saveManualDraft', 'nexo.purchaseDrafts', 'nexo.erpSession.v1', 'initializeErpUi', 'selectCompany', 'runtimeMode', 'textContent']) {
  if (!appSource.includes(fragment)) throw new Error(`Falta la función requerida: ${fragment}`);
}
assert.match(appSource, /function\s+showSuccess\s*\(/, 'Debe existir la confirmación visual de operaciones exitosas.');
assert.doesNotMatch(appSource, /forEach\s*\(\s*document\s*=>/, 'Una variable local no puede ocultar el document del navegador.');
assert.doesNotMatch(appSource, /const\s+document\s*=\s*detail\.documento/, 'El detalle no puede ocultar el document del navegador.');
assert.doesNotMatch(appSource, /function\s+savedPurchaseEffectiveState\s*\(\s*document\s*\)/, 'La bandeja no debe usar document como nombre de un registro.');
new vm.Script(appSource);
for (const id of ['accountsPayableNav', 'accountsPayableModule', 'accountsPayableSupplier', 'accountsPayableState', 'accountsPayableFrom', 'accountsPayableTo', 'accountsPayableTable']) {
  assert(indexSource.includes(`id="${id}"`), `Falta el control visual de cartera: ${id}`);
}
for (const fragment of ['showAccountsPayable', 'refreshAccountsPayable', '/accounts-payable?', 'renderPayableDashboard']) {
  assert(appSource.includes(fragment), `Falta la integración visual de cartera: ${fragment}`);
}

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
 <cac:PaymentMeans><cbc:ID>2</cbc:ID><cbc:PaymentDueDate>2026-09-19</cbc:PaymentDueDate></cac:PaymentMeans>
 <cac:WithholdingTaxTotal><cbc:TaxAmount currencyID="COP">125.00</cbc:TaxAmount><cac:TaxSubtotal><cbc:TaxableAmount currencyID="COP">10000.00</cbc:TaxableAmount><cbc:TaxAmount currencyID="COP">125.00</cbc:TaxAmount><cac:TaxCategory><cbc:Percent>1.25</cbc:Percent><cac:TaxScheme><cbc:ID>06</cbc:ID><cbc:Name>ReteRenta</cbc:Name></cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal></cac:WithholdingTaxTotal>
 <cac:LegalMonetaryTotal><cbc:LineExtensionAmount currencyID="COP">10000.00</cbc:LineExtensionAmount><cbc:TaxExclusiveAmount currencyID="COP">10000.00</cbc:TaxExclusiveAmount><cbc:TaxInclusiveAmount currencyID="COP">11900.00</cbc:TaxInclusiveAmount><cbc:PayableAmount currencyID="COP">11775.00</cbc:PayableAmount></cac:LegalMonetaryTotal>
 <cac:InvoiceLine><cbc:ID>1</cbc:ID><cbc:InvoicedQuantity unitCode="94">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="COP">3000.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Moto combinada NEGRO MATE CALCOMANIA AZUL 2027</cbc:Description><cac:AdditionalItemProperty><cbc:Name>Chasis / Motor (Chassis / Engine)</cbc:Name><cbc:Value>9FLTESTCHASIS01/MOTORTEST01</cbc:Value></cac:AdditionalItemProperty></cac:Item><cac:Price><cbc:PriceAmount currencyID="COP">3000.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
 <cac:InvoiceLine><cbc:ID>2</cbc:ID><cbc:InvoicedQuantity unitCode="94">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="COP">3000.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Moto separada GRIS GRAFITO</cbc:Description><cac:AdditionalItemProperty><cbc:Name>Chasis</cbc:Name><cbc:Value>9FLTESTCHASIS02</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>Motor</cbc:Name><cbc:Value>MOTORTEST02</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>Color</cbc:Name><cbc:Value>NEGRO</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>Año Modelo</cbc:Name><cbc:Value>2028</cbc:Value></cac:AdditionalItemProperty></cac:Item><cac:Price><cbc:PriceAmount currencyID="COP">3000.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
 <cac:InvoiceLine><cbc:ID>3</cbc:ID><cbc:InvoicedQuantity unitCode="94">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="COP">4000.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Moto VIN</cbc:Description><cac:AdditionalItemProperty><cbc:Name>VIN</cbc:Name><cbc:Value>VINTEST00000000003</cbc:Value></cac:AdditionalItemProperty><cac:AdditionalItemProperty><cbc:Name>NumeroMotor</cbc:Name><cbc:Value>MOTORTEST03</cbc:Value></cac:AdditionalItemProperty></cac:Item><cac:Price><cbc:PriceAmount currencyID="COP">4000.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
</Invoice>`;

const variants = parserContext.parseInvoiceForTest(variantsFixture);
assert.strictEqual(variants.items.length, 3);
assert.deepStrictEqual(Array.from(variants.items[0].serials, (serial) => [serial.chassis, serial.motor]), [['9FLTESTCHASIS01', 'MOTORTEST01']]);
assert.deepStrictEqual(Array.from(variants.items[1].serials, (serial) => [serial.chassis, serial.motor, serial.color]), [['9FLTESTCHASIS02', 'MOTORTEST02', 'NEGRO']]);
assert.deepStrictEqual(Array.from(variants.items[2].serials, (serial) => [serial.vin, serial.motor]), [['VINTEST00000000003', 'MOTORTEST03']]);
assert.strictEqual(variants.items[0].serials[0].color, 'NEGRO MATE / CALCOMANÍA AZUL');
assert.strictEqual(variants.items[0].serials[0].model, '2027');
assert.strictEqual(variants.items[1].serials[0].model, '2028');
assert.strictEqual(variants.retentions.length, 1);
assert.strictEqual(variants.retentions[0].amount, 125);
assert.strictEqual(variants.items.reduce((total, item) => total + item.retention, 0), 125);
assert.strictEqual(variants.paymentCondition, 'CREDITO');
assert.strictEqual(variants.creditDays, 30);
assert.strictEqual(variants.dueDate, '2026-09-19');

const supplierFixture = `<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
 <cbc:ID>SUP-1</cbc:ID><cbc:IssueDate>2026-08-20</cbc:IssueDate><cbc:DocumentCurrencyCode>COP</cbc:DocumentCurrencyCode>
 <cac:AccountingSupplierParty><cac:Party><cbc:WebsiteURI>https://proveedor.example</cbc:WebsiteURI><cac:PartyName><cbc:Name>Proveedor Comercial</cbc:Name></cac:PartyName><cac:PartyTaxScheme><cbc:RegistrationName>Proveedor Completo SAS</cbc:RegistrationName><cbc:CompanyID schemeID="7" schemeName="31">900123456</cbc:CompanyID><cbc:TaxLevelCode>O-13;O-15</cbc:TaxLevelCode><cac:TaxScheme><cbc:ID>01</cbc:ID><cbc:Name>IVA</cbc:Name></cac:TaxScheme></cac:PartyTaxScheme><cac:PartyLegalEntity><cbc:RegistrationName>Proveedor Completo SAS</cbc:RegistrationName><cac:RegistrationAddress><cbc:ID>11001</cbc:ID><cbc:CityName>Bogotá</cbc:CityName><cbc:PostalZone>110111</cbc:PostalZone><cbc:CountrySubentity>Bogotá D.C.</cbc:CountrySubentity><cbc:CountrySubentityCode>11</cbc:CountrySubentityCode><cac:AddressLine><cbc:Line>Carrera 10 # 20-30</cbc:Line></cac:AddressLine><cac:Country><cbc:IdentificationCode>CO</cbc:IdentificationCode><cbc:Name>Colombia</cbc:Name></cac:Country></cac:RegistrationAddress></cac:PartyLegalEntity><cac:Contact><cbc:Name>Ana Compras</cbc:Name><cbc:Telephone>6015551234</cbc:Telephone><cbc:ElectronicMail>facturas@proveedor.example</cbc:ElectronicMail></cac:Contact></cac:Party></cac:AccountingSupplierParty>
 <cac:LegalMonetaryTotal><cbc:PayableAmount currencyID="COP">100</cbc:PayableAmount></cac:LegalMonetaryTotal>
</Invoice>`;
const supplierInvoice=parserContext.parseInvoiceForTest(supplierFixture);
assert.strictEqual(supplierInvoice.supplier.identification,'900123456');
assert.strictEqual(supplierInvoice.supplier.identificationType,'NIT');
assert.strictEqual(supplierInvoice.supplier.verificationDigit,'7');
assert.strictEqual(supplierInvoice.supplier.name,'Proveedor Completo SAS');
assert.strictEqual(supplierInvoice.supplier.commercialName,'Proveedor Comercial');
assert.strictEqual(supplierInvoice.supplier.address,'Carrera 10 # 20-30');
assert.strictEqual(supplierInvoice.supplier.city,'Bogotá');
assert.strictEqual(supplierInvoice.supplier.department,'Bogotá D.C.');
assert.strictEqual(supplierInvoice.supplier.country,'Colombia');
assert.strictEqual(supplierInvoice.supplier.phone,'6015551234');
assert.strictEqual(supplierInvoice.supplier.email,'facturas@proveedor.example');
assert(Object.keys(supplierInvoice.supplier.xmlFields).some((key)=>key.endsWith('CompanyID')),'Debe conservar los campos originales del proveedor.');

const realSamplesDir = path.join(__dirname, '..', 'tmp', 'xml-samples');
if (fs.existsSync(realSamplesDir)) {
  const expected = {
    'ad08914101370072600107716.xml': { serials: 5, motor: '157FMJ-3AAHR036247', chassis: 'LC6JCK4PXV0017728', color: 'NEGRO', model: '2027' },
    'ad089090031702126E670173433.xml': { serials: 1, motor: 'BG7AV22D7955', chassis: '9FLT11259VEH28114', color: 'NEGRO MATE / GRIS CARBONO / CALCOMANÍA DORADA', model: '2027' },
    'ad089090031702126F660064021.xml': { serials: 5, motor: '1P53FMIHT1195160', chassis: '9FLXCJTC2VHH08181', color: 'NEGRO NEBULOSA / CALCOMANÍA NEGRA', model: '2027' },
    'ad089090031702126E670172906.xml': { serials: 4, motor: 'RF5AV10A8568', chassis: '9FLT81006VDG66549', color: 'NEGRO NEBULOSA / CALCOMANÍA AZUL ASPAS', model: '2027' },
    'ad0901398813004265d0f80ce.xml': { serials: 1, motor: 'DYXWTA02525', vin: '9GJA76DY3VP033179', model: '2027' },
    'ad090143949300426df34dad4.xml': { serials: 1, motor: 'AZXWTA18308' },
  };
  for (const [fileName, expectation] of Object.entries(expected)) {
    const invoice = parserContext.parseInvoiceForTest(fs.readFileSync(path.join(realSamplesDir, fileName), 'utf8'));
    const serials = invoice.items.flatMap((item) => Array.from(item.serials));
    assert.strictEqual(serials.length, expectation.serials, `${fileName}: cantidad de motos`);
    assert(serials.some((serial) => serial.motor === expectation.motor), `${fileName}: motor ${expectation.motor}`);
    if (expectation.chassis) assert(serials.some((serial) => serial.chassis === expectation.chassis), `${fileName}: chasis ${expectation.chassis}`);
    if (expectation.vin) assert(serials.some((serial) => serial.vin === expectation.vin), `${fileName}: VIN ${expectation.vin}`);
    if (expectation.color) assert(serials.some((serial) => serial.color === expectation.color), `${fileName}: color ${expectation.color}`);
    if (expectation.model) assert(serials.some((serial) => serial.model === expectation.model), `${fileName}: modelo ${expectation.model}`);
  }
}

console.log('Pruebas correctas: extrae motor, chasis, VIN, colores, año modelo e impuestos retenidos.');
