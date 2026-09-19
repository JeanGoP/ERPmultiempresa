const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {DOMParser}=require('@xmldom/xmldom');
const source=fs.readFileSync('public/app.js','utf8');
const slice=(a,b)=>source.slice(source.indexOf(a),source.indexOf(b));
const state={purchaseWorkflow:null};
let errors=0,renders=0;
const context=vm.createContext({DOMParser,Node:{ELEMENT_NODE:1,TEXT_NODE:3,CDATA_SECTION_NODE:4},state,
  document:{createElement:()=>({value:'',setAttribute(){},addEventListener(event,fn){this[event]=fn;}})},
  renderInvoice:()=>renders++,showError:()=>errors++,
  mappedLine:()=>null,externalProductCode:item=>item.code,findById:()=>null,getCompanyMasterData:()=>({data:{articles:[]}}),documentTypeForApi:()=> 'FACTURA',
  elements:{xmlInput:{value:'<Invoice>original</Invoice>'}}
});
vm.runInContext(slice('function localName','function inferType')+slice('function updateXmlRetentionTotal(','function buildInvoiceClassificationTable(')+slice('function buildSupplierDocumentPayload(','async function refreshPurchaseWorkflow('),context);
const retention=(rate,amount,tag='WithholdingTaxTotal')=>`<${tag}><TaxAmount>${amount}</TaxAmount><TaxSubtotal><TaxableAmount>10000</TaxableAmount><TaxAmount>${amount}</TaxAmount><TaxCategory>${rate===null?'':`<Percent>${rate}</Percent>`}<TaxScheme><ID>06</ID><Name>ReteRenta</Name></TaxScheme></TaxCategory></TaxSubtotal></${tag}>`;
const parse=(root,line='')=>context.extractInvoiceData(new DOMParser().parseFromString(`<Invoice><ID>QA</ID>${root}<LegalMonetaryTotal><PayableAmount>10000</PayableAmount></LegalMonetaryTotal><InvoiceLine><ID>1</ID><InvoicedQuantity>1</InvoicedQuantity><LineExtensionAmount>10000</LineExtensionAmount>${line}<Item><Description>Servicio QA</Description></Item><Price><PriceAmount>10000</PriceAmount></Price></InvoiceLine></Invoice>`,'application/xml'));
for(const tag of ['TaxTotal','WithholdingTaxTotal']){
  const mixed=parse(retention(1.2,120,tag)+retention(2,200,tag));
  assert.equal(mixed.totals.retentions,320);assert.equal(mixed.items[0].retention,320);assert.equal(mixed.taxes.length,0);
  const lineOnly=parse('',retention(0.5,50,tag)+retention(2.5,250,tag));
  assert.equal(lineOnly.totals.retentions,300);assert.equal(lineOnly.items[0].retention,300);
  const duplicated=parse(retention(2,200,tag),retention(2,200,tag));assert.equal(duplicated.items[0].retention,200);
}
assert.equal(parse(retention(null,120)).totals.retentions,120);
for(const name of ['Autorretencion de Renta','AUTORRETENCIÓN','Auto-retención renta','Auto retención','Autorretefuente']){
  for(const rate of [null,1.2,2.5]){
    for(const tag of ['TaxTotal','WithholdingTaxTotal']){
      const self=retention(rate,120,tag).replace('ReteRenta',name);
      assert.equal(parse(self).totals.retentions,0);
      assert.equal(parse('',self).items[0].retention,0);
      const mixed=parse(self+retention(1.25,125,tag));assert.equal(mixed.totals.retentions,125);assert.equal(mixed.items[0].retention,125);
    }
  }
}
assert.equal(parse('<CustomField Name="AutorreteFuenteAmount" Value="120"/><CustomField Name="TotalRetenciones" Value="120"/>').totals.retentions,0);
assert.equal(parse('<CustomField Name="AutorreteFuenteAmount" Value="120"/><CustomField Name="ReteFuenteAmount" Value="125"/><CustomField Name="TotalRetenciones" Value="245"/>').totals.retentions,125);
assert.equal(parse('<WithholdingTaxTotal><TaxAmount>120</TaxAmount></WithholdingTaxTotal>').totals.retentions,120,'No inventar una tarifa sin base');
const invoice=parse(retention(2,200));
invoice.items.push({...invoice.items[0],line:'2',retention:0,lineTotal:3333.33});
context.updateXmlRetentionTotal(invoice,100.01);
assert.equal(Math.round(invoice.items.reduce((sum,x)=>sum+x.retention,0)*100),10001);
assert.equal(invoice.totals.retentions,100.01);assert.equal(invoice.retentions[0].amount,100.01);
assert.equal(invoice.totals.payable,10099.99);
const payload=context.buildSupplierDocumentPayload(invoice);
assert.equal(Math.round(payload.lineas.reduce((sum,x)=>sum+x.retencion,0)*100),10001);
assert.equal(payload.totalPagar,10099.99);assert.equal(payload.xmlOriginal,'<Invoice>original</Invoice>');
context.updateXmlRetentionTotal(invoice,0);assert.equal(invoice.totals.payable,10200);assert.ok(invoice.items.every(x=>x.retention===0));
const before=JSON.stringify(invoice);
for(const value of [-1,NaN,Infinity,999999])assert.throws(()=>context.updateXmlRetentionTotal(invoice,value));
assert.equal(JSON.stringify(invoice),before,'Validaciones no deben modificar valores');
const input=context.buildXmlRetentionInput(invoice);assert.equal(input.disabled,false);input.value='75';input.change();assert.equal(invoice.totals.retentions,75);assert.equal(renders,1);
input.value='';input.change();assert.equal(errors,1);assert.equal(invoice.totals.retentions,75);
state.purchaseWorkflow={documentId:1};assert.equal(context.buildXmlRetentionInput(invoice).disabled,true);input.value='50';input.change();assert.equal(invoice.totals.retentions,75);
assert.ok(!slice('function buildInvoiceClassificationTable(','function mappedLine(').includes('updateXmlRetentionTotal'),'No debe haber edición por línea');
console.log('QA retenciones: exclusión de autorretenciones, tarifas ordinarias sin mínimo, total editable, payload y bloqueo correctos.');
