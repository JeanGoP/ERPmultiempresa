const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('public/disbursements.js','utf8');
assert.doesNotMatch(source,/data-search|data-search-button/);
assert.match(source,/data-beneficiary list="egresoBeneficiarios"/);
assert.match(source,/searchTerm='';dialog.showModal\(\);await edit\(\)/,'Tesorería abre nuevo egreso');
assert.doesNotMatch(source,/data-config>Caja/,'No configura caja desde tesorería');
assert.match(source,/\?q='\+encodeURIComponent\(searchTerm\)/,'Consulta filtrada en servidor');
assert.match(source,/if\(!searchTerm\)/,'Sin búsqueda no descarga historial');
assert.match(fs.readFileSync('public/zeus.js','utf8'),/id="zeusCashAccounts"/,'Configuración en integración Zeus');
const parts={};
for(const key of ['[data-beneficiary]','#egresoBeneficiarios','[data-options-note]','[name="terceroId"]','fieldset'])parts[key]={value:'',setCustomValidity(v){this.error=v;}};
let timer,resolveLookup,confirmed=true,requests=[],renders=0;
const a={id:1,identificacion:'123',nombre:'Proveedor A'},b={id:2,identificacion:'456',nombre:'Proveedor <B>'};
const ctx=vm.createContext({
  $e:key=>parts[key],esc:v=>String(v).replaceAll('<','&lt;'),
  beneficiaryLabel:x=>x?`${x.identificacion} · ${x.nombre}`:'',
  generation:1,beneficiaryRequest:0,beneficiaryTimer:null,busy:false,dirty:false,
  current:{datos:{terceroId:'1',lineas:[{tipo:'FACTURA',documentoPorPagarId:10},{tipo:'GASTO'}]},beneficiario:a},
  options:{beneficiarios:[a,b],facturas:[{id:10}]},
  setTimeout:fn=>{timer=fn;return 1;},clearTimeout:()=>{timer=null;},
  valid:token=>token===ctx.generation,url:()=>'/company/1',capture:()=>{},
  confirm:()=>confirmed,renderLines:()=>renders++,notice:message=>{ctx.message=message;},
  apiRequest:async url=>{requests.push(url);return {facturas:[{id:20}]};}
});
vm.runInContext(source.slice(source.indexOf('  function beneficiaryOptions(){'),source.indexOf('  async function save(event){')),ctx);
(async()=>{
  ctx.beneficiaryOptions();assert.match(parts['#egresoBeneficiarios'].innerHTML,/Proveedor &lt;B>/);
  parts['[data-beneficiary]'].value='proveedor remoto';ctx.beneficiaryInput();
  assert.equal(requests.length,0,'Consulta con debounce');
  assert.ok(parts['[data-beneficiary]'].error,'Texto libre no es una selección');
  ctx.apiRequest=async url=>{requests.push(url);return {beneficiarios:[b],masBeneficiarios:false};};
  await timer();assert.match(requests.at(-1),/options\?q=proveedor%20remoto/);
  assert.equal(ctx.options.facturas[0].id,10,'Buscar no cambia las facturas elegidas');
  assert.equal(ctx.current.datos.lineas.length,2);
  ctx.apiRequest=()=>new Promise(resolve=>{resolveLookup=resolve;});
  parts['[data-beneficiary]'].value='anterior';ctx.beneficiaryInput();const pending=timer();
  parts['[data-beneficiary]'].value='nueva';ctx.beneficiaryInput();
  resolveLookup({beneficiarios:[],masBeneficiarios:false});await pending;
  assert.equal(ctx.options.beneficiarios[0].id,2,'Ignora respuestas de búsquedas anteriores');
  confirmed=false;await ctx.changeSupplier(b);
  assert.equal(ctx.current.datos.terceroId,'1');assert.equal(parts['[data-beneficiary]'].value,'123 · Proveedor A');
  assert.equal(ctx.current.datos.lineas.length,2,'Cancelar conserva abonos');
  confirmed=true;ctx.apiRequest=async()=>{throw Error('sin conexión');};await ctx.changeSupplier(b);
  assert.equal(ctx.current.datos.terceroId,'1');assert.equal(ctx.options.facturas[0].id,10);
  assert.equal(ctx.current.datos.lineas.length,2,'Un error no borra los abonos');
  assert.match(ctx.message,/sin conexión/);assert.equal(ctx.busy,false);
  ctx.apiRequest=async url=>{requests.push(url);return {facturas:[{id:20}]};};
  await ctx.changeSupplier(b);assert.equal(ctx.current.datos.terceroId,'2');
  assert.match(requests.at(-1),/options\?terceroId=2$/);
  assert.equal(ctx.options.facturas[0].id,20);assert.equal(ctx.current.datos.lineas.length,1);
  assert.equal(ctx.current.datos.lineas[0].tipo,'GASTO');assert.equal(renders,1);
  ctx.apiRequest=()=>new Promise(resolve=>{resolveLookup=resolve;});
  parts['[data-beneficiary]'].value='otra empresa';ctx.beneficiaryInput();const stale=timer();
  ctx.generation++;resolveLookup({beneficiarios:[],masBeneficiarios:false});await stale;
  assert.equal(ctx.options.beneficiarios[0].id,2,'Ignora resultados después de abandonar la empresa o pantalla');
  console.log('OK: búsqueda integrada, debounce, selección, abonos, errores y respuestas obsoletas.');
})().catch(e=>{console.error(e);process.exitCode=1;});
