const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const app=fs.readFileSync('public/app.js','utf8');
const start=app.indexOf('function paginateArticles(');
const end=app.indexOf('function renderArticleMasterPage(',start);
assert.ok(start>=0&&end>start);
const context=vm.createContext({Math});
vm.runInContext(app.slice(start,end),context);
const articles=Array.from({length:261},(_,id)=>({id:id+1}));

let page=context.paginateArticles(articles,1,20);
assert.equal(page.items.length,20);
assert.equal(page.items[0].id,1);
assert.equal(page.pages,14);
assert.equal(page.end,20);

page=context.paginateArticles(articles,14,20);
assert.equal(page.items.length,1);
assert.equal(page.items[0].id,261);
assert.equal(page.start,261);

const filtered=articles.filter(x=>x.id>250);
page=context.paginateArticles(filtered,14,20);
assert.equal(page.page,1);
assert.equal(page.total,11);
assert.equal(page.items.length,11);

page=context.paginateArticles([],1,20);
assert.equal(page.start,0);
assert.equal(page.end,0);
assert.equal(page.items.length,0);
console.log('Artículos: páginas, búsqueda y límites correctos.');
