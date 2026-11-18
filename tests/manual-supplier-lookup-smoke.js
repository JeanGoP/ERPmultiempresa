const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const source=fs.readFileSync('public/app.js','utf8');
const lookupCode=source.slice(source.indexOf('function foldSupplierSearch'),source.indexOf('function apiClientToMaster'));
const payloadCode=source.slice(source.indexOf('function buildManualSupplierDocumentPayload'),source.indexOf('async function refreshManualWorkflow'));
const supplier={identification:'900123456',identificationType:'NIT',verificationDigit:'7',name:'Fábrica de Motos S.A.S.',
  address:'Calle 1',cityCode:'23001',city:'Montería',departmentCode:'23',department:'Córdoba',countryCode:'57',country:'Colombia',
  phone:'12345',email:'ventas@fabrica.co',clientType:'',active:true};
const fields={manualNit:{value:'900.123.456-7'},manualSupplier:{value:'',readOnly:false},manualSupplierStatus:{textContent:'',classList:{add(){},remove(){}}}};
const context=vm.createContext({state:{apiContext:{masterData:{suppliers:[supplier]}}},$:(selector)=>fields[selector.slice(1)],
  findById:()=>null,getCompanyMasterData:()=>({data:{units:[]}})});
vm.runInContext(lookupCode+payloadCode,context);

assert.equal(context.manualSupplierNit('900.123.456-7'),'900123456');
assert.equal(context.foldSupplierSearch('Fábrica xx'),'fabrica xx');
assert.equal(context.findManualSupplier(fields.manualNit.value).name,supplier.name);
context.syncManualSupplierFromNit();
assert.equal(fields.manualSupplier.value,supplier.name);
assert.equal(fields.manualSupplier.readOnly,false);
assert.equal(context.findManualSupplierSuggestions('fabrica').items[0].name,supplier.name);
assert.equal(context.findManualSupplierSuggestions('motos fabrica').items[0].identification,supplier.identification);
assert.equal(context.findManualSupplierSuggestions('900.123').items[0].name,supplier.name);
assert.equal(context.findManualSupplierSuggestions('900.123.456-7').items[0].name,supplier.name);
assert.equal(context.findManualSupplierSuggestions('').total,0);
assert.equal(context.findManualSupplierSuggestions('desconocido').total,0);
context.state.apiContext.masterData.suppliers.push({...supplier,identification:'111',name:'Proveedor inactivo',active:false});
assert.equal(context.findManualSupplierSuggestions('inactivo').total,0);
context.state.apiContext.masterData.suppliers.push(...Array.from({length:12},(_,i)=>({...supplier,identification:String(i),name:`Fábrica ${i}`})));
assert.equal(context.findManualSupplierSuggestions('fabrica').items.length,8);
assert.equal(context.findManualSupplierSuggestions('fabrica').total,13);

const payload=context.buildManualSupplierDocumentPayload({nit:supplier.identification,supplier:supplier.name,supplierProfile:supplier,
  invoiceNumber:'F-1',documentType:'FACTURA',issueDate:'2026-11-11',dueDate:null,paymentCondition:'CONTADO',creditDays:0,
  lines:[],total:0,id:'test'});
assert.equal(payload.proveedorIdentificacion,supplier.identification);
assert.equal(payload.proveedorDigitoVerificacion,'7');
assert.equal(payload.proveedorDireccion,'Calle 1');
assert.equal(payload.proveedorCiudadCodigo,'23001');
assert.equal(payload.proveedorTelefono,'12345');

fields.manualNit.value='123456789';
context.syncManualSupplierFromNit();
assert.equal(fields.manualSupplier.value,'');
assert.equal(fields.manualSupplier.readOnly,false);
assert.match(fs.readFileSync('backend/NexoERP.Api/Purchasing/PurchasingRepository.cs','utf8'),/RazonSocial COLLATE Latin1_General_CI_AI LIKE/);
console.log('Entrada manual: búsqueda por nombre y NIT sin tildes, sugerencias limitadas y datos del proveedor.');
