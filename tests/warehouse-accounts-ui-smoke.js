const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
let dialog,calls=[],response={versionEmpresa:4,servidor:'SQL',baseDatos:'EMPRESA',configuracion:{version:0},cuentas:[{codigo:'1435',nombre:'Inventario <prueba>'}]};
function element(){return {disabled:false,events:{},classList:{add(){},remove(){}},addEventListener(n,f){this.events[n]=f;},remove(){this.removed=true;}};}
const context=vm.createContext({state:{erpSession:{company:{id:3,name:'Empresa'}}},zeusUI:{epoch:0},zeusEscape:v=>String(v??'').replaceAll('<','&lt;'),showMasterNotice(){},
  apiRequest:async(url,options)=>{calls.push({url,options});return response;},document:{body:{append(){}},createElement(tag){const e=element();if(tag==='dialog'){
    dialog=e;e.parts={'[data-close]':element(),'form':element(),'[type="submit"]':element(),'[role="status"]':element()};e.querySelector=k=>e.parts[k];e.showModal=()=>{};e.close=()=>e.remove();
  }return e;}}});
vm.runInContext(fs.readFileSync('public/warehouse-accounts.js','utf8'),context);
const fields=['inventario','ivaCompras','ivaVentas','ivaDevolucionVentas','ingreso','costoVenta','devolucionVenta'];
const form={reportValidity:()=>true,elements:Object.fromEntries(fields.map(k=>[k,{value:'1435'}]))};
const submit=()=>dialog.parts.form.events.submit({preventDefault(){},currentTarget:form});
(async()=>{
 const button=context.warehouseAccountsButton({id:7,code:'01',name:'Principal'});await button.events.click();
 assert.equal(calls.length,1);assert.equal(calls[0].options,undefined);assert.match(calls[0].url,/companies\/3\/zeus\/warehouses\/7\/accounts$/);
 for(const key of fields)assert.ok(dialog.innerHTML.includes(`name="${key}"`));
 assert.match(dialog.innerHTML,/Inventario &lt;prueba>/);assert.match(dialog.innerHTML,/EMPRESA/);
 form.elements.inventario.value='999';await submit();assert.equal(calls.length,1,'Rechaza cuentas fuera del catálogo');
 form.elements.inventario.value='1435';await submit();assert.equal(calls[1].options.method,'PUT');
 const payload=JSON.parse(calls[1].options.body);assert.equal(payload.versionEmpresa,4);assert.equal(payload.version,0);assert.equal(Object.keys(payload.cuentas).length,7);
 await submit();assert.equal(calls.length,2,'No guarda dos veces con la misma versión');
 await button.events.click();context.state.erpSession.company.id=24;const before=calls.length;await submit();assert.equal(calls.length,before,'No guarda si cambia la empresa');
 context.state.erpSession.company.id=3;response.configuracion={version:2,servidor:'OTRO',baseDatos:'OTRA',cuentas:{inventario:'1435'}};
 await button.events.click();assert.match(dialog.innerHTML,/Cambió el destino/);assert.doesNotMatch(dialog.innerHTML,/value="1435"[^>]*><\/label>/,'Destino distinto no preselecciona cuentas');
 console.log('Bodegas UI: siete cuentas, consulta sin escritura, validación, versión, aislamiento y cambio de destino correctos.');
})().catch(e=>{console.error(e);process.exitCode=1;});
