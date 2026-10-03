const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const app=fs.readFileSync('public/app.js','utf8');
const backend=fs.readFileSync('backend/NexoERP.Api/Zeus/ZeusCustomerTransport.cs','utf8');
const salesModule=fs.readFileSync('backend/NexoERP.Api/Sales/SalesModule.cs','utf8');
const permissions=fs.readFileSync('backend/NexoERP.Api/Security/PermissionEndpointFilterExtensions.cs','utf8');
const fields=Object.fromEntries(['cityCode','city','departmentCode','department','countryCode','country','divisionPoliticaZeus']
  .map(name=>[name,{value:''}]));
const search={value:'',dataset:{},events:{},setAttribute(name,value){this[name]=value;},after(list){this.list=list;},
  addEventListener(name,handler){this.events[name]=handler;}};
const elements={masterRecordForm:{elements:{...fields,cityLookup:search}},masterRecordDialog:{open:true},
  masterFormError:{hidden:true,textContent:''}};
let timer;
const city={divisionPolitica:'5723001',ciudadCodigo:'23001',ciudad:'Montería',departamentoCodigo:'23',
  departamento:'Córdoba',paisCodigo:'57',pais:'Colombia'};
const context=vm.createContext({elements,state:{erpSession:{company:{id:3}}},
  document:{createElement(){return {replaceChildren(...items){this.items=items;}};}},
  Option:class{constructor(text,value){this.text=text;this.value=value;}},
  apiRequest:async()=>[city],setTimeout:callback=>{timer=callback;return 1;},clearTimeout:()=>{},encodeURIComponent});
vm.runInContext(app.slice(app.indexOf('function setupMasterCityLookup'),app.indexOf('function openMasterForm')),context);
(async()=>{
  context.setupMasterCityLookup();
  search.value='monte';search.events.input();await timer();
  assert.equal(search.list.items.length,1);
  search.value=search.list.items[0].value;search.events.input();
  assert.equal(fields.divisionPoliticaZeus.value,'5723001');
  assert.equal(fields.cityCode.value,'23001');
  assert.equal(fields.departmentCode.value,'23');
  assert.equal(fields.countryCode.value,'57');
  assert.equal(search.dataset.selectedCode,'23001');
  search.value='Otra ciudad';search.events.input();
  assert.equal(fields.cityCode.value,'');
  assert.equal(search.dataset.selectedCode,'');
  assert.match(backend,/FROM dbo\.DIVPOLITICA d/);
  assert.match(backend,/RTRIM\(ISNULL\(NOMBVENDE,''\)\)/);
  assert.match(app,/new Option\(`\$\{x\.codigo\} · \$\{x\.nombre\|\|'Sin nombre'\}`,x\.codigo\)/);
  assert.match(salesModule,/zeus\.FindCityAsync/);
  assert.match(salesModule,/zeus\/cities[\s\S]*RequireErpPermission\("MAESTROS\.CLIENTE\.ADMINISTRAR","MAESTROS\.PROVEEDOR\.ADMINISTRAR"\)/);
  assert.match(permissions,/foreach\(var permission in permissions\)/);
  assert.match(app,/state\.masterView==='suppliers'\|\|state\.masterView==='clients'\)setupMasterCityLookup\(editingSupplier\|\|editingClient\)/);
  assert.match(app,/Selecciona una ciudad de las opciones de Zeus antes de guardar el proveedor/);
  assert.match(app,/payload\.direccion=values\.address\|\|null/);
  assert.match(app,/Selecciona una ciudad de las opciones de Zeus antes de guardar/);
  console.log('Clientes y proveedores: ciudad Zeus completa códigos y no conserva una selección editada manualmente.');
})().catch(error=>{console.error(error);process.exitCode=1;});
