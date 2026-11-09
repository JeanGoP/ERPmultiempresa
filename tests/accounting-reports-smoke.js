const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {DOMParser}=require('@xmldom/xmldom');

const source=fs.readFileSync('public/accounting-reports.js','utf8')
  .replace('  window.resetAccountingReports=','  window.__testWorkbook=workbook;\n  window.resetAccountingReports=');
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
assert.throws(()=>context.window.__testWorkbook({filas:[],truncado:false}));
console.log('Accounting reports Excel smoke passed');
