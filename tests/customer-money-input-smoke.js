const assert = require('node:assert/strict');
const { format, apply, erase } = require('../public/customer-money-input.js');

assert.deepEqual(format('1000'), { value: '1.000', cursor: 5 });
assert.deepEqual(format('1234567'), { value: '1.234.567', cursor: 9 });
assert.deepEqual(format('1234,56'), { value: '1.234,56', cursor: 8 });
assert.deepEqual(format('1000.5'), { value: '1.000,5', cursor: 7 });
assert.deepEqual(format('1000', 2), { value: '1.000', cursor: 3 });
assert.deepEqual(format(''), { value: '', cursor: 0 });
function deleteAt(value, cursor, key, end = cursor) {
  const input = { value, selectionStart: cursor, selectionEnd: end,
    setSelectionRange(start, finish) { this.selectionStart = start; this.selectionEnd = finish; },
    dispatchEvent() { apply(this); } };
  const event = { key, prevented: false, preventDefault() { this.prevented = true; } };
  assert.equal(erase(input, event), true);
  assert.equal(event.prevented, true);
  return { value: input.value, cursor: input.selectionStart };
}
assert.deepEqual(deleteAt('1.234', 5, 'Backspace'), { value: '123', cursor: 3 });
assert.deepEqual(deleteAt('1.000', 5, 'Backspace'), { value: '100', cursor: 3 });
assert.deepEqual(deleteAt('12.345', 3, 'Backspace'), { value: '1.345', cursor: 1 });
assert.deepEqual(deleteAt('12.345', 2, 'Delete'), { value: '1.245', cursor: 3 });
assert.deepEqual(deleteAt('1.234,56', 8, 'Backspace'), { value: '1.234,5', cursor: 7 });
console.log('Importes: puntos en vivo, decimales y posición del cursor correctos.');
