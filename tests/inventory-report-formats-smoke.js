const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const sandbox={window:{},Intl,Date};
vm.runInNewContext(fs.readFileSync('public/inventory-report-formats.js','utf8'),sandbox);
const model=sandbox.window.inventoryReportFormats.model;
const context={
  company:{id:'3',name:'MOTOCENTRO & Cía',nit:'900060537-4',currency:'COP'},
  warehouseLabel:'01 · Montelíbano',query:'00017',from:'2026-11-01',until:'2026-11-18',
  issueTypeLabel:'Recibidas con novedad'
};
const byView=view=>({...context,view});
const receipt={
  recepcionMercanciaId:1,numero:'00017',estado:'CONTABILIZADA',documentoProveedorId:7,tipoDocumento:'FACTURA',
  numeroDocumento:'000000041',proveedor:'Fábrica & Cía',fechaDocumento:'2026-11-01',fechaContable:'2026-11-02',
  bodega:'Montelíbano',lineas:2,unidadesSerializadas:3,revisadas:2,recibidasConforme:1,recibidasConNovedad:1,noRecibidas:0
};
for(const view of ['receiving','receipt-history']){
  const report=model([receipt,{...receipt,numero:'00018',lineas:1,unidadesSerializadas:2,revisadas:2,recibidasConforme:0,recibidasConNovedad:1,noRecibidas:1}],byView(view));
  assert.equal(report.view,view);
  assert.equal(report.recordLabel,'recepciones');
  assert.equal(report.rows[0][0],'00017');
  assert.equal(report.rows[0][3],'000000041');
  assert.equal(report.rows[0][6],'2026-11-01');
  assert.equal(report.columns[6].type,'date');
  assert.equal(report.columns[7].type,'date');
  assert.equal(report.totals[8],3);
  assert.equal(report.totals[9],5);
  assert.equal(report.totals[10],4);
  assert.equal(report.totals[11],1);
  assert.equal(report.totals[12],2);
  assert.equal(report.totals[13],1);
  assert.equal(report.totals[0],undefined);
}
const issue={
  recepcionMercanciaRevisionUnidadId:4,recepcionMercanciaId:1,recepcionNumero:'00017',documentoProveedorId:7,
  tipoDocumento:'FACTURA',numeroDocumento:'000000041',proveedor:'Fábrica & Cía',fechaDocumento:'2026-11-01',
  fechaContable:'2026-11-02',bodega:'Montelíbano',recepcionMercanciaUnidadId:2,numeroLinea:2,codigoArticulo:'000123',
  descripcion:'Moto <prueba>',numeroUnidad:1,serial:'0000017',motor:'=MOTOR-17',chasis:'000CH-17',vin:'+VIN-17',
  color:'Negro',modelo:'2027',estadoFisico:'RECIBIDA_NOVEDAD',observacion:'Revisar <caja>\nProtector roto.',
  revisadoPor:'María <prueba>',revisadoEnUtc:'2026-11-18T12:34:56'
};
const issues=model([issue],byView('receipt-issues'));
assert.equal(issues.rows[0][9],'000123');
assert.equal(issues.rows[0][11],'0000017');
assert.equal(issues.rows[0][12],'=MOTOR-17');
assert.equal(issues.columns[12].type,'text');
assert.equal(issues.rows[0][14],'+VIN-17');
assert.equal(issues.rows[0][18],'Revisar <caja>\nProtector roto.');
assert.match(issues.rows[0][20],/18\/11\/2026.*07:34:56/);
assert.equal(issues.columns[20].type,'text');
assert.deepEqual(Object.keys(issues.totals),[]);
assert.equal(issues.issueTypeLabel,context.issueTypeLabel);
assert.equal(model([{...issue,revisadoEnUtc:'2026-11-18T12:34:56Z'}],byView('receipt-issues')).rows[0][20],issues.rows[0][20]);

const serials=model([{
  codigo:'000123',descripcion:'Moto <prueba>',estado:'VENDIDA',bodega:null,serial:'0000017',motor:'=MOTOR-17',
  chasis:'000CH-17',vin:'+VIN-17',placa:'001ABC'
}],byView('serials'));
assert.equal(serials.recordLabel,'unidades');
assert.equal(serials.rows[0][0],'000123');
assert.equal(serials.rows[0][2],'VENDIDA');
assert.equal(serials.rows[0][3],'');
assert.equal(serials.rows[0][4],'0000017');
assert.equal(serials.rows[0][8],'001ABC');
assert.ok(serials.columns.every(column=>column.type==='text'&&!column.total));
assert.deepEqual(Object.keys(serials.totals),[]);

const expiry=model([
  {bodega:'Origen',codigo:'00017',descripcion:'Aceite',numeroLote:'00021',fechaVencimiento:'2026-11-17',diasParaVencer:-1,estado:'VENCIDO',existencia:1.25},
  {bodega:'Destino',codigo:'00017',descripcion:'Aceite',numeroLote:'00022',fechaVencimiento:'2026-11-21',diasParaVencer:3,estado:'CRITICO',existencia:2.5}
],byView('expiry'));
assert.equal(expiry.rows[0][3],'00021');
assert.equal(expiry.rows[0][5],-1);
assert.equal(expiry.columns[4].type,'date');
assert.equal(expiry.totals[7],3.75);
assert.equal(expiry.totals[5],undefined);

const transfer={
  trasladoId:10,numero:'MOV-00001',estado:'REVERTIDO',fechaContable:'2026-11-18',fechaSalida:'2026-11-18T12:00:00',
  bodegaOrigen:{id:1,codigo:'01',nombre:'Montelíbano'},bodegaDestino:{id:2,codigo:'03',nombre:'Repuestos Caucasia'},
  trasladoOriginalId:null,numeroOriginal:null,trasladoReversionId:11,numeroReversion:'REV-00001'
};
const transfers=model({items:[transfer],page:1,pageSize:100,total:1},byView('transfers'));
assert.equal(transfers.rows[0][2],'2026-11-18');
assert.equal(transfers.rows[0][4],'01 · Montelíbano');
assert.equal(transfers.rows[0][5],'03 · Repuestos Caucasia');
assert.equal(transfers.rows[0][7],'REV-00001');
assert.equal(transfers.columns.length,8);
assert.ok(!transfers.columns.some(column=>column.label==='Observación'||column.label==='Cantidad'));
assert.deepEqual(Object.keys(transfers.totals),[]);
const detailed=model([
  {...transfer,observacion:'Bodega <equivocada>',lineas:[{cantidad:1.5},{cantidad:2}]},
  {...transfer,numero:'MOV-00002',fechaContable:null}
],byView('transfers'));
assert.equal(detailed.columns.length,10);
assert.equal(detailed.rows[0][8],'Bodega <equivocada>');
assert.equal(detailed.rows[0][9],3.5);
assert.equal(detailed.rows[1][3],'');
assert.equal(detailed.rows[1][8],'');
assert.equal(detailed.rows[1][9],'');
assert.equal(detailed.totals[9],3.5);
assert.equal(model([{...transfer,cantidad:4}],byView('transfers')).totals[8],4);
assert.equal(model([{...transfer,lineas:[{cantidad:2},{cantidad:''}]}],byView('transfers')).columns.length,8);

for(const view of ['receiving','receipt-history','receipt-issues','serials','expiry','transfers']){
  const report=model([],byView(view));
  assert.equal(report.rows.length,0);
  assert.ok(report.title&&report.recordLabel);
  assert.ok(report.sheetName.length<=31);
  assert.match(report.generatedAt,/^\d{4}-\d{2}-\d{2}T/);
  assert.ok(report.columns.every(column=>column.width>0&&['text','date','quantity','money'].includes(column.type)));
  assert.notEqual(report.company,context.company);
  report.company.name='Cambio local';
  assert.equal(context.company.name,'MOTOCENTRO & Cía');
}
assert.equal(model([{...receipt,lineas:undefined}],byView('receiving')).rows[0][8],'');
assert.equal(receipt.numero,'00017');
assert.throws(()=>model([],byView('unknown')),/no tiene un formato/);
assert.throws(()=>model({},byView('receiving')),/datos válidos/);
assert.throws(()=>model([{...receipt,lineas:Infinity}],byView('receiving')),/cantidad inválida/);
assert.throws(()=>model([{...issue,revisadoEnUtc:'inválido'}],byView('receipt-issues')),/fecha de revisión inválida/);
console.log('Formatos de inventario: recepción, historial, novedades, seriales, vencimientos y traslados con contexto, tipos y totales correctos.');
