const assert = require('node:assert/strict');
const { indexArticles, findArticles, findConcepts } = require('../public/customer-catalog-search.js');

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

const concepts = [{ id: 5, codigo: 'FIN', nombre: 'Financiación', cuentaIngresoZeus: '413502001' }];
assert.equal(findConcepts(concepts, 'financiacion').items[0].id, 5);
assert.equal(findConcepts(concepts, '413502').items[0].id, 5);
console.log('Búsqueda de venta: artículo, chasis, VIN/motor, bodega, acentos y concepto correctos.');
