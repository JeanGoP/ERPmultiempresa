const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {DOMParser}=require('@xmldom/xmldom');
const node=()=>({hidden:true,disabled:true,textContent:'',value:'',handlers:{},addEventListener(name,fn){this.handlers[name]=fn;}});
const status=node(),print=node(),excel=node(),actions=node();
actions.querySelector=selector=>({'[data-report-status]':status,'[data-print-kardex]':print,'[data-excel-kardex]':excel})[selector];
const elements={inventoryDateFrom:node(),inventoryDateTo:node(),inventorySearch:node(),inventoryWarehouse:node(),inventoryIssueType:node()};
elements.inventoryDateFrom.value='2026-11-01';elements.inventoryDateTo.value='2026-11-18';
elements.inventoryWarehouse.value='12';elements.inventoryWarehouse.selectedOptions=[{textContent:'01 · Montelíbano'}];
elements.inventorySearch.value='DR150';
elements.inventoryIssueType.value='RECIBIDA_NOVEDAD';elements.inventoryIssueType.selectedOptions=[{textContent:'Recibidas con novedad'}];
const state={inventoryView:'kardex',runtimeMode:'api',erpSession:{api:true,company:{id:'3',name:'MOTOCENTRO',nit:'900060537-4',currency:'COP'}}};
let unit=null,downloads=[];
const sandbox={window:{},document:{querySelector:selector=>selector==='#kardexReportActions'?actions:null,createElement:()=>({click(){downloads.push(this.download);},remove(){}}),body:{append(){},classList:{remove(){}}}},elements,state,selectedInventoryUnit:()=>unit,Intl,Date,setTimeout(){},URL:{createObjectURL:()=> 'blob:test',revokeObjectURL(){}}};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync('public/inventory-report-formats.js','utf8'),sandbox);
vm.runInContext(fs.readFileSync('public/kardex-reports.js','utf8'),sandbox);
const formats=sandbox.window.kardexReportFormats,api=sandbox.window.kardexReports;
const rows=[{fechaContable:'2026-11-18',tipoMovimiento:'VENTA',numeroDocumento:'FV-001',bodega:'Montelíbano',codigo:'000123',descripcion:'Moto <prueba>',entrada:0,salida:1,costoUnitario:500,valorMovimiento:500,existenciaPosterior:4,numeroLote:'00001',unidades:[{unidadSerializadaId:1,chasis:'CH-1',estadoAnterior:'DISPONIBLE',estadoPosterior:'VENDIDA'}]},
{fechaContable:'2026-11-17',tipoMovimiento:'COMPRA_PROVEEDOR',numeroDocumento:'ENT-01',bodega:'Montelíbano',codigo:'000123',descripcion:'Moto <prueba>',entrada:5,salida:0,costoUnitario:500,valorMovimiento:2500,existenciaPosterior:5,unidades:[]}];
const context=api.capture(),report=formats.model(rows,context);
assert.equal(report.rows.length,2);assert.equal(report.rows[0][4],'000123');
assert.equal(report.rows[0][6],'00001');assert.equal(report.totals[8],5);assert.equal(report.totals[9],1);
assert.equal(report.totals[11],2500);assert.equal(report.totals[12],500);assert.equal(report.totals[10],undefined);assert.equal(report.totals[13],undefined);
const html=formats.html(report);assert.match(html,/01 · Montelíbano/);assert.match(html,/01\/11\/2026/);assert.match(html,/18\/11\/2026/);assert.match(html,/DR150/);assert.match(html,/Moto &lt;prueba&gt;/);assert.doesNotMatch(html,/<prueba>/);
rows[0].descripcion='Editado';assert.equal(report.rows[0][5],'Moto <prueba>');
api.loading('kardex');assert.equal(actions.hidden,false);assert.equal(excel.disabled,true);
api.loaded(rows,context);assert.equal(print.disabled,false);assert.equal(excel.disabled,false);
let downloaded;sandbox.window.kardexExcel={workbook(value){downloaded=value;return {};}};
excel.handlers.click();assert.equal(downloaded.rows.length,2);assert.equal(downloads[0],'kardex-2026-11-01-2026-11-18.xlsx');
elements.inventorySearch.value='Otra búsqueda';excel.handlers.click();assert.equal(downloads.length,1);
api.loading('kardex');api.loaded(rows,context);assert.equal(excel.disabled,true);
elements.inventorySearch.value='DR150';api.loaded(rows,context);elements.inventorySearch.handlers.input();assert.equal(print.disabled,true);
api.loaded(rows,context);state.erpSession.company.id='4';excel.handlers.click();assert.equal(downloads.length,1);state.erpSession.company.id='3';
api.failed();assert.equal(print.disabled,true);assert.equal(excel.disabled,true);
api.loaded([],context);assert.equal(excel.disabled,true);
unit={unidadSerializadaId:1,chasis:'CH-1'};
const individual=formats.model([{...rows[0],salida:3,valorMovimiento:1500},rows[1]],api.capture());
assert.equal(individual.rows.length,1);assert.equal(individual.rows[0][8],1);assert.equal(individual.totals[8],1);
assert.ok(!individual.columns.some(col=>col.label==='Saldo posterior'||col.label==='Valor salida'));
assert.match(formats.html(individual),/CH-1/);assert.match(formats.html(individual),/Estado posterior/);
api.loading('serials');assert.equal(actions.hidden,false);assert.equal(print.textContent,'Imprimir seriales');api.reset();assert.equal(actions.hidden,true);
state.inventoryView='stock';
const stockContext=api.capture();
assert.equal(stockContext.view,'stock');assert.equal(stockContext.from,'');assert.equal(stockContext.until,'');assert.equal(stockContext.unit,null);
const stockRows=[{bodega:'Montelíbano',ubicacion:'PISO 1',codigo:'000123',descripcion:'Moto <prueba>',numeroLote:'00001',fechaVencimiento:'2027-01-01',existencia:2.5,costoPromedio:2000,valorTotal:5000},
{bodega:'Montelíbano',codigo:'000123',descripcion:'Moto <prueba>',existencia:3,costoPromedio:2200,valorTotal:6600}];
const stock=formats.model(stockRows,stockContext);assert.equal(stock.rows.length,2);assert.equal(stock.rows[0][2],'000123');assert.equal(stock.rows[0][4],'00001');
assert.equal(stock.rows[1][5],'');assert.equal(stock.totals[6],5.5);assert.equal(stock.totals[8],11600);assert.equal(stock.totals[7],undefined);
const stockHtml=formats.html(stock);assert.match(stockHtml,/Existencias de inventario/);assert.match(stockHtml,/Montelíbano/);assert.match(stockHtml,/DR150/);assert.match(stockHtml,/01\/01\/2027/);assert.match(stockHtml,/Moto &lt;prueba&gt;/);assert.doesNotMatch(stockHtml,/<b>Desde|<b>Hasta|CH-1/);
api.loading('stock');assert.equal(actions.hidden,false);assert.equal(print.textContent,'Imprimir existencias');assert.equal(excel.disabled,true);
api.loaded(stockRows,stockContext);assert.equal(excel.disabled,false);excel.handlers.click();assert.equal(downloads.length,2);assert.match(downloads[1],/^existencias-\d{4}-\d{2}-\d{2}\.xlsx$/);
elements.inventoryDateFrom.value='2020-01-01';excel.handlers.click();assert.equal(downloads.length,3);
elements.inventoryWarehouse.value='99';excel.handlers.click();assert.equal(downloads.length,3);api.loading('stock');api.loaded(stockRows,stockContext);assert.equal(excel.disabled,true);
elements.inventoryWarehouse.handlers.input();assert.equal(excel.disabled,true);
api.loading('kardex');assert.equal(print.textContent,'Imprimir Kardex');assert.equal(excel.disabled,true);
api.reset();
state.inventoryView='aging';sandbox.originAgeBand=1;sandbox.originAgeBands=[['0–30 días'],['31–60 días']];
const agingContext=api.capture();assert.equal(agingContext.view,'aging');assert.equal(agingContext.ageBandIndex,1);assert.equal(agingContext.ageBandLabel,'31–60 días');assert.equal(agingContext.from,'');assert.equal(agingContext.unit,null);
const agingRows=[{articuloId:1,codigo:'000123',descripcion:'Moto <prueba>',factura:'000456',proveedor:'Fábrica & Cía',entrada:'ENT-01',fechaEntrada:'2026-10-01',bodega:'Montelíbano',cantidad:2,dias:40,serializado:true},
{articuloId:1,codigo:'000123',descripcion:'Moto <prueba>',factura:'FA-02',proveedor:'Proveedor',entrada:'ENT-02',fechaEntrada:'2026-10-10',bodega:'Montelíbano',cantidad:1,dias:55,serializado:false}];
const aging=formats.model(agingRows,agingContext);assert.equal(aging.rows[0][0],'000123');assert.equal(aging.rows[0][2],'000456');assert.equal(aging.totals[7],3);assert.equal(aging.totals[8],undefined);assert.equal(aging.references,1);assert.equal(aging.averageDays,45);assert.equal(aging.maxDays,55);
const agingHtml=formats.html(aging);assert.match(agingHtml,/Edad de artículos/);assert.match(agingHtml,/31–60 días/);assert.match(agingHtml,/Fábrica &amp; Cía/);assert.match(agingHtml,/01\/10\/2026/);assert.doesNotMatch(agingHtml,/Valores en|<b>Desde|CH-1/);
api.loading('aging');api.loaded(agingRows,agingContext);assert.equal(print.textContent,'Imprimir edad de artículos');assert.equal(excel.disabled,false);const oldDownloadCount=downloads.length;excel.handlers.click();assert.match(downloads.at(-1),/^edad-articulos-\d{4}-\d{2}-\d{2}\.xlsx$/);
sandbox.originAgeBand=null;excel.handlers.click();assert.equal(downloads.length,oldDownloadCount+1);api.loading('aging');api.loaded(agingRows,agingContext);assert.equal(excel.disabled,true);
api.loaded(agingRows,api.capture());assert.equal(excel.disabled,false);elements.inventorySearch.handlers.input();assert.equal(excel.disabled,true);api.failed();assert.equal(print.disabled,true);api.reset();
const receipt={
  recepcionMercanciaId:1,numero:'00017',estado:'CONTABILIZADA',documentoProveedorId:7,tipoDocumento:'FACTURA',
  numeroDocumento:'000000041',proveedor:'Fábrica <proveedor> & Cía',fechaDocumento:'2026-11-01',fechaContable:'2026-11-02',
  bodega:'Montelíbano',lineas:2,unidadesSerializadas:3,revisadas:2,recibidasConforme:1,recibidasConNovedad:1,noRecibidas:0
};
const issue={
  recepcionNumero:'00017',tipoDocumento:'FACTURA',numeroDocumento:'000000041',proveedor:'Fábrica <proveedor> & Cía',
  fechaDocumento:'2026-11-01',fechaContable:'2026-11-02',bodega:'Montelíbano',numeroLinea:2,numeroUnidad:1,
  codigoArticulo:'000123',descripcion:'Moto <moto>',serial:'0000017',motor:'=MOTOR-17',chasis:'000CH-17',vin:'+VIN-17',
  color:'Negro',modelo:'2027',estadoFisico:'RECIBIDA_NOVEDAD',observacion:'Revisar <caja>\nProtector roto.',
  revisadoPor:'María <revisor>',revisadoEnUtc:'2026-11-18T12:34:56'
};
const serial={
  codigo:'000123',descripcion:'Moto <moto>',estado:'EN_TRANSITO',bodega:'Montelíbano',
  serial:'0000017',motor:'=MOTOR-17',chasis:'000CH-17',vin:'+VIN-17',placa:'001ABC'
};
const expiration={
  bodega:'Montelíbano',codigo:'000017',descripcion:'Aceite <producto>',numeroLote:'00021',
  fechaVencimiento:'2026-11-17',diasParaVencer:-1,estado:'VENCIDO',existencia:1.25
};
const transfer={
  trasladoId:10,numero:'MOV-00001',estado:'REVERTIDO',fechaContable:'2026-11-18',fechaSalida:'2026-11-18T12:00:00',
  bodegaOrigen:{id:1,codigo:'01',nombre:'Montelíbano'},bodegaDestino:{id:2,codigo:'03',nombre:'Repuestos Caucasia'},
  trasladoOriginalId:null,numeroOriginal:null,trasladoReversionId:11,numeroReversion:'REV-00001'
};
const newReports=[
  ['receiving',[receipt],'recepcion-fisica',10],
  ['receipt-history',[receipt],'historial-recepciones',10],
  ['receipt-issues',[issue],'novedades-pendientes',7],
  ['serials',[serial],'seriales',9],
  ['expiry',[expiration],'vencimientos',8]
];
function verifyPrintedValues(value){
  const output=formats.html(value);
  const doc=new DOMParser().parseFromString('<html><body>'+output+'</body></html>','text/html');
  const printed=doc.documentElement.textContent;
  for(const row of value.rows)row.forEach((entry,index)=>{
    if(entry==null||entry==='')return;
    const type=value.columns[index].type;
    const expected=type==='date'?entry.split('-').reverse().join('/')
      :type==='quantity'?new Intl.NumberFormat('es-CO',{maximumFractionDigits:6}).format(entry):String(entry);
    assert.ok(printed.includes(expected),value.view+' conserva '+value.columns[index].label);
  });
  assert.ok(printed.includes(value.title));
  assert.doesNotMatch(output,/<proveedor>|<moto>|<caja>|<revisor>|<producto>/);
  assert.doesNotMatch(output,/Valores en/);
  return {output,doc};
}
for(const [view,source,prefix,columnCount] of newReports){
  state.inventoryView=view;elements.inventoryDateFrom.value='2026-11-01';elements.inventoryDateTo.value='2026-11-18';
  elements.inventorySearch.value='00017';elements.inventoryWarehouse.value='12';
  const captured=api.capture(),value=formats.model(source,captured);
  assert.equal(captured.view,view);assert.equal(captured.unit,null);
  assert.equal(captured.from,['receipt-history','receipt-issues'].includes(view)?'2026-11-01':'');
  const printed=verifyPrintedValues(value);
  assert.equal(printed.doc.getElementsByTagName('thead')[0].getElementsByTagName('th').length,columnCount);
  if(view==='receipt-issues'){
    assert.match(printed.output,/Recibidas con novedad/);
    assert.match(printed.output,/07:34:56/);
    assert.equal(captured.issueType,'RECIBIDA_NOVEDAD');
    assert.equal(value.totals[7],undefined);assert.equal(value.totals[8],undefined);
  }
  if(view==='expiry'){assert.equal(value.totals[7],1.25);assert.equal(value.totals[5],undefined);}
  if(view==='receiving'||view==='receipt-history'){assert.equal(value.totals[8],2);assert.equal(value.totals[9],3);}
  api.loading(view);api.loaded(source,captured);
  assert.equal(actions.hidden,false);assert.equal(excel.disabled,false);assert.equal(print.disabled,false);
  const before=downloads.length;
  excel.handlers.click();assert.equal(downloads.length,before+1);assert.ok(downloads.at(-1).startsWith(prefix+'-'));
  assert.equal(downloaded.view,view);
  elements.inventorySearch.value='Consulta cambiada';
  excel.handlers.click();assert.equal(downloads.length,before+1);
  api.loading(view);api.loaded(source,captured);assert.equal(excel.disabled,true);
  elements.inventorySearch.value='00017';api.loaded(source,captured);assert.equal(excel.disabled,false);
  state.erpSession.company.id='4';excel.handlers.click();assert.equal(downloads.length,before+1);
  api.loading(view);api.loaded(source,captured);assert.equal(excel.disabled,true);state.erpSession.company.id='3';
  api.loaded(source,captured);assert.equal(excel.disabled,false);
  if(view==='receipt-history'||view==='receipt-issues'){
    elements.inventoryDateFrom.value='2026-10-01';excel.handlers.click();assert.equal(downloads.length,before+1);
    elements.inventoryDateFrom.value='2026-11-01';
  }
  if(view==='receipt-issues'){
    elements.inventoryIssueType.value='NO_RECIBIDA';excel.handlers.click();assert.equal(downloads.length,before+1);
    api.loading(view);api.loaded(source,captured);assert.equal(excel.disabled,true);
    elements.inventoryIssueType.value='RECIBIDA_NOVEDAD';api.loaded(source,captured);
    elements.inventoryIssueType.handlers.input();assert.equal(excel.disabled,true);
  }
  api.loaded(source,captured);elements.inventorySearch.handlers.input();assert.equal(excel.disabled,true);
  api.loaded([],captured);assert.equal(print.disabled,true);assert.equal(excel.disabled,true);api.reset();
}
const transferContext={...context,view:'transfers',unit:null,from:'',until:''};
const transfers=formats.model({items:[transfer],page:1,pageSize:100,total:1},transferContext);
verifyPrintedValues(transfers);
assert.equal(transfers.columns.length,8);
assert.ok(!transfers.columns.some(column=>column.label==='Cantidad'||column.label==='Observación'));
formats.download(transfers);assert.ok(downloads.at(-1).startsWith('traslados-'));
const transferDetail=formats.model([{...transfer,observacion:'Empaque <observación>',lineas:[{cantidad:1.25},{cantidad:2}]}],transferContext);
verifyPrintedValues(transferDetail);assert.equal(transferDetail.totals[9],3.25);
api.loading('operations');assert.equal(actions.hidden,true);
console.log('Informes de todas las pestañas de inventario: datos completos, agrupación impresa, filtros, totales y protección de consultas obsoletas correctos.');
