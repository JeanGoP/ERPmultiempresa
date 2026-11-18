/* Impresión y descarga de la misma consulta que se muestra en el Kardex. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const number=value=>new Intl.NumberFormat('es-CO',{maximumFractionDigits:6}).format(value||0);
  const money=value=>new Intl.NumberFormat('es-CO',{minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const date=value=>/^\d{4}-\d{2}-\d{2}/.test(String(value||''))?String(value).slice(0,10).split('-').reverse().join('/'):value?'—':'Sin límite';
  const identifiers=unit=>[['Chasis',unit.chasis],['VIN',unit.vin],['Serial',unit.serial],['Motor',unit.motor],['Placa',unit.placa]].filter(([,value])=>value).map(([label,value])=>`${label} ${value}`).join(' · ');
  const column=(label,type,width,total=false)=>({label,type,width,total});
  function model(source,context){
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
  function html(report){
    const individual=Boolean(report.unit?.unidadSerializadaId);
    const display=(value,index)=>report.columns[index].type==='money'?money(value):report.columns[index].type==='quantity'?number(value):report.columns[index].type==='date'?date(value):esc(value||'—');
    const cell=(row,index)=>`<td class="${['money','quantity'].includes(report.columns[index].type)?'numeric':''}">${display(row[index],index)}</td>`;
    const headings=['Fecha','Movimiento / documento','Bodega','Artículo / descripción',individual?'Identificadores':'Lote / identificadores','Entrada','Salida','Costo unitario',...(individual?['Estado anterior','Estado posterior']:['Valor entrada','Valor salida','Saldo'])];
    const rows=report.rows.map(row=>`<tr>${cell(row,0)}<td><strong>${esc(String(row[1]||'').replaceAll('_',' '))}</strong><span>${esc(row[2])}</span></td>${cell(row,3)}<td><strong>${esc(row[4])}</strong><span>${esc(row[5])}</span></td><td class="identifiers">${individual?esc(row[6]||'—'):[row[6]&&`Lote ${esc(row[6])}`,esc(row[7])].filter(Boolean).join('\n')||'—'}</td>${row.slice(individual?7:8).map((value,index)=>cell(row,index+(individual?7:8))).join('')}</tr>`).join('');
    const sum=(label,unitsIndex)=>`<div><span>${esc(label)}</span><strong>${number(report.totals[unitsIndex])}</strong></div>`;
    return `<header class="kardex-print-heading"><div><p>${esc(report.company.name)}</p><h1>Kardex de inventario</h1>${report.company.nit?`<span>NIT ${esc(String(report.company.nit).replace(/^NIT\s*/i,''))}</span>`:''}<span>Valores en ${esc(report.company.currency||'COP')}</span></div><div><strong>${report.rows.length} movimientos</strong><span>Generado ${esc(new Date(report.generatedAt).toLocaleString('es-CO',{timeZone:'America/Bogota'}))}</span>${report.demo?'<span>Datos de demostración</span>':''}</div></header>
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
  function capture(){
    const company=state.erpSession?.company||{};
    return {company:{...company},from:elements.inventoryDateFrom.value,until:elements.inventoryDateTo.value,warehouseId:elements.inventoryWarehouse.value,warehouseLabel:elements.inventoryWarehouse.selectedOptions?.[0]?.textContent||'Todas las bodegas',query:elements.inventorySearch.value.trim(),unit:selectedInventoryUnit(),demo:state.runtimeMode!=='api'||!state.erpSession?.api};
  }
  const key=context=>JSON.stringify([String(context.company.id),context.from,context.until,context.warehouseId,context.query,context.unit?.unidadSerializadaId||null,context.demo]);
  function available(){return !busy&&snapshot?.report.rows.length>0&&state.inventoryView==='kardex'&&snapshot.key===key(capture());}
  function disable(message){snapshot=null;printButton.disabled=excelButton.disabled=true;status.textContent=message;}
  function reset(){busy=false;disable('');actions.hidden=true;clearPrint();}
  function loading(view){actions.hidden=view!=='kardex';disable(view==='kardex'?'Consultando movimientos…':'');}
  function loaded(rows,context){
    if(!context||state.inventoryView!=='kardex'||key(context)!==key(capture()))return;
    const report=model(rows,context);snapshot={report,key:key(context)};actions.hidden=false;
    printButton.disabled=excelButton.disabled=!report.rows.length;
    status.textContent=report.rows.length?`${report.rows.length} movimientos para imprimir o descargar`:'No hay movimientos con estos filtros';
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
      link.href=url;link.download=`kardex-${report.from||'inicio'}-${report.until||'actual'}${report.unit?'-unidad':''}.xlsx`;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
    }catch(error){status.textContent=`No fue posible descargar el Excel. ${error.message}`;}
    finally{busy=false;excelButton.disabled=!available();}
  });
  for(const input of [elements.inventorySearch,elements.inventoryDateFrom,elements.inventoryDateTo,elements.inventoryWarehouse])input.addEventListener('input',()=>{if(state.inventoryView==='kardex')disable('Actualizando filtros…');});
  window.kardexReports={capture,loading,loaded,failed:()=>disable('Consulta nuevamente para imprimir o descargar.'),reset};
})();
