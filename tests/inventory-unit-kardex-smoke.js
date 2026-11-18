const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('public/app.js','utf8');

function node(){
  return {
    children:[],dataset:{},value:'',listeners:{},classList:{add(){}},
    textContent:'',hidden:false,disabled:false,
    append(...items){this.children.push(...items);},
    replaceChildren(...items){this.children=items;},
    setAttribute(name,value){this[name]=value;},
    addEventListener(name,listener){this.listeners[name]=listener;},
    focus(){this.focused=true;}
  };
}
const filter=node();
const elements=Object.fromEntries(['inventorySearch','inventoryWarehouse','inventoryDateFrom','inventoryDateTo',
  'inventoryStatus','inventoryNotice','inventoryTable','inventoryStats'].map(name=>[name,node()]));
const state={inventoryView:'kardex',runtimeMode:'api',erpSession:{api:true,company:{id:'3'}}};
const unit={unidadSerializadaId:17,chasis:'CHASIS-17',motor:'MOTOR-17',estadoAnterior:'DISPONIBLE',estadoPosterior:'EN_TRANSITO'};
const receipt={
  fechaContable:'2026-11-15',tipoMovimiento:'COMPRA',numeroDocumento:'ENT-17',bodega:'Montelíbano',
  codigo:'MOTO',descripcion:'Motocicleta',entrada:13,salida:0,costoUnitario:5000000,
  valorMovimiento:65000000,existenciaPosterior:20,unidades:[unit]
};
const exit={...receipt,tipoMovimiento:'TRASLADO_SALIDA',entrada:0,salida:3,unidades:[{...unit,estadoPosterior:'EN_TRANSITO'}]};
let timerId=0, timers=new Map(), requests=[];
const sandbox={
  state,elements,Intl,URLSearchParams,
  document:{
    createElement:()=>node(),
    querySelector:selector=>selector.endsWith(' button')?filter.children[1]:filter
  },
  clearTimeout:id=>timers.delete(id),
  setTimeout:callback=>{timers.set(++timerId,callback);return timerId;},
  isInventoryViewAllowed:()=>true,
  manualCurrency:amount=>`$ ${amount}`,
  emptyMessage:text=>({...node(),textContent:text}),
  buildDataTable:(headers,rows)=>({
    ...node(),headers,rows,
    tBodies:[{rows:rows.map(values=>({cells:values.map(value=>({...node(),textContent:value}))}))}]
  }),
  apiRequest:path=>new Promise(resolve=>requests.push({path,resolve})),
  showInventoryView:view=>{state.inventoryView=view;sandbox.renderInventoryUnitFilter();}
};
vm.createContext(sandbox);
vm.runInContext(source.slice(source.indexOf('function inventoryRows('),source.indexOf('async function refreshWarehouseReceiving(')),sandbox);
vm.runInContext(source.slice(source.indexOf('let inventoryRefreshVersion='),source.indexOf('function showInventoryView(')),sandbox);
vm.runInContext(source.slice(source.indexOf("elements.inventorySearch.addEventListener('input'"),source.indexOf("elements.inventoryWarehouse.addEventListener('change'")),sandbox);

async function run(){
  const general=sandbox.inventoryRows('kardex',[receipt]);
  assert.ok(general.headers.includes('Saldo'));
  assert.equal(general.rows[0][7],13);
  assert.equal(general.rows[0][10],'$ 65000000');
  const individual=sandbox.inventoryRows('kardex',[receipt,exit],17);
  assert.equal(individual.rows[0][6],1);
  assert.equal(individual.rows[1][7],1);
  assert.ok(!individual.headers.includes('Saldo')&&!individual.headers.includes('Valor'));
  assert.equal(individual.rows[1][9],'DISPONIBLE');
  assert.equal(individual.rows[1][10],'EN_TRANSITO');
  assert.equal(individual.rows[0][8],'$ 5000000');
  const safe=sandbox.inventoryRows('kardex',[{...receipt,unidades:[]}],17);
  assert.equal(safe.rows[0][6],0);

  const serialTable=sandbox.buildInventoryTable('serials',[{...receipt,...unit}],null);
  serialTable.tBodies[0].rows[0].cells[9].children[0].listeners.click();
  assert.equal(sandbox.selectedInventoryUnit().unidadSerializadaId,17);
  assert.equal(state.inventoryView,'kardex');
  const pinned=sandbox.buildInventoryTable('kardex',[receipt],null);
  const history=pinned.tBodies[0].rows[0].cells[6].children[0];
  assert.match(history['aria-label'],/CHASIS-17/);
  const multi={...receipt,unidades:[unit,{...unit,unidadSerializadaId:18,chasis:'CHASIS-18'},{...unit,unidadSerializadaId:19,chasis:'CHASIS-19'}]};
  const collapsed=sandbox.buildInventoryTable('kardex',[multi],null).tBodies[0].rows[0].cells[6].children[0];
  assert.equal(collapsed.children[0].textContent,'Ver vehículos (3)');
  assert.equal(collapsed.children.length,4);
  elements.inventorySearch.value='cHasis-18';
  const searched=sandbox.buildInventoryTable('kardex',[multi],null).tBodies[0].rows[0].cells[6];
  assert.equal(searched.children.length,1);
  assert.match(searched.children[0]['aria-label'],/CHASIS-18/);
  elements.inventorySearch.value='otra consulta';
  elements.inventoryWarehouse.value='99';
  elements.inventoryDateFrom.value='2026-11-01';
  elements.inventoryDateTo.value='2026-11-17';
  history.listeners.click();
  for(const field of ['inventorySearch','inventoryWarehouse','inventoryDateFrom','inventoryDateTo'])assert.equal(elements[field].value,'');
  assert.equal(filter.children[0].children[0].textContent,'Chasis CHASIS-17 · Motor MOTOR-17');
  assert.equal(filter.hidden,false);

  const loading=sandbox.refreshInventory();
  assert.match(requests.at(-1).path,/unidadSerializadaId=17/);
  requests.at(-1).resolve([receipt,exit,{...receipt,unidades:[{...unit,unidadSerializadaId:99}]}]);
  await loading;
  assert.equal(state.inventoryData.length,2);
  assert.equal(elements.inventoryStats.children[0].children[0].textContent,2);
  assert.equal(elements.inventoryStats.children[1].children[0].textContent,1);

  const stale=sandbox.refreshInventory();
  const old=requests.at(-1);
  const renderedTable=elements.inventoryTable.children[0];
  elements.inventorySearch.value='CHASIS-18';
  elements.inventorySearch.listeners.input();
  assert.equal(sandbox.selectedInventoryUnit(),null);
  assert.equal(filter.hidden,true);
  old.resolve([{...receipt,numeroDocumento:'STALE'}]);
  await stale;
  assert.equal(elements.inventoryTable.children[0],renderedTable);
  elements.inventorySearch.listeners.keydown({key:'Enter',preventDefault(){}});
  assert.equal(timers.size,0);
  assert.match(requests.at(-1).path,/q=CHASIS-18/);
  assert.doesNotMatch(requests.at(-1).path,/unidadSerializadaId/);
  requests.at(-1).resolve([]);
  await new Promise(resolve=>setImmediate(resolve));
  sandbox.openUnitKardex(unit,receipt);
  const oldBackend=sandbox.refreshInventory();
  const missing={...receipt};delete missing.unidades;
  requests.at(-1).resolve([missing]);
  await oldBackend;
  assert.match(elements.inventoryNotice.textContent,/Actualiza el backend/);
  assert.equal(elements.inventoryStats.children.length,0);
  assert.match(elements.inventoryTable.children[0].textContent,/No fue posible cargar/);

  sandbox.openUnitKardex(unit,receipt);
  filter.children[1].listeners.click();
  assert.equal(sandbox.selectedInventoryUnit(),null);
  assert.equal(filter.hidden,true);
  requests.at(-1).resolve([]);
  await new Promise(resolve=>setImmediate(resolve));
  sandbox.openUnitKardex(unit,receipt);
  state.erpSession.company.id='4';
  assert.equal(sandbox.selectedInventoryUnit(),null);
  const changed=sandbox.refreshInventory();
  assert.doesNotMatch(requests.at(-1).path,/unidadSerializadaId/);
  assert.match(requests.at(-1).path,/companies\/4\/inventory\/kardex/);
  requests.at(-1).resolve([]);
  await changed;
  assert.equal(filter.hidden,true);
  console.log('Kardex por unidad: cantidades individuales, estados, consulta general, seriales, filtros, empresa y respuestas obsoletas verificados.');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
