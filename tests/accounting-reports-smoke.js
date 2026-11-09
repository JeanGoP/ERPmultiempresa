const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {DOMParser}=require('@xmldom/xmldom');

const source=fs.readFileSync('public/accounting-reports.js','utf8')
  .replace('  window.resetAccountingReports=','  window.__testWorkbook=workbook;window.__testTotals=totalsFor;\n  window.resetAccountingReports=');
const field=value=>({value,closest(){return {hidden:false}},addEventListener(){}});
const stub={addEventListener(){},elements:{tipo:field('balance'),desde:field(''),hasta:field(''),cuenta:field(''),tercero:field(''),centro:field('')},querySelector(){return null}};
const nodes=new Map([
  ['#accountingReportsModule',stub],['#accountingReportsNav',stub],['#accountingReportsForm',stub],
  ['#accountingReportTable',stub],['#accountingReportStatus',stub],['#accountingReportTitle',stub],
  ['#accountingReportCount',stub],['#accountingReportExcel',stub]
]);
const context={
  document:{querySelector(selector){return selector==='#companyName'?{textContent:'MOTOCENTRO SA'}:nodes.get(selector);}},
  window:{},state:{erpSession:{company:{id:3}}},paymentReportZip:files=>files,
  Intl,Date,URLSearchParams,setTimeout
};
vm.runInNewContext(source,context);
const files=context.window.__testWorkbook({titulo:'Balance & prueba',tipo:'balance',desde:'2026-01-01',hasta:'2026-11-09',
  columnas:['Cuenta','Nombre','Saldo'],filas:[['110505','Caja <principal>',1250.5],['2205','=NoFormula',-4]]});
assert.ok(files['xl/workbook.xml']);
const xml=files['xl/worksheets/sheet1.xml'];
for(const [path,body] of Object.entries(files)){
  if(!path.endsWith('.xml'))continue;
  const errors=[];new DOMParser({onError:(level,message)=>errors.push(level+':'+message)}).parseFromString(body,'application/xml');
  assert.deepEqual(errors,[],path);
}
assert.match(xml,/Caja &lt;principal&gt;/);
assert.match(xml,/<c r="C5" s="2"><v>1250\.5<\/v><\/c>/);
assert.match(xml,/<c r="B6" t="inlineStr" s="0"><is><t xml:space="preserve">=NoFormula<\/t>/);
assert.match(xml,/<autoFilter ref="A4:C6"\/>/);
assert.match(xml,/SUBTOTALES/);
assert.match(xml,/TOTAL/);
const balance=context.window.__testTotals({tipo:'balance',columnas:['Cuenta','Debitos','Creditos','Saldo final'],filas:[['1105',100,0,100],['2205',0,100,-100]]});
assert.equal(balance.groupRows.length,2);
assert.equal(balance.grand.Debitos,100);
assert.equal(balance.grand.Creditos,100);
assert.equal(balance.grand['Saldo final'],0);
const currencies=context.window.__testTotals({tipo:'cxp',columnas:['Factura','Moneda','Valor original','Saldo actual'],filas:[['A','COP',100,50],['B','USD',20,10]]});
assert.equal(currencies.mixedCurrency,true);
assert.equal(currencies.grand,null);
assert.deepEqual(Array.from(currencies.groupRows,x=>x.values['Saldo actual']),[50,10]);
const inventory=context.window.__testTotals({tipo:'inventario',columnas:['BodegaId','Existencia','ValorHistorico','CostoPromedioHistorico'],filas:[[1,3,100,33.33],[1,2,80,40]]});
assert.equal(inventory.grand.ValorHistorico,180);
assert.equal(inventory.grand.Existencia,undefined);
const incomeStatement=context.window.__testWorkbook({titulo:'Resultados',tipo:'resultados',desde:'2026-01-01',hasta:'2026-11-09',
  columnas:['Cuenta','Nombre','Saldo final'],filas:[['4135','Ventas',-1000],['5105','Gastos',250]]});
assert.match(incomeStatement['xl/worksheets/sheet1.xml'],/RESULTADO DEL PERÍODO/);
assert.match(incomeStatement['xl/worksheets/sheet1.xml'],/<v>750<\/v>/);
assert.throws(()=>context.window.__testWorkbook({filas:[],truncado:false}));
console.log('Accounting reports Excel smoke passed');
