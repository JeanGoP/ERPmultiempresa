const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('public/zeus.js','utf8');
const calls=[];let dialog,preview={huella:'H',nombre:'Proveedor <prueba>',codigo:'802019690',baseDatos:'PRUEBAS',divisionPolitica:'5708001',tipoPersona:'J',terceroExiste:false,proveedorExiste:false,zona:'GN',segmento:'OTROS',categoriaFiscal:'OTROS'};
let result={estado:'CREADO',mensaje:'Confirmado en Zeus'};
function element(){return {disabled:false,events:{},classList:{toggle(){},add(){}},addEventListener(name,fn){this.events[name]=fn;},remove(){this.removed=true;}};}
const context=vm.createContext({state:{erpSession:{company:{id:3}}},
  zeusEscape:value=>String(value??'').replaceAll('<','&lt;').replaceAll('>','&gt;'),showMasterNotice:()=>{},
  FormData:class{*[Symbol.iterator](){}},
  apiRequest:async(url,options)=>{calls.push({url,options});return options?result:preview;},
  document:{body:{append(){}},createElement(tag){const el=element();if(tag==='dialog'){
    dialog=el;el.parts={'[data-close]':element(),'form':element(),'[type="submit"]':element(),'[role="status"]':element()};el.querySelector=key=>el.parts[key];el.showModal=()=>{el.open=true;};el.close=()=>{el.open=false;el.events.close();};
  }return el;}}
});
vm.runInContext(source.slice(source.indexOf('function zeusSupplierSyncText'),source.indexOf('const zeusConcepts')),context);
(async()=>{
  assert.match(context.zeusSupplierSyncText({zeusEstado:'PENDIENTE',zeusMensaje:'Cuenta no configurada'}),/Pendiente de envío.*Cuenta no configurada/);
  assert.match(context.zeusSupplierSyncText({zeusEstado:'INCIERTO'}),/Requiere verificar/);
  assert.match(context.zeusSupplierSyncText({zeusEstado:'EN_COLA'}),/En cola/);
  assert.match(context.zeusSupplierSyncText({zeusEstado:'CREADO'}),/Creado en Zeus/);
  const button=context.zeusSupplierSendButton({id:21,active:true});await button.events.click();
  assert.equal(calls.length,1);assert.match(calls[0].url,/companies\/3\/zeus\/suppliers\/21\/preview$/);
  assert.equal(calls[0].options,undefined,'Abrir consulta no crea registros');
  assert.doesNotMatch(dialog.innerHTML,/<select/,'No solicita zona, segmento ni categoría');
  assert.match(dialog.innerHTML,/GN/);assert.match(dialog.innerHTML,/OTROS/);
  assert.match(dialog.innerHTML,/Proveedor &lt;prueba&gt;/);assert.match(dialog.innerHTML,/PRUEBAS/);assert.ok(dialog.open);
  await dialog.parts.form.events.submit({preventDefault(){},currentTarget:{}});
  assert.equal(calls[1].options.method,'POST');assert.match(calls[1].url,/\/send$/);
  assert.deepEqual(JSON.parse(calls[1].options.body),{huella:'H'});
  assert.match(dialog.parts['[role="status"]'].textContent,/CREADO/);assert.ok(dialog.parts['[type="submit"]'].disabled);
  await dialog.parts.form.events.submit({preventDefault(){},currentTarget:{}});assert.equal(calls.length,2,'No repite tras éxito');
  await button.events.click();context.state.erpSession.company.id=24;
  const before=calls.length;await dialog.parts.form.events.submit({preventDefault(){},currentTarget:{}});assert.equal(calls.length,before,'Cambio de empresa impide enviar');
  context.state.erpSession.company.id=3;result={estado:'INCIERTO',mensaje:'Consultar antes de repetir'};
  await button.events.click();await dialog.parts.form.events.submit({preventDefault(){},currentTarget:{}});
  assert.ok(dialog.parts['[type="submit"]'].disabled,'Incierto exige nueva consulta');
  preview={...preview,proveedorExiste:true};await button.events.click();assert.match(dialog.innerHTML,/Actualizar estado en ERP/,'Existente permite confirmar el estado sin recrear');
  assert.ok(context.zeusSupplierSendButton({id:22,active:false}).disabled);
  console.log('UI envío Zeus: consulta sin escritura, confirmación, huella, empresa, éxito e incierto correctos.');
})().catch(error=>{console.error(error);process.exitCode=1;});
