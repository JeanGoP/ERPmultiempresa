const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const app=fs.readFileSync('public/app.js','utf8');
const start=app.indexOf('async function loadClientMasterPage');
const end=app.indexOf('function renderClientMasterTable',start);
assert.ok(start>=0&&end>start);

const pager={hidden:true,replaceChildren(...items){this.items=items;}};
const elements={masterSearch:{value:''},masterCount:{textContent:''},masterClientPager:pager,masterDataModule:{hidden:false}};
const state={erpSession:{company:{id:3}},apiContext:{masterData:{clients:[]}},masterView:'clients'};
const page=(number,total=61)=>({items:Array.from({length:Math.min(25,Math.max(0,total-(number-1)*25))},(_,i)=>({id:(number-1)*25+i+1})),total,pagina:number,tamano:25});
let requests=[];let renders=0;
const context=vm.createContext({elements,state,clientPageRequestVersion:0,clientPageState:{page:1,total:0,size:25},
  apiRequest:async url=>{requests.push(url);return page(Number(new URL(url,'http://local').searchParams.get('pagina')));},
  apiClientToMaster:x=>x,renderMasterView:()=>{renders++;},showMasterNotice:()=>{},encodeURIComponent,
  document:{createElement:()=>({disabled:false,addEventListener(type,handler){this[type]=handler;}})}});
vm.runInContext(app.slice(start,end),context);

(async()=>{
  await context.loadClientMasterPage(1);
  assert.equal(state.apiContext.masterData.clients.length,25);
  assert.equal(context.clientPageState.total,61);
  context.renderClientPager();
  assert.equal(pager.hidden,false);
  assert.equal(pager.items[0].disabled,true);
  assert.equal(pager.items[1].textContent,'Página 1 de 3 · 61 clientes');
  assert.equal(pager.items[2].disabled,false);

  elements.masterSearch.value='Gómez 123';
  await context.loadClientMasterPage(3);
  assert.match(requests.at(-1),/pagina=3&q=G%C3%B3mez%20123/);
  assert.equal(state.apiContext.masterData.clients.length,11);
  context.renderClientPager();
  assert.equal(pager.items[0].disabled,false);
  assert.equal(pager.items[2].disabled,true);

  let resolveOld;context.apiRequest=()=>new Promise(resolve=>{resolveOld=resolve;});
  const old=context.loadClientMasterPage(1);
  context.apiRequest=async()=>page(2);
  await context.loadClientMasterPage(2);
  resolveOld(page(1));await old;
  assert.equal(context.clientPageState.page,2);
  assert.equal(state.apiContext.masterData.clients[0].id,26);
  assert.ok(renders>=3);
  console.log('Clientes: paginación, búsqueda y respuestas obsoletas correctas.');
})().catch(error=>{console.error(error);process.exitCode=1;});
