/* Impresión y descarga de las consultas de Kardex y existencias. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const number=value=>new Intl.NumberFormat('es-CO',{maximumFractionDigits:6}).format(value||0);
  const money=value=>new Intl.NumberFormat('es-CO',{minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const date=value=>/^\d{4}-\d{2}-\d{2}/.test(String(value||''))?String(value).slice(0,10).split('-').reverse().join('/'):value?'—':'Sin límite';
  const identifiers=unit=>[['Chasis',unit.chasis],['VIN',unit.vin],['Serial',unit.serial],['Motor',unit.motor],['Placa',unit.placa]].filter(([,value])=>value).map(([label,value])=>`${label} ${value}`).join(' · ');
  const column=(label,type,width,total=false)=>({label,type,width,total});
  function stockModel(source,context){
    const report=JSON.parse(JSON.stringify(context));report.view='stock';report.generatedAt=new Date().toISOString();
    report.columns=[column('Bodega','text',25),column('Ubicación','text',20),column('Artículo','text',22),column('Descripción','text',44),column('Lote','text',20),column('Vencimiento','date',15),column('Existencia','quantity',16,true),column('Costo promedio','money',21),column('Valor total','money',23,true)];
    report.rows=source.map(item=>[item.bodega,item.ubicacion||'',String(item.codigo??''),item.descripcion,item.numeroLote||'',item.fechaVencimiento||'',Number(item.existencia)||0,Number(item.costoPromedio)||0,Number(item.valorTotal)||0]);
    report.totals={6:Number(report.rows.reduce((sum,row)=>sum+row[6],0).toFixed(6)),8:Number(report.rows.reduce((sum,row)=>sum+row[8],0).toFixed(4))};
    return report;
  }
  function model(source,context){
    if(context.view==='stock')return stockModel(source,context);
    const report=JSON.parse(JSON.stringify(context));
    const unitId=report.unit?.unidadSerializadaId;
    const entries=unitId?source.filter(item=>item.unidades?.some(unit=>Number(unit.unidadSerializadaId)===Number(unitId))):source;
    report.generatedAt=new Date().toISOString();
    report.columns=[column('Fecha','date',13),column('Movimiento','text',23),column('Documento','text',22),column('Bodega','text',24),column('Artículo','text',22),column('Descripción','text',42)];
    if(!unitId)report.columns.push(column('Lote','text',20));
    report.columns.push(column('Seriales e identificadores','text',48),column('Entrada','quantity',14,true),column('Salida','quantity',14,true),column('Costo unitario','money',20));
    if(unitId)report.columns.push(column('Estado anterior','text',22),column('Estado posterior','text',22));
    else report.columns.push(column('Valor entrada','money',22,true),column('Valor salida','money',22,true),column('Saldo posterior','quantity',18));
    report.rows=entries.map(item=>{
      const unit=unitId?item.unidades.find(unit=>Number(unit.unidadSerializadaId)===Number(unitId)):null;
      let units=unit?[unit]:item.unidades||[];
      if(!unit&&report.query){const query=report.query.toLocaleLowerCase('es-CO');const matching=units.filter(item=>[item.serial,item.motor,item.chasis,item.vin,item.placa].filter(Boolean).join(' ').toLocaleLowerCase('es-CO').includes(query));if(matching.length)units=matching;}
      const entrance=Number(item.entrada)||0,exit=Number(item.salida)||0;
      const values=[item.fechaContable,item.tipoMovimiento,item.numeroDocumento,item.bodega,String(item.codigo??''),item.descripcion];
      if(!unitId)values.push(item.numeroLote||'');
      values.push(units.map(identifiers).filter(Boolean).join('\n'),unitId?(entrance>0?1:0):entrance,unitId?(exit>0?1:0):exit,Number(item.costoUnitario)||0);
      if(unitId)values.push(unit.estadoAnterior||'',unit.estadoPosterior||'');
      else values.push(entrance>0?Number(item.valorMovimiento)||0:0,exit>0?Number(item.valorMovimiento)||0:0,Number(item.existenciaPosterior)||0);
      return values;
    });
    report.totals={};
    report.columns.forEach((col,index)=>{if(col.total)report.totals[index]=Number(report.rows.reduce((sum,row)=>sum+row[index],0).toFixed(col.type==='quantity'?6:4));});
    return report;
  }
  function heading(report,title,label){
    return `<header class="kardex-print-heading"><div><p>${esc(report.company.name)}</p><h1>${title}</h1>${report.company.nit?`<span>NIT ${esc(String(report.company.nit).replace(/^NIT\s*/i,''))}</span>`:''}<span>Valores en ${esc(report.company.currency||'COP')}</span></div><div><strong>${report.rows.length} ${label}</strong><span>Generado ${esc(new Date(report.generatedAt).toLocaleString('es-CO',{timeZone:'America/Bogota'}))}</span>${report.demo?'<span>Datos de demostración</span>':''}</div></header>`;
  }
  function stockHtml(report){
    return heading(report,'Existencias de inventario','registros')
      +`<section class="kardex-print-filters"><div><b>Bodega</b> ${esc(report.warehouseLabel)}</div><div><b>Búsqueda</b> ${esc(report.query||'Todos los artículos')}</div></section>`
      +`<section class="kardex-print-summary"><div><span>Referencias</span><strong>${new Set(report.rows.map(row=>row[2])).size}</strong></div><div><span>Total unidades</span><strong>${number(report.totals[6])}</strong></div><div><span>Valor de inventario</span><strong>$ ${money(report.totals[8])}</strong></div></section>`
      +`<table class="kardex-print-table stock"><thead><tr>${report.columns.map(col=>`<th scope="col">${col.label}</th>`).join('')}</tr></thead><tbody>${report.rows.map(row=>`<tr>${row.map((value,index)=>`<td class="${index>=6?'numeric':''}">${index>=7?money(value):index===6?number(value):index===5?(value?date(value):'—'):esc(value||'—')}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  }
  function html(report){
    if(report.view==='stock')return stockHtml(report);
    const individual=Boolean(report.unit?.unidadSerializadaId);
    const display=(value,index)=>report.columns[index].type==='money'?money(value):report.columns[index].type==='quantity'?number(value):report.columns[index].type==='date'?date(value):esc(value||'—');
    const cell=(row,index)=>`<td class="${['money','quantity'].includes(report.columns[index].type)?'numeric':''}">${display(row[index],index)}</td>`;
    const headings=['Fecha','Movimiento / documento','Bodega','Artículo / descripción',individual?'Identificadores':'Lote / identificadores','Entrada','Salida','Costo unitario',...(individual?['Estado anterior','Estado posterior']:['Valor entrada','Valor salida','Saldo'])];
    const rows=report.rows.map(row=>`<tr>${cell(row,0)}<td><strong>${esc(String(row[1]||'').replaceAll('_',' '))}</strong><span>${esc(row[2])}</span></td>${cell(row,3)}<td><strong>${esc(row[4])}</strong><span>${esc(row[5])}</span></td><td class="identifiers">${individual?esc(row[6]||'—'):[row[6]&&`Lote ${esc(row[6])}`,esc(row[7])].filter(Boolean).join('\n')||'—'}</td>${row.slice(individual?7:8).map((value,index)=>cell(row,index+(individual?7:8))).join('')}</tr>`).join('');
    const sum=(label,unitsIndex)=>`<div><span>${esc(label)}</span><strong>${number(report.totals[unitsIndex])}</strong></div>`;
    return `${heading(report,'Kardex de inventario','movimientos')}
      <section class="kardex-print-filters"><div><b>Desde</b> ${date(report.from)} <b>Hasta</b> ${date(report.until)}</div><div><b>Bodega</b> ${esc(report.warehouseLabel)}</div><div><b>Búsqueda</b> ${esc(report.query||'Todos los artículos')}</div>${individual?`<div class="unit"><b>Unidad</b> ${esc(identifiers(report.unit))}</div>`:''}</section>
      <section class="kardex-print-summary">${sum('Total entradas',individual?7:8)}${sum('Total salidas',individual?8:9)}${individual?'':`<div><span>Valor entradas</span><strong>$ ${money(report.totals[11])}</strong></div><div><span>Valor salidas</span><strong>$ ${money(report.totals[12])}</strong></div>`}</section>
      <table class="kardex-print-table ${individual?'individual':''}"><thead><tr>${headings.map(heading=>`<th scope="col">${heading}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table>`;
  }
  let printNode=null;
  function clearPrint(){printNode?.remove();printNode=null;document.body.classList.remove('printing-kardex');}
  function print(report){
    clearPrint();const paper=document.createElement('article');paper.id='kardexPrint';paper.innerHTML=html(report);printNode=paper;
    document.body.append(paper);document.body.classList.add('printing-kardex');
    const cleanup=()=>{window.removeEventListener('afterprint',cleanup);paper.remove();if(printNode===paper){printNode=null;document.body.classList.remove('printing-kardex');}};
    window.addEventListener('afterprint',cleanup,{once:true});
    try{window.print();}catch(error){cleanup();throw error;}
    window.setTimeout(cleanup,120000);
  }
  window.kardexReportFormats={model,html,print};

  const actions=document.querySelector('#kardexReportActions');if(!actions)return;
  const status=actions.querySelector('[data-report-status]'),printButton=actions.querySelector('[data-print-kardex]'),excelButton=actions.querySelector('[data-excel-kardex]');
  let snapshot=null,busy=false;
  const supported=view=>['kardex','stock'].includes(view);
  function capture(){
    const company=state.erpSession?.company||{};
    const stock=state.inventoryView==='stock';
    return {view:stock?'stock':'kardex',company:{...company},from:stock?'':elements.inventoryDateFrom.value,until:stock?'':elements.inventoryDateTo.value,warehouseId:elements.inventoryWarehouse.value,warehouseLabel:elements.inventoryWarehouse.selectedOptions?.[0]?.textContent||'Todas las bodegas',query:elements.inventorySearch.value.trim(),unit:stock?null:selectedInventoryUnit(),demo:state.runtimeMode!=='api'||!state.erpSession?.api};
  }
  const key=context=>JSON.stringify([context.view||'kardex',String(context.company.id),context.from,context.until,context.warehouseId,context.query,context.unit?.unidadSerializadaId||null,context.demo]);
  function available(){return !busy&&snapshot?.report.rows.length>0&&supported(state.inventoryView)&&snapshot.key===key(capture());}
  function disable(message){snapshot=null;printButton.disabled=excelButton.disabled=true;status.textContent=message;}
  function reset(){busy=false;disable('');actions.hidden=true;clearPrint();}
  function loading(view){actions.hidden=!supported(view);printButton.textContent=view==='stock'?'Imprimir existencias':'Imprimir Kardex';disable(supported(view)?view==='stock'?'Consultando existencias…':'Consultando movimientos…':'');}
  function loaded(rows,context){
    if(!context||!supported(state.inventoryView)||key(context)!==key(capture()))return;
    const report=model(rows,context);snapshot={report,key:key(context)};actions.hidden=false;
    printButton.disabled=excelButton.disabled=!report.rows.length;
    const records=report.view==='stock'?'registros':'movimientos';
    status.textContent=report.rows.length?`${report.rows.length} ${records} para imprimir o descargar`:`No hay ${records} con estos filtros`;
  }
  printButton.addEventListener('click',()=>{
    if(!available())return;
    try{print(snapshot.report);}catch(error){status.textContent=`No fue posible imprimir. ${error.message}`;}
  });
  excelButton.addEventListener('click',()=>{
    if(!available())return;
    busy=true;excelButton.disabled=true;
    try{
      const report=snapshot.report,blob=window.kardexExcel.workbook(report),url=URL.createObjectURL(blob),link=document.createElement('a');
      link.href=url;link.download=report.view==='stock'?`existencias-${new Date(report.generatedAt).toLocaleDateString('sv-SE',{timeZone:'America/Bogota'})}.xlsx`:`kardex-${report.from||'inicio'}-${report.until||'actual'}${report.unit?'-unidad':''}.xlsx`;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
    }catch(error){status.textContent=`No fue posible descargar el Excel. ${error.message}`;}
    finally{busy=false;excelButton.disabled=!available();}
  });
  for(const input of [elements.inventorySearch,elements.inventoryDateFrom,elements.inventoryDateTo,elements.inventoryWarehouse])input.addEventListener('input',()=>{if(supported(state.inventoryView)&&(state.inventoryView==='kardex'||[elements.inventorySearch,elements.inventoryWarehouse].includes(input)))disable('Actualizando filtros…');});
  window.kardexReports={capture,loading,loaded,failed:()=>disable('Consulta nuevamente para imprimir o descargar.'),reset};
})();
