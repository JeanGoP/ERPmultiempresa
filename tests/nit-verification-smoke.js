const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const app=fs.readFileSync('public/app.js','utf8');
const company=fs.readFileSync('public/company-master.js','utf8');
const start=app.indexOf('function calculateNitVerificationDigit(');
const end=app.indexOf('function addMasterField(',start);
assert.ok(start>=0&&end>start);
const context=vm.createContext({});
vm.runInContext(app.slice(start,end),context);

assert.equal(context.calculateNitVerificationDigit('860324218'),'1');
assert.equal(context.calculateNitVerificationDigit(''),'');
assert.equal(context.calculateNitVerificationDigit('900.749.690'),'');
assert.equal(context.calculateNitVerificationDigit('ABC'),'');
assert.equal(context.calculateNitVerificationDigit('1234567890123456'),'');
assert.match(app,/form\.identification\.addEventListener\('input',updateDigit\)/);
assert.match(app,/form\.identificationType\.addEventListener\('change',updateDigit\)/);
assert.match(app,/form\.verificationDigit\.disabled=!isNit/);
assert.match(company,/nit\.addEventListener\('input',updateDigit\)/);
assert.match(company,/digit\.readOnly=true/);
console.log('DV NIT: fórmula módulo 11, actualización al digitar y bloqueo para otros documentos.');
