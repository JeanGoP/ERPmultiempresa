/* Impresión y descarga de las consultas de inventario y antigüedad. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const number=value=>new Intl.NumberFormat('es-CO',{maximumFractionDigits:6}).format(value||0);
  const money=value=>new Intl.NumberFormat('es-CO',{minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const date=value=>/^\d{4}-\d{2}-\d{2}/.test(String(value||''))?String(value).slice(0,10).split('-').reverse().join('/'):value?'—':'Sin límite';
  const identifiers=unit=>[['Chasis',unit.chasis],['VIN',unit.vin],['Serial',unit.serial],['Motor',unit.motor],['Placa',unit.placa]].filter(([,value])=>value).map(([label,value])=>`${label} ${value}`).join(' · ');
  const column=(label,type,width,total=false)=>({label,type,width,total});
  function agingModel(source,context){
    const report=JSON.parse(JSON.stringify(context));report.view='aging';report.generatedAt=new Date().toISOString();
    report.columns=[column('Código','text',22),column('Artículo','text',42),column('Factura','text',23),column('Proveedor','text',38),column('Entrada','text',24),column('Fecha entrada (contable)','date',23),column('Bodega actual','text',26),column('Disponible','quantity',16,true),column('Edad (días)','quantity',16),column('Control','text',28)];
    report.rows=source.map(item=>[String(item.codigo??''),item.descripcion,item.factura,item.proveedor,item.entrada,item.fechaEntrada,item.bodega,Number(item.cantidad)||0,Number(item.dias)||0,item.serializado?'Por unidad serializada':'Por entrada (FIFO)']);
    report.totals={7:Number(report.rows.reduce((sum,row)=>sum+row[7],0).toFixed(6))};
    report.references=new Set(source.map(item=>item.articuloId??item.codigo)).size;
    report.averageDays=report.totals[7]?Math.round(report.rows.reduce((sum,row)=>sum+Math.max(0,row[8])*row[7],0)/report.totals[7]):0;
    report.maxDays=report.rows.reduce((max,row)=>Math.max(max,row[8]),0);
    return report;
  }
  function stockModel(source,context){
    const report=JSON.parse(JSON.stringify(context));report.view='stock';report.generatedAt=new Date().toISOString();
    report.columns=[column('Bodega','text',25),column('Ubicación','text',20),column('Artículo','text',22),column('Descripción','text',44),column('Lote','text',20),column('Vencimiento','date',15),column('Existencia','quantity',16,true),column('Costo promedio','money',21),column('Valor total','money',23,true)];
    report.rows=source.map(item=>[item.bodega,item.ubicacion||'',String(item.codigo??''),item.descripcion,item.numeroLote||'',item.fechaVencimiento||'',Number(item.existencia)||0,Number(item.costoPromedio)||0,Number(item.valorTotal)||0]);
    report.totals={6:Number(report.rows.reduce((sum,row)=>sum+row[6],0).toFixed(6)),8:Number(report.rows.reduce((sum,row)=>sum+row[8],0).toFixed(4))};
    return report;
  }
  function model(source,context){
    if(context.view==='aging')return agingModel(source,context);
    if(context.view==='stock')return stockModel(source,context);
    if(['receiving','receipt-history','receipt-issues','serials','expiry','transfers'].includes(context.view))return window.inventoryReportFormats.model(source,context);
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
    return `<header class="kardex-print-heading"><div><p>${esc(report.company.name)}</p><h1>${esc(title)}</h1>${report.company.nit?`<span>NIT ${esc(String(report.company.nit).replace(/^NIT\s*/i,''))}</span>`:''}${report.view==='aging'?'<span>Edad desde la fecha contable de la entrada original</span>':report.columns.some(col=>col.type==='money')?`<span>Valores en ${esc(report.company.currency||'COP')}</span>`:''}</div><div><strong>${report.rows.length} ${esc(label)}</strong><span>Generado ${esc(new Date(report.generatedAt).toLocaleString('es-CO',{timeZone:'America/Bogota'}))}</span>${report.demo?'<span>Datos de demostración</span>':''}</div></header>`;
  }
  function agingHtml(report){
    return heading(report,'Edad de artículos','entradas / bodegas')
      +`<section class="kardex-print-filters"><div><b>Bodega</b> ${esc(report.warehouseLabel)}</div><div><b>Búsqueda</b> ${esc(report.query||'Todos los artículos')}</div><div><b>Antigüedad</b> ${esc(report.ageBandLabel||'Todas las edades')}</div></section>`
      +`<section class="kardex-print-summary"><div><span>Referencias</span><strong>${report.references}</strong></div><div><span>Unidades disponibles</span><strong>${number(report.totals[7])}</strong></div><div><span>Edad promedio ponderada</span><strong>${number(report.averageDays)} días</strong></div><div><span>Mayor antigüedad</span><strong>${number(report.maxDays)} días</strong></div></section>`
      +`<table class="kardex-print-table aging"><thead><tr>${report.columns.map(col=>`<th scope="col">${col.label}</th>`).join('')}</tr></thead><tbody>${report.rows.map(row=>`<tr>${row.map((value,index)=>`<td class="${[7,8].includes(index)?'numeric':''}">${[7,8].includes(index)?number(value):index===5?date(value):esc(value||'—')}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  }
  function stockHtml(report){
    return heading(report,'Existencias de inventario','registros')
      +`<section class="kardex-print-filters"><div><b>Bodega</b> ${esc(report.warehouseLabel)}</div><div><b>Búsqueda</b> ${esc(report.query||'Todos los artículos')}</div></section>`
      +`<section class="kardex-print-summary"><div><span>Referencias</span><strong>${new Set(report.rows.map(row=>row[2])).size}</strong></div><div><span>Total unidades</span><strong>${number(report.totals[6])}</strong></div><div><span>Valor de inventario</span><strong>$ ${money(report.totals[8])}</strong></div></section>`
      +`<table class="kardex-print-table stock"><thead><tr>${report.columns.map(col=>`<th scope="col">${col.label}</th>`).join('')}</tr></thead><tbody>${report.rows.map(row=>`<tr>${row.map((value,index)=>`<td class="${index>=6?'numeric':''}">${index>=7?money(value):index===6?number(value):index===5?(value?date(value):'—'):esc(value||'—')}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  }
  function inventoryHtml(report){
    const display=(value,col)=>value==null||value===''?'—':col.type==='money'?money(value):col.type==='quantity'?number(value):col.type==='date'?date(value):esc(value);
    // Group related fields on paper; the workbook keeps each original column.
    const groups=report.view==='receipt-issues'
      ? [[0],[1,2,3,4,5],[6],[7,8,9,10],[11,12,13,14,15,16],[17,18],[19,20]]
      : ['receiving','receipt-history'].includes(report.view)
        ? [[0,1],[2,3,4],[6,7],[5],...report.columns.slice(8).map((_,index)=>[index+8])]
        : report.columns.map((_,index)=>[index]);
    const groupedLabels=report.view==='receipt-issues'?['Recepción','Documento / proveedor','Bodega','Artículo / unidad','Identificadores','Novedad / observación','Revisión']:['Recepción / estado','Documento / proveedor','Fechas','Bodega'];
    const receipts=['receiving','receipt-history'].includes(report.view);
    const widths=report.view==='receipt-issues'?[10,17,10,17,20,16,14]:receipts?[12,24,16,12,6,6,6,6,6,6]:groups.map(group=>Math.max(...group.map(index=>Number(report.columns[index]?.width)||16)));
    const widthSum=widths.reduce((sum,value)=>sum+value,0);
    const headerLabel=(group,index)=>receipts&&index>=4?['Líneas','Unidades','Revisadas','Conformes','Con novedad','No recibidas'][index-4]:group.length>1?groupedLabels[index]:report.columns[group[0]].label;
    const headers=groups.map((group,index)=>`<th scope="col" style="width:${(widths[index]/widthSum*100).toFixed(2)}%">${esc(headerLabel(group,index))}</th>`).join('');
    const fieldLabel=index=>receipts?({2:'Tipo',3:'Factura',6:'Factura',7:'Contable'}[index]||report.columns[index].label):report.columns[index].label;
    const rows=report.rows.map(row=>`<tr>${groups.map(group=>`<td class="${group.length===1&&['money','quantity'].includes(report.columns[group[0]].type)?'numeric':''}">${group.map(index=>group.length===1?display(row[index],report.columns[index]):`<span>${receipts&&index===0?'':`<b>${esc(fieldLabel(index))}:</b> `}${display(row[index],report.columns[index])}</span>`).join('')}</td>`).join('')}</tr>`).join('');
    const totals=report.columns.map((col,index)=>col.total?`<div><span>${esc(col.label)}</span><strong>${col.type==='money'?money(report.totals[index]):number(report.totals[index])}</strong></div>`:'').join('');
    return heading(report,report.title,report.recordLabel||'registros')
      +`<section class="kardex-print-filters"><div><b>Bodega</b> ${esc(report.warehouseLabel||'Todas las bodegas')}</div><div><b>Búsqueda</b> ${esc(report.query||'Sin filtro')}</div>${['receipt-history','receipt-issues'].includes(report.view)?`<div><b>Desde</b> ${date(report.from)} <b>Hasta</b> ${date(report.until)}</div>`:''}${report.view==='receipt-issues'?`<div><b>Novedad</b> ${esc(report.issueTypeLabel||'Todas')}</div>`:''}${report.view==='expiry'?'<div>Vencidos y próximos a vencer en 365 días</div>':''}</section>`
      +(totals?`<section class="kardex-print-summary">${totals}</section>`:'')
      +`<table class="kardex-print-table inventory-report"><thead><tr>${headers}</tr></thead><tbody>${rows}</tbody></table>`;
  }
  function html(report){
    if(report.view==='aging')return agingHtml(report);
    if(report.view==='stock')return stockHtml(report);
    if(report.view!=='kardex'&&report.title)return inventoryHtml(report);
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
  const fileNames={aging:'edad-articulos',stock:'existencias',receiving:'recepcion-fisica','receipt-history':'historial-recepciones','receipt-issues':'novedades-pendientes',serials:'seriales',expiry:'vencimientos',transfers:'traslados'};
  function download(report){
    const blob=window.kardexExcel.workbook(report),url=URL.createObjectURL(blob),link=document.createElement('a');
    link.href=url;link.download=report.view==='kardex'?`kardex-${report.from||'inicio'}-${report.until||'actual'}${report.unit?'-unidad':''}.xlsx`:`${fileNames[report.view]||'inventario'}-${new Date(report.generatedAt).toLocaleDateString('sv-SE',{timeZone:'America/Bogota'})}.xlsx`;
    document.body.append(link);try{link.click();}finally{link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
  }
  window.kardexReportFormats={model,html,print,download};

  const actions=document.querySelector('#kardexReportActions');if(!actions)return;
  const status=actions.querySelector('[data-report-status]'),printButton=actions.querySelector('[data-print-kardex]'),excelButton=actions.querySelector('[data-excel-kardex]');
  let snapshot=null,busy=false;
  const supported=view=>['kardex',...Object.keys(fileNames).filter(view=>view!=='transfers')].includes(view);
  const labels={kardex:'Kardex',stock:'existencias',aging:'edad de artículos',receiving:'recepciones','receipt-history':'historial de recepciones','receipt-issues':'novedades',serials:'seriales',expiry:'vencimientos'};
  function capture(){
    const company=state.erpSession?.company||{};
    const view=state.inventoryView,history=['kardex','receipt-history','receipt-issues'].includes(view);
    const ageBandIndex=view==='aging'&&typeof originAgeBand==='number'?originAgeBand:null;
    const ageBandLabel=ageBandIndex!==null&&typeof originAgeBands!=='undefined'?originAgeBands[ageBandIndex]?.[0]:'Todas las edades';
    return {view:supported(view)?view:'kardex',company:{...company},from:history?elements.inventoryDateFrom.value:'',until:history?elements.inventoryDateTo.value:'',warehouseId:elements.inventoryWarehouse.value,warehouseLabel:elements.inventoryWarehouse.selectedOptions?.[0]?.textContent||'Todas las bodegas',query:elements.inventorySearch.value.trim(),unit:view==='kardex'?selectedInventoryUnit():null,issueType:view==='receipt-issues'?elements.inventoryIssueType?.value||'':'',issueTypeLabel:view==='receipt-issues'?elements.inventoryIssueType?.selectedOptions?.[0]?.textContent||'Todas':'',ageBandIndex,ageBandLabel,demo:state.runtimeMode!=='api'||!state.erpSession?.api};
  }
  const key=context=>JSON.stringify([context.view||'kardex',String(context.company.id),context.from,context.until,context.warehouseId,context.query,context.unit?.unidadSerializadaId||null,context.demo,context.ageBandIndex??null,context.issueType||'']);
  function available(){return !busy&&snapshot?.report.rows.length>0&&supported(state.inventoryView)&&snapshot.key===key(capture());}
  function disable(message){snapshot=null;printButton.disabled=excelButton.disabled=true;status.textContent=message;}
  function reset(){busy=false;disable('');actions.hidden=true;clearPrint();}
  function loading(view){actions.hidden=!supported(view);printButton.textContent=`Imprimir ${labels[view]||'informe'}`;disable(supported(view)?'Consultando registros…':'');}
  function loaded(rows,context){
    if(!context||!supported(state.inventoryView)||key(context)!==key(capture()))return;
    const report=model(rows,context);snapshot={report,key:key(context)};actions.hidden=false;
    printButton.disabled=excelButton.disabled=!report.rows.length;
    const records=report.recordLabel||(report.view==='aging'?'entradas / bodegas':report.view==='stock'?'registros':'movimientos');
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
      download(snapshot.report);
    }catch(error){status.textContent=`No fue posible descargar el Excel. ${error.message}`;}
    finally{busy=false;excelButton.disabled=!available();}
  });
  for(const input of [elements.inventorySearch,elements.inventoryDateFrom,elements.inventoryDateTo,elements.inventoryWarehouse,elements.inventoryIssueType].filter(Boolean))input.addEventListener('input',()=>{if(supported(state.inventoryView)&&(['kardex','receipt-history','receipt-issues'].includes(state.inventoryView)||[elements.inventorySearch,elements.inventoryWarehouse].includes(input)))disable('Actualizando filtros…');});
  window.kardexReports={capture,loading,loaded,failed:()=>disable('Consulta nuevamente para imprimir o descargar.'),reset};
})();
