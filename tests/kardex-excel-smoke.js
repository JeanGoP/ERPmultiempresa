const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {DOMParser}=require('@xmldom/xmldom');

const namespace='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const context={window:{},Intl,Date,paymentReportZip:files=>files};
vm.runInNewContext(fs.readFileSync('public/kardex-excel.js','utf8'),context);
const workbook=context.window.kardexExcel.workbook;
const report={
  company:{id:3,name:'MOTOCENTRO & COMPAÑÍA',nit:'NIT 900060537-4',currency:'COP'},
  from:'2026-11-01',until:'2026-11-18',warehouseLabel:'01 · Montelíbano',query:'CHASIS-17',
  unit:{unidadSerializadaId:17,chasis:'CHASIS-17',vin:'VIN-17',motor:'MOTOR-17'},
  generatedAt:'2026-11-18T12:34:56Z',
  columns:[
    {label:'Fecha',type:'date'},
    {label:'Documento',type:'text',width:23},
    {label:'Chasis',type:'text'},
    {label:'Descripción',type:'text'},
    {label:'Entrada',type:'quantity',total:true},
    {label:'Costo unitario',type:'money'},
    {label:'Valor',type:'money',total:true},
    {label:'Saldo',type:'quantity'}
  ],
  rows:[
    ['2026-11-01','=SUM(1,2)','000000017','Moto <principal> & negra\nMotor A',1,5000000.25,5000000.25,13],
    ['2026-11-18T08:00:00-05:00','@documento','+CHASIS-17','Otra\u0000moto',0,5000000.25,-5000000.25,12]
  ],
  totals:{4:1,5:10000000.5,6:0,7:25}
};
function parse(text,label){
  const errors=[];
  const doc=new DOMParser({onError:(level,message)=>errors.push(level+': '+message)}).parseFromString(text,'application/xml');
  assert.deepEqual(errors,[],label);
  return doc;
}
function cell(doc,reference){
  return [...doc.getElementsByTagNameNS(namespace,'c')].find(node=>node.getAttribute('r')===reference);
}
function contents(node,name){
  return node.getElementsByTagNameNS(namespace,name)[0]?.textContent;
}
const files=workbook(report);
for(const [name,xml] of Object.entries(files))parse(xml,name);
const sheet=parse(files['xl/worksheets/sheet1.xml'],'Kardex');
const book=parse(files['xl/workbook.xml'],'Workbook');
const plain=sheet.documentElement.textContent;
assert.match(plain,/MOTOCENTRO & COMPAÑÍA/);
assert.match(plain,/NIT 900060537-4 · Moneda COP/);
assert.doesNotMatch(plain,/NIT NIT/);
assert.match(plain,/Desde 2026-11-01 · Hasta 2026-11-18/);
assert.match(plain,/Bodega 01 · Montelíbano/);
assert.match(plain,/Búsqueda CHASIS-17/);
assert.match(plain,/Chasis CHASIS-17 · VIN VIN-17 · Motor MOTOR-17/);
assert.match(plain,/18\/11\/2026.*07:34:56.*Bogotá/);
assert.equal(contents(cell(sheet,'B10'),'t'),'=SUM(1,2)');
assert.equal(cell(sheet,'B10').getAttribute('t'),'inlineStr');
assert.equal(contents(cell(sheet,'B10'),'f'),undefined);
assert.equal(contents(cell(sheet,'C10'),'t'),'000000017');
assert.equal(contents(cell(sheet,'B11'),'t'),'@documento');
assert.equal(contents(cell(sheet,'C11'),'t'),'+CHASIS-17');
assert.equal(contents(cell(sheet,'D10'),'t'),'Moto <principal> & negra\nMotor A');
assert.equal(contents(cell(sheet,'D11'),'t'),'Otramoto');
assert.equal(contents(cell(sheet,'A10'),'v'),String(Date.parse('2026-11-01T00:00:00Z')/86400000+25569));
assert.equal(contents(cell(sheet,'A11'),'v'),String(Date.parse('2026-11-18T00:00:00Z')/86400000+25569));
assert.equal(cell(sheet,'A10').getAttribute('s'),'5');
assert.equal(contents(cell(sheet,'F10'),'v'),'5000000.25');
assert.equal(contents(cell(sheet,'G11'),'v'),'-5000000.25');
assert.equal(cell(sheet,'F10').getAttribute('s'),'7');
assert.equal(contents(cell(sheet,'E12'),'f'),'SUM(E10:E11)');
assert.equal(contents(cell(sheet,'E12'),'v'),'1');
assert.equal(contents(cell(sheet,'G12'),'f'),'SUM(G10:G11)');
assert.equal(contents(cell(sheet,'G12'),'v'),'0');
assert.equal(contents(cell(sheet,'A12'),'t'),'TOTAL');
assert.equal(contents(cell(sheet,'F12'),'f'),undefined);
assert.equal(contents(cell(sheet,'H12'),'f'),undefined);
assert.equal(sheet.getElementsByTagNameNS(namespace,'f').length,2);
assert.equal(sheet.getElementsByTagNameNS(namespace,'autoFilter')[0].getAttribute('ref'),'A9:H11');
assert.equal(sheet.getElementsByTagNameNS(namespace,'pane')[0].getAttribute('topLeftCell'),'A10');
assert.equal(sheet.getElementsByTagNameNS(namespace,'pane')[0].getAttribute('ySplit'),'9');
assert.equal(sheet.getElementsByTagNameNS(namespace,'sheetView')[0].getAttribute('showGridLines'),'0');
assert.equal(sheet.getElementsByTagNameNS(namespace,'col')[1].getAttribute('width'),'23');
assert.equal(sheet.getElementsByTagNameNS(namespace,'pageSetup')[0].getAttribute('orientation'),'landscape');
assert.equal(sheet.getElementsByTagNameNS(namespace,'pageSetup')[0].getAttribute('fitToWidth'),'1');
assert.equal(sheet.getElementsByTagNameNS(namespace,'pageSetup')[0].getAttribute('fitToHeight'),'0');
const names=[...book.getElementsByTagNameNS(namespace,'definedName')];
assert.equal(names.find(node=>node.getAttribute('name')==='_xlnm.Print_Titles').textContent,"'Kardex'!$1:$9");
assert.equal(names.find(node=>node.getAttribute('name')==='_xlnm.Print_Area').textContent,"'Kardex'!$A$1:$H$12");
const style=parse(files['xl/styles.xml'],'Estilos');
assert.equal(style.getElementsByTagNameNS(namespace,'cellXfs')[0].getElementsByTagNameNS(namespace,'xf')[0].getAttribute('numFmtId'),'49');
const headingStyle=style.getElementsByTagNameNS(namespace,'cellXfs')[0].getElementsByTagNameNS(namespace,'xf')[4]
  .getElementsByTagNameNS(namespace,'alignment')[0];
assert.equal(headingStyle.getAttribute('horizontal'),'center');
assert.equal(headingStyle.getAttribute('vertical'),'center');
assert.equal(style.getElementsByTagNameNS(namespace,'fonts')[0].getElementsByTagNameNS(namespace,'font')[1]
  .getElementsByTagNameNS(namespace,'sz')[0].getAttribute('val'),'16');
assert.match(workbook({...report,demo:true})['xl/worksheets/sheet1.xml'],/Datos de demostración/);

const emptyFiles=workbook({...report,rows:[],totals:{4:0,6:0},from:null,until:null,query:'',unit:null,warehouseLabel:''});
const empty=parse(emptyFiles['xl/worksheets/sheet1.xml'],'Kardex vacío');
assert.match(empty.documentElement.textContent,/Sin límite/);
assert.match(empty.documentElement.textContent,/Todas las bodegas/);
assert.match(empty.documentElement.textContent,/Todas las unidades/);
assert.equal(empty.getElementsByTagNameNS(namespace,'autoFilter')[0].getAttribute('ref'),'A9:H9');
assert.equal(empty.getElementsByTagNameNS(namespace,'f').length,0);
assert.equal(contents(cell(empty,'E10'),'v'),'0');
const wide=workbook({...report,columns:Array.from({length:27},(_,index)=>({label:'Columna '+index,type:'text'})),rows:[Array(27).fill('=literal')],totals:{}});
assert.match(wide['xl/worksheets/sheet1.xml'],/ref="A9:AA10"/);
const january=parse(workbook({...report,rows:[['1900-01-01','','','',0,0,0,0]],totals:{}})['xl/worksheets/sheet1.xml'],'Fecha inicial');
assert.equal(contents(cell(january,'A10'),'v'),'1');
assert.throws(()=>workbook({...report,rows:[['2026-02-30','','','',0,0,0,0]]}),/fecha inválida/);
assert.throws(()=>workbook({...report,rows:[['2026-11-18','','','',NaN,0,0,0]]}),/valor inválido/);
assert.throws(()=>workbook({...report,rows:[['2026-11-18','','','',1,'500',0,0]]}),/valor inválido/);
assert.throws(()=>workbook({...report,rows:[['faltan celdas']]}),/no coincide/);
assert.throws(()=>workbook({...report,totals:{4:Infinity,6:0}}),/valor inválido/);
const actualContext={window:{},Intl,Date,Blob,TextEncoder};
vm.runInNewContext(fs.readFileSync('public/payment-report-excel.js','utf8'),actualContext);
vm.runInNewContext(fs.readFileSync('public/kardex-excel.js','utf8'),actualContext);
const zipped=actualContext.window.kardexExcel.workbook(report);
assert.ok(zipped instanceof Blob);
assert.equal(zipped.type,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
zipped.arrayBuffer().then(buffer=>{
  assert.deepEqual([...new Uint8Array(buffer).slice(0,4)],[80,75,3,4]);
  console.log('Excel Kardex: ZIP real, XML, fechas, números, texto seguro, filtros, unidad, impresión y totales verificados.');
}).catch(error=>{console.error(error);process.exitCode=1;});
