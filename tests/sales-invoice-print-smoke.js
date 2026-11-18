const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');

const context={window:{},Intl};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../public/sales-invoice-print.js'),'utf8'),context);
const data={header:{numero:'FV-7',fecha:'2026-10-14',sucursalCodigo:'01',sucursal:'CENTRO',cliente:'Ana <script>',identificacion:'123',total:119000,anticipo:19000,observacion:'Garantía <especial>'},articulos:[{codigo:'M1',descripcion:'Moto',bodegaCodigo:'B1',bodega:'Principal',cantidad:1,precio:119000,base:100000,iva:19000,ivaTarifa:19}],conceptos:[],anticipos:[{reciboId:2,fecha:'2026-10-10',concepto:'Cuota inicial',valor:19000}],cuotas:[{numero:1,tipo:'ORDINARIA',vence:'2026-11-14',valor:100000}]};
const report=context.window.salesInvoicePrint.html(data,{name:'MOTOCENTRO',nit:'NIT 900006537-4'});
assert.match(report,/FACTURA DE VENTA/);
assert.match(report,/No válido como factura electrónica DIAN/);
assert.match(report,/FV-7/);
assert.match(report,/MOTOCENTRO/);
assert.doesNotMatch(report,/Plan de cuotas|2026-11-14|Valor original/);
assert.match(report,/Total factura<\/th><td>119\.000,00/);
assert.doesNotMatch(report,/Anticipos aplicados|Saldo inicial financiado|Cuota inicial|RC-2/);
assert.match(report,/Resumen del IVA/);
assert.match(report,/Ana &lt;script&gt;/);
assert.doesNotMatch(report,/<script>/);
assert.match(report,/No contiene resolución de numeración, CUFE, código QR/);
data.conceptos=[{codigo:'F',nombre:'Financiación',valor:20000,mostrarEnCuerpo:false,mostrarEnTotales:true},{codigo:'S',nombre:'Servicio',valor:5000,mostrarEnCuerpo:true,mostrarEnTotales:false},{codigo:'D',nombre:'Domicilio',valor:3000,mostrarEnCuerpo:true,mostrarEnTotales:true},{codigo:'I',nombre:'Interno',valor:1000,mostrarEnCuerpo:false,mostrarEnTotales:false}];
const positioned=context.window.salesInvoicePrint.html(data,{name:'MOTOCENTRO',nit:'NIT 900006537-4'});
assert.match(positioned,/<th>Financiación<\/th>/);
assert.match(positioned,/<td>S<\/td><td colspan="8">Servicio<\/td>/);
assert.doesNotMatch(positioned,/<td>F<\/td>/);
assert.match(positioned,/<td>D<\/td><td colspan="8">Domicilio<\/td>/);
assert.match(positioned,/<th>Domicilio<\/th>/);
assert.doesNotMatch(positioned,/>Interno</);
assert.doesNotMatch(positioned,/Conceptos del cuerpo/);
assert.match(positioned,/Otros conceptos<\/th><td>23\.000,00/);
assert.match(positioned,/Total factura<\/th><td>142\.000,00/);
data.conceptos=[{codigo:'L',nombre:'Anterior',valor:1000,ubicacionFormato:'TOTALES'}];
assert.match(context.window.salesInvoicePrint.html(data,{name:'MOTOCENTRO',nit:'NIT 900006537-4'}),/<th>Anterior<\/th>/);
data.empresa={razonSocial:'Empresa de prueba',nit:'900000001',digitoVerificacion:'2',direccion:'Calle 1 # 2-3',telefono:'1234567',ciudad:'Montelíbano'};
Object.assign(data.header,{elaboradoPor:'Auxiliar',direccionCliente:'Barrio Centro',telefonoCliente:'3000000000',ciudadCliente:'Montería',vendedor:'057'});
data.conceptos=[];
data.articulos=[{codigo:'M1',descripcion:'Moto',cantidad:1,precio:107100,base:90000,iva:17100,ivaTarifa:19,
  precioBaseConIva:119000,descuentoPorcentaje:10,unidades:[{chasis:'CH-123',motor:'M-456',modelo:'2027',color:'NEGRO'}]}];
data.header.total=107100;
const discounted=context.window.salesInvoicePrint.html(data,{name:'MOTOCENTRO',nit:'NIT 900006537-4'});
assert.match(discounted,/Empresa de prueba/);
assert.match(discounted,/NIT 900000001-2/);
assert.doesNotMatch(discounted,/NIT 900006537/);
assert.match(discounted,/Calle 1 # 2-3/);
assert.match(discounted,/Barrio Centro/);
assert.match(discounted,/Chasis CH-123 · Motor M-456/);
assert.match(discounted,/MOD 2027 · NEGRO/);
assert.match(discounted,/Total bruto<\/th><td>100\.000,00/);
assert.match(discounted,/Total descuento<\/th><td>10\.000,00/);
assert.match(discounted,/Total venta neta<\/th><td>90\.000,00/);
assert.match(discounted,/Total factura<\/th><td>107\.100,00/);
assert.match(discounted,/CIENTO SIETE MIL CIEN PESOS CON 00\/100/);
assert.match(discounted,/Firma autorizada/);
assert.match(discounted,/Referencia ERP FV-7/);
assert.match(discounted,/<svg[^>]*viewBox=/);
assert.match(fs.readFileSync(path.join(__dirname,'../public/sales-invoice-print.css'),'utf8'),/size:letter/);
for(const [total,expected] of [[1,'UN PESO CON 00/100'],[21.25,'VEINTIÚN PESOS CON 25/100'],[1000000,'UN MILLÓN DE PESOS CON 00/100'],[7790001,'SIETE MILLONES SETECIENTOS NOVENTA MIL UN PESOS CON 00/100']]){
  const wordsData={...data,header:{...data.header,total},articulos:[{...data.articulos[0],base:total,iva:0,precioBaseConIva:null,descuentoPorcentaje:0}]};
  assert.ok(context.window.salesInvoicePrint.html(wordsData,{}).includes(expected),expected);
}
const financing={
  header:{...data.header,total:12220000},
  articulos:[{codigo:'DR150',descripcion:'DR150 ABS',cantidad:1,precio:10990000,base:9235294.12,iva:1754705.88,ivaTarifa:19}],
  conceptos:[{codigo:'01',nombre:'FINANCIACION',valor:1230000,mostrarEnCuerpo:false,mostrarEnTotales:false}]
};
const original=JSON.stringify(financing);
const hidden=context.window.salesInvoicePrint.html(financing,{});
assert.doesNotMatch(hidden,/FINANCIACION|1\.230\.000,00|12\.220\.000,00|DOCE MILLONES/);
assert.match(hidden,/Otros conceptos<\/th><td>0,00/);
assert.match(hidden,/Total factura<\/th><td>10\.990\.000,00/);
assert.match(hidden,/DIEZ MILLONES NOVECIENTOS NOVENTA MIL PESOS CON 00\/100/);
assert.equal(JSON.stringify(financing),original,'La impresión no modifica los valores contables guardados');
for(const [body,totals] of [[true,false],[false,true],[true,true]]){
  const sample={...financing,conceptos:[{...financing.conceptos[0],mostrarEnCuerpo:body,mostrarEnTotales:totals}]};
  const html=context.window.salesInvoicePrint.html(sample,{});
  assert.equal(/<td colspan="8">FINANCIACION<\/td>/.test(html),body);
  assert.equal(/<th>FINANCIACION<\/th>/.test(html),totals);
  assert.ok(html.includes(totals?'Total factura</th><td>12.220.000,00':'Total factura</th><td>10.990.000,00'));
}
data.header.numero='<svg onload="bad">';
assert.doesNotMatch(context.window.salesInvoicePrint.html(data,{}),/<svg onload/);
console.log('Factura de venta: formato carta, datos de empresa, seriales, descuentos, IVA, conceptos y firmas verificados.');
