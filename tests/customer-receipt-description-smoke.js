const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const source=fs.readFileSync(path.join(__dirname,'../public/customer-documents.js'),'utf8');
const helpers=source.slice(source.indexOf('  const productItems='),source.indexOf('  const portfolioOptions='));
const receipt=source.slice(source.indexOf('  function syncReceiptConcept()'),source.indexOf('  function renderAllocations()'));
assert.ok(helpers.startsWith('  const productItems='));
assert.ok(receipt.startsWith('  function syncReceiptConcept()'));

const form={elements:{concepto:{value:''},tipo:{value:'CARTERA'}}};
const moto={id:7,numero:'FV-7',cuotaId:101,numeroCuota:1,tipoCuota:'ORDINARIA',vence:'2026-11-03',saldo:500000,
  claseCartera:'MOTO',articulos:[{nombre:'MOTOCICLETA PRUEBA',cantidad:1,unidades:[{chasis:'CH-123',vin:'VIN-789'}]}]};
const next={...moto,cuotaId:102,numeroCuota:2,tipoCuota:'EXTRA',vence:'2026-12-03'};
const context={mode:'receipt',automaticReceiptConcept:'',applications:[{facturaVentaId:7,facturaVentaCuotaId:101,valor:500000}],
  options:{facturas:[moto,next]},$:()=>form,esc:value=>String(value??''),money:value=>String(value),portfolioLabel:value=>value};
vm.createContext(context);
vm.runInContext(helpers+receipt,context);
context.syncReceiptConcept();
assert.match(form.elements.concepto.value,/cuota 1 \(2026-11-03\) factura FV-7/);
assert.match(form.elements.concepto.value,/MOTOCICLETA PRUEBA.*Chasis CH-123/);
assert.ok(form.elements.concepto.value.length<=300);
const motoRow=context.receiptDueRow(moto,0,()=>null,new Set(['7:101']));
assert.match(motoRow,/Chasis CH-123 · VIN VIN-789/);
assert.match(motoRow,/Ver productos \(1\)/);
assert.match(motoRow,/data-product-list="0" hidden/);

context.applications.push({facturaVentaId:7,facturaVentaCuotaId:102,valor:500000});
context.syncReceiptConcept();
assert.match(form.elements.concepto.value,/cuota 1.*cuota extra 2/s);
assert.match(form.elements.concepto.value,/2026-12-03/);
form.elements.concepto.value='Descripción pactada con el cliente';
context.syncReceiptConcept();
assert.equal(form.elements.concepto.value,'Descripción pactada con el cliente');

const electro={id:8,numero:'FV-8',cuotaId:201,numeroCuota:1,tipoCuota:'ORDINARIA',vence:'2026-11-20',saldo:800000,
  claseCartera:'OTROS',articulos:[{nombre:'Nevera',cantidad:1,unidades:[]},{nombre:'Lavadora',cantidad:1,unidades:[]}]};
const electroRow=context.receiptDueRow(electro,1,()=>null,new Set(['8:201']));
assert.match(electroRow,/Ver productos \(2\)/);
assert.match(electroRow,/Nevera/);
assert.match(electroRow,/Lavadora/);
console.log('Recibos de caja: cuota, artículos, chasis/VIN y detalle desplegable correctos.');
