const fs=require('node:fs');const vm=require('node:vm');const assert=require('node:assert/strict');
const app=fs.readFileSync('public/app.js','utf8'),zeus=fs.readFileSync('public/zeus.js','utf8');
const source=app.slice(app.indexOf('let receiptZeusNoticeVersion='),app.indexOf('function renderCompanyOptions('));
let notice;const timers=[];const state={erpSession:{company:{id:3}}};
const sandbox={state,document:{querySelector:()=>notice,createElement:()=>({dataset:{},setAttribute(){}})},elements:{errorBox:{after:n=>notice=n}},setTimeout:fn=>timers.push(fn),apiRequest:async()=>({estado:'CONTABILIZADO',mensaje:'Zeus contabilizado: 1200000001'})};
vm.createContext(sandbox);vm.runInContext(source,sandbox);
(async()=>{
 sandbox.receiptZeusNotice('/api/v1/companies/3/receipts/34/post',{estado:'PENDIENTE',mensaje:'ERP contabilizado; Zeus pendiente'});
 assert.match(notice.textContent,/pendiente/);await timers.shift()();assert.equal(notice.dataset.estado,'CONTABILIZADO');
 sandbox.receiptZeusNotice('/api/v1/companies/3/receipts/34/post',{estado:'PENDIENTE',mensaje:'Anterior'});
 sandbox.receiptZeusNotice('/api/v1/companies/3/receipts/35/post',{estado:'REQUIERE_REVISION',mensaje:'Falta cuenta IVA'});
 await timers.shift()();assert.equal(notice.textContent,'Falta cuenta IVA');assert.equal(notice.hidden,false);
 sandbox.receiptZeusNotice('/api/v1/companies/3/receipts/36/post',{estado:'PENDIENTE',mensaje:'Otra entrada'});state.erpSession.company.id=4;await timers.shift()();assert.equal(notice.hidden,true);
 const prepare=zeus.slice(zeus.indexOf('function zeusPrepare('),zeus.indexOf('function zeusTaxesPayload('));assert.ok(!prepare.includes('zeusPreviewForm'));assert.ok(prepare.includes('datos guardados'));
 assert.ok(app.includes('payload?.zeus) receiptZeusNotice'));assert.ok(zeus.includes('/send-automatic'));
 console.log('Zeus automático UI: sin recaptura de impuestos, estado pendiente/confirmado, aislamiento y respuestas obsoletas correctos.');
})().catch(e=>{console.error(e);process.exitCode=1;});
