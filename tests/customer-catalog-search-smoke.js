const assert = require('node:assert/strict');
const { indexArticles, findArticles, findConcepts, indexClients, findClients } = require('../public/customer-catalog-search.js');

const articles = [
  { id: 1, codigo: 'M001', descripcion: 'Motocicleta Navi 2.0', bodegaId: 10, bodegaCodigo: '01', bodega: 'Principal', sucursalId: 1 },
  { id: 2, codigo: 'R002', descripcion: 'Batería de repuesto', bodegaId: 10, bodegaCodigo: '01', bodega: 'Principal', sucursalId: 1 },
  { id: 3, codigo: 'E003', descripcion: 'Nevera', bodegaId: 20, bodegaCodigo: '02', bodega: 'Centro', sucursalId: 2 },
];
const serials = [
  { id: 101, articuloId: 1, bodegaId: 10, tipo: 'CHASIS', valor: '9FMK1715VF016690' },
  { id: 101, articuloId: 1, bodegaId: 10, tipo: 'MOTOR', valor: 'MOT-12345' },
  { id: 101, articuloId: 1, bodegaId: 10, tipo: 'VIN', valor: 'VIN-555666' },
  { id: 301, articuloId: 3, bodegaId: 20, tipo: 'SERIAL', valor: 'NEV-777' },
];
const index = indexArticles(articles, serials);

assert.equal(findArticles(index, 1, '').total, 0);
assert.equal(findArticles(index, 1, 'navi').items[0].article.id, 1);
assert.equal(findArticles(index, 1, '9FMK1715VF016690').items[0].exactSerialId, 101);
assert.equal(findArticles(index, 1, 'chasis 9fmk1715').items[0].article.id, 1);
assert.equal(findArticles(index, 1, 'mot-12345').items[0].exactSerialId, 101);
assert.equal(findArticles(index, 1, 'VIN-555666').items[0].exactSerialId, 101);
assert.equal(findArticles(index, 1, 'bateria').items[0].article.id, 2);
assert.equal(findArticles(index, 1, 'nevera').total, 0);
assert.equal(findArticles(index, 2, 'NEV-777').items[0].article.id, 3);
assert.equal(findArticles(index, 1, 'principal', 1).items.length, 1);
assert.equal(findArticles(index, 1, 'principal', 1).total, 2);

const warehouseIndex = indexArticles([
  { id: 377, codigo: '364929', descripcion: 'XR300L Tornado', inventario: true, sucursalId: 1, bodegaId: 14, bodegaCodigo: '03', bodega: 'Repuesto Caucasia', existencia: 0 },
  { id: 377, codigo: '364929', descripcion: 'XR300L Tornado', inventario: true, sucursalId: 1, bodegaId: 12, bodegaCodigo: '01', bodega: 'Montelíbano', existencia: 1 },
  { id: 377, codigo: '364929', descripcion: 'XR300L Tornado', inventario: true, sucursalId: 2, bodegaId: 20, bodegaCodigo: '04', bodega: 'Otra sucursal', existencia: 0 },
]);
assert.deepEqual(findArticles(warehouseIndex, 1, '364929').items.map(entry => entry.article.bodegaId), [12]);
assert.equal(findArticles(warehouseIndex, 1, '364929 caucasia').items[0].article.existencia, 0);
assert.equal(findArticles(warehouseIndex, 2, '364929').items[0].article.existencia, 0);

const concepts = [{ id: 5, codigo: 'FIN', nombre: 'Financiación', cuentaIngresoZeus: '413502001' }];
assert.equal(findConcepts(concepts, 'financiacion').items[0].id, 5);
assert.equal(findConcepts(concepts, '413502').items[0].id, 5);
const clients = indexClients([
  { id: 1, identificacion: '1003393939', nombre: 'Ángela Pérez' },
  { id: 2, identificacion: '200123', nombre: 'Pedro Angarita' },
  { id: 3, identificacion: '300456', nombre: 'María Torres' },
]);
assert.equal(findClients(clients, 'a').total, 0);
assert.equal(findClients(clients, 'angela').items[0].id, 1);
assert.equal(findClients(clients, '100339').items[0].id, 1);
assert.equal(findClients(clients, 'torres').items[0].id, 3);
assert.equal(findClients(clients, 'ang').total, 2);
assert.equal(findClients(clients, 'ang', 1).items.length, 1);
console.log('Búsqueda de venta: artículos, seriales, conceptos y clientes correctos.');
