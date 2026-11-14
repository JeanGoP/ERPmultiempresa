const assert = require('node:assert/strict');
const { format } = require('../public/customer-money-input.js');

assert.deepEqual(format('1000'), { value: '1.000', cursor: 5 });
assert.deepEqual(format('1234567'), { value: '1.234.567', cursor: 9 });
assert.deepEqual(format('1234,56'), { value: '1.234,56', cursor: 8 });
assert.deepEqual(format('1000.5'), { value: '1.000,5', cursor: 7 });
assert.deepEqual(format('1000', 2), { value: '1.000', cursor: 3 });
assert.deepEqual(format(''), { value: '', cursor: 0 });
console.log('Importes: puntos en vivo, decimales y posición del cursor correctos.');
