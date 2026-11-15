const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sandbox = { window:{}, Intl };
const read = filename => fs.readFileSync(path.join(__dirname, '..', 'public', filename), 'utf8');
vm.runInNewContext(read('transfer-documents.js'), sandbox);
const { receiptHtml } = sandbox.window.transferDocuments;
const origin = { codigo:'01', nombre:'Montelíbano' };
const destination = { codigo:'03', nombre:'Repuestos Caucasia' };
const transfer = {
  trasladoId:27, numero:'MOV-631049', estado:'RECIBIDO', fechaContable:'2026-11-15',
  empresa:{ razonSocial:'MOTOCENTRO S.A.', nit:'900060537', digitoVerificacion:4 },
  bodegaOrigen:origin, bodegaDestino:destination, observacion:'Solicitud <bodega>\nEntregar al encargado.',
  lineas:[
    {
      codigo:'00261', descripcion:'Motocicleta de prueba', cantidad:5,
      unidades:[{serial:'<S-1>',chasis:'CH-2027-A',vin:'VIN-2027-A',motor:'M-1'}, {serial:'S-2'}, {serial:'S-3'}, {serial:'S-4'}, {serial:'S-5'}]
    },
    {codigo:'F-201', descripcion:'Repuesto', cantidad:1.25, unidades:[]}
  ]
};

const original = receiptHtml(transfer);
assert.match(original, /Comprobante de traslado/);
assert.match(original, /MOTOCENTRO S\.A\. · NIT 900060537-4/);
assert.match(original, /MOV-631049.*15\/11\/2026/s);
assert.match(original, /Origen.*01 · Montelíbano.*Destino.*03 · Repuestos Caucasia/s);
assert.match(original, /Motocicleta de prueba.*>5<.*Serial &lt;S-1&gt; · Chasis CH-2027-A · VIN VIN-2027-A · Motor M-1/s);
assert.match(original, /Serial S-5/);
assert.match(original, /Repuesto.*>1,25</s);
assert.match(original, /Observaciones.*Solicitud &lt;bodega&gt;\nEntregar al encargado/s);
assert.doesNotMatch(original, /<bodega>/);
assert.equal((original.match(/class="transfer-quantity">5</g) || []).length, 1);

const reversal = {
  ...transfer, numero:'REV-0000000027', trasladoOriginalId:27, numeroOriginal:transfer.numero,
  bodegaOrigen:destination, bodegaDestino:origin, observacion:'Corrección de bodega.'
};
const reversed = receiptHtml(reversal);
assert.match(reversed, /Reversión de traslado/);
assert.match(reversed, /Origen.*03 · Repuestos Caucasia.*Destino.*01 · Montelíbano/s);
assert.match(reversed, /Revierte el traslado MOV-631049/);
assert.match(reversed, /Motivo de reversión.*Corrección de bodega/s);
assert.match(receiptHtml({...transfer, estado:'REVERTIDO', trasladoReversionId:28, numeroReversion:reversal.numero}), /Revertido por REV-0000000027/);
assert.match(read('transfer-documents.css'), /@page transfer-slip\s*\{\s*size:\s*8\.5in\s+5\.5in/);
assert.match(read('index.html'), /<script src="transfer-documents\.js"><\/script>/);
console.log('Comprobante de traslado: media carta, trazabilidad, seriales, cantidades y observaciones verificados.');
