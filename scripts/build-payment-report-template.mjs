// Autoría del formato, fuera de producción. Usa el runtime de hojas de cálculo.
// ERP_ARTIFACT_NODE_MODULES debe apuntar al node_modules del runtime instalado.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {inflateRawSync} from 'node:zlib';
const runtime=process.env.ERP_ARTIFACT_NODE_MODULES;
if(!runtime)throw new Error('Configura ERP_ARTIFACT_NODE_MODULES con el runtime de autoría.');
const resolve=createRequire(path.join(runtime,'..','runtime.cjs'));
const {Workbook,SpreadsheetFile}=await import(pathToFileURL(resolve.resolve('@oai/artifact-tool')));
const wb=Workbook.create();
const headers=[['Factura','Bruto sin impuestos','Descuento factura','Neto sin impuestos','Impuestos','Cargos','Otros ajustes factura','Valor factura','Pagos registrados','Saldo actual'],['Fecha','Factura','Movimiento','Soporte aplicado','Cargo','Abono','Banco / consignación']];
for(let i=0;i<2;i++){
  const sheet=wb.worksheets.add(i?'Pagos y notas':'Facturas'),last=i?'H':'K';
  sheet.showGridLines=false;sheet.tabColor=i?'#6A897C':'#193F3B';
  sheet.getRange(`A1:${last}18`).format={font:{name:'Arial',size:11,color:'#223C34'},rowHeight:24,verticalAlignment:'center'};
  sheet.getRange('A1:A18').format.columnWidth=3;
  sheet.getRange(`B1:${last}18`).format.columnWidth=20;
  sheet.getRange('B1:B18').format.columnWidth=i?15:24;
  if(i)sheet.getRange('E1:E18').format.columnWidth=48;
  const merged=(range,value)=>{sheet.mergeCells(range);sheet.getRange(range.split(':')[0]).values=[[value]];};
  merged(`B2:${last}2`,i?'Pagos y notas aplicados':'Relación de facturas y pagos');
  sheet.getRange(`B2:${last}2`).format={font:{name:'Arial',size:16,bold:true,color:'#193F3B'},rowHeight:34};
  merged(`B4:${last}4`,'{{empresa}}');merged(`B5:${last}5`,'{{proveedor}}');merged(`B6:${last}6`,'{{referencia}}');
  merged(`B7:${last}7`,'{{fecha}}');merged(`B9:${last}9`,'{{alcance}}');
  sheet.getRange(`B4:${last}7`).format.wrapText=true;
  sheet.getRange(`B9:${last}9`).format.font={name:'Arial',size:11,color:'#62756D',italic:true};
  sheet.getRange(`B4:${last}4`).format.font.bold=true;
  sheet.getRangeByIndexes(10,1,1,headers[i].length).values=[headers[i]];
  sheet.getRange(`B11:${last}11`).format={fill:'#193F3B',font:{name:'Arial',size:11,bold:true,color:'#FFFFFF'},wrapText:true,horizontalAlignment:'center',rowHeight:36};
  // Filas prototipo: blanca, alterna, total y observación. El navegador las repite.
  for(let r=12;r<=14;r++){
    sheet.getRangeByIndexes(r-1,1,1,headers[i].length).values=[headers[i].map((_,c)=>c===0?'{{dato}}':0)];
    sheet.getRange(`B${r}:${last}${r}`).format={rowHeight:28,wrapText:true,fill:r===13?'#F3F7F5':r===14?'#DCEBE3':'#FFFFFF'};
    if(r===14)sheet.getRange(`B${r}:${last}${r}`).format.font.bold=true;
    sheet.getRange(`${i?'F':'C'}${r}:${i?'G':last}${r}`).setNumberFormat('#,##0.00;[Red](#,##0.00);"—"');
    sheet.getRange(`${i?'F':'C'}${r}:${i?'G':last}${r}`).format.horizontalAlignment='right';
    sheet.getRange(`B${r}:${i?'E':'B'}${r}`).setNumberFormat('@');
    sheet.getRange(`B${r}:${i?'E':'B'}${r}`).format.horizontalAlignment='left';
    if(i)sheet.getRange(`B${r}`).setNumberFormat('dd/mm/yyyy');
  }
  merged(`B16:${last}16`,'{{nota}}');sheet.getRange(`B16:${last}16`).format={wrapText:true,rowHeight:44,font:{name:'Arial',size:11,color:'#62756D'}};
  sheet.freezePanes.freezeRows(11);
}
wb.recalculate();
await fs.mkdir('tmp/payment-xlsx',{recursive:true});
await (await SpreadsheetFile.exportXlsx(wb)).save('tmp/payment-xlsx/template.xlsx');
// Empaqueta los componentes del XLSX para rellenar la plantilla en el navegador.
// No requiere un servicio Node en Netlify ni herramientas de autoría en producción.
const zip=await fs.readFile('tmp/payment-xlsx/template.xlsx'),files={};
let end=zip.length-22;while(end>=0&&zip.readUInt32LE(end)!==0x06054b50)end--;
if(end<0)throw new Error('El archivo generado no es un ZIP válido.');
let offset=zip.readUInt32LE(end+16);
for(let i=0;i<zip.readUInt16LE(end+10);i++){
  const method=zip.readUInt16LE(offset+10),size=zip.readUInt32LE(offset+20),nameSize=zip.readUInt16LE(offset+28),extra=zip.readUInt16LE(offset+30),comment=zip.readUInt16LE(offset+32),local=zip.readUInt32LE(offset+42);
  const name=zip.subarray(offset+46,offset+46+nameSize).toString('utf8');
  const start=local+30+zip.readUInt16LE(local+26)+zip.readUInt16LE(local+28),bytes=zip.subarray(start,start+size);
  if(method!==0&&method!==8)throw new Error('Compresión no compatible.');
  files[name]=(method===8?inflateRawSync(bytes):bytes).toString('utf8');offset+=46+nameSize+extra+comment;
}
await fs.mkdir('public/assets',{recursive:true});
await fs.writeFile('public/assets/payment-report-template.json',JSON.stringify({version:1,files}));
console.log('Plantilla XLSX creada con Artifact Tool.');
