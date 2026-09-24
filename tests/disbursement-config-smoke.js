const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('public/disbursements.js','utf8');
const elements={};
for(const s of ['[data-notice]','[data-content]','[name="branch"]','[name="method"]','[name="account"]','[name="currency"]','[data-back]','[data-config-form]','fieldset'])elements[s]={value:'',remove(){this.removed=true;}};
elements['[name="branch"]'].value='1';elements['[name="method"]'].value='TRANSFERENCIA';
const root={isConnected:true,querySelector:s=>elements[s]};
const requests=[];let writes=0;
const context=vm.createContext({document:{querySelector:()=>root},state:{erpSession:{company:{id:1}}},zeusCurrent:()=>true,esc:s=>String(s),apiRequest:async(url,options)=>{
 requests.push(url);
 if(options){writes++;const payload=JSON.parse(options.body);assert.equal(payload.version,3);assert.equal(payload.cuenta,'111005');assert.equal(payload.monedaZeus,'TRA');return;}
 if(url.endsWith('/cash-configuration'))return {opts:{sucursales:[{id:1,nombre:'Sucursal'}]},saved:[{sucursalId:1,medioPago:'TRANSFERENCIA',cuenta:'111005',monedaZeus:'TRA',version:3}]};
 assert.ok(url.endsWith('/cash-chart'));return {cuentas:[{codigo:'111005',nombre:'Banco'}],medios:[{codigo:'TRA',nombre:'Transferencia'}]};
}});
vm.runInContext(source.slice(source.indexOf('  async function configure(scope){'),source.lastIndexOf('})();')),context);
(async()=>{
 await context.configure({});assert.equal(elements['[name="account"]'].value,'111005');
 assert.doesNotMatch(elements['[data-content]'].innerHTML,/<form|<button/,'Sin formulario ni botón de guardar independiente');
 await root.prepareSave()();assert.equal(writes,0,'Sin cambios no guarda cuentas');
 elements['[name="account"]'].value='';elements['[name="account"]'].onchange();
 assert.throws(()=>root.prepareSave(),/Completa/,'Valida antes de guardar configuración general');
 elements['[name="account"]'].value='111005';elements['[name="account"]'].onchange();
 elements['[name="method"]'].value='EFECTIVO';elements['[name="method"]'].onchange();
 assert.equal(elements['[name="account"]'].value,'');
 elements['[name="method"]'].value='TRANSFERENCIA';elements['[name="method"]'].onchange();
 assert.equal(elements['[name="account"]'].value,'111005','Conserva cambios al volver al medio de pago');
 await root.prepareSave()();assert.equal(writes,1);
 await root.prepareSave()();assert.equal(writes,1,'No repite cuentas guardadas');
 assert.ok(requests.every(x=>x.startsWith('/api/v1/companies/1/')));
 root.isConnected=false;assert.throws(()=>root.prepareSave(),/Actualiza/);assert.equal(writes,1,'Pantalla retirada no guarda configuración');
 const zeus=fs.readFileSync('public/zeus.js','utf8');
 const layout=zeus.slice(zeus.indexOf('function zeusRenderSettings(){'),zeus.indexOf('function zeusReadSettings(){'));
 assert.ok(layout.indexOf('id="zeusCashAccounts"')<layout.indexOf('</section>'),'Caja banco está dentro de la primera sección');
 assert.equal((layout.match(/type="submit"/g)||[]).length,1,'Un único botón para guardar');
 assert.match(zeus,/prepareSave\?\.\(\)/);assert.match(zeus,/if\(saveCash\)await saveCash\(\)/);
 console.log('OK: configuración bancaria en integración, carga, guardado y aislamiento.');
})().catch(e=>{console.error(e);process.exitCode=1;});
