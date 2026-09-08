/* Recepción y ubicación física: nunca se modifica la fecha de entrada original. */
function originWarehouseSelect(value){
  const select=document.createElement('select');select.required=true;
  select.add(new Option('Selecciona bodega…',''));
  (state.apiContext?.warehouses||[]).filter(x=>!x.esTransito).forEach(x=>select.add(new Option(x.codigo+' · '+x.nombre,x.bodegaId)));
  select.value=String(value||'');return select;
}
function originField(title,control){const label=document.createElement('label');label.className='workflow-field';const span=document.createElement('span');span.textContent=title;label.append(span,control);return label;}
function originDialog(title,note){
  const dialog=document.createElement('dialog');dialog.className='origin-dialog';dialog.setAttribute('aria-label',title);
  const heading=document.createElement('h2');heading.textContent=title;const copy=document.createElement('p');copy.textContent=note;
  dialog.append(heading,copy);document.body.append(dialog);return dialog;
}
async function chooseReceiptWarehouses(path){
  const company=state.erpSession?.company?.id;
  const rows=await apiRequest(path);
  if(!rows.length)throw new Error('La recepción no contiene artículos.');
  if(company!==state.erpSession?.company?.id)throw new Error('La empresa activa cambió.');
  return new Promise((resolve,reject)=>{
    const dialog=originDialog('¿Dónde ingresa cada artículo?','La bodega general se aplica a todos los renglones. Después puedes cambiar cada uno. Solo al confirmar se contabiliza la entrada.');
    const form=document.createElement('form');const general=originWarehouseSelect(rows[0].bodegaId);
    form.append(originField('Bodega general',general));
    const table=buildDataTable(['Artículo','Cantidad','Bodega de llegada'],rows.map(x=>[x.codigo+' · '+x.descripcion,x.cantidad,'']));
    const selects=rows.map((x,i)=>{const select=originWarehouseSelect(x.bodegaId);select.setAttribute('aria-label','Bodega para '+x.codigo);table.querySelectorAll('tbody tr')[i].lastElementChild.append(select);return select;});
    general.addEventListener('change',()=>selects.forEach(x=>{x.value=general.value;}));
    const scroll=document.createElement('div');scroll.className='origin-scroll';scroll.append(table);form.append(scroll);
    const actions=document.createElement('div');actions.className='saved-detail-actions';
    const cancel=document.createElement('button');cancel.type='button';cancel.className='button secondary';cancel.textContent='Cancelar';cancel.onclick=()=>dialog.close();
    const confirm=document.createElement('button');confirm.type='submit';confirm.className='button primary';confirm.textContent='Confirmar bodegas y contabilizar';actions.append(cancel,confirm);form.append(actions);dialog.append(form);
    let completed=false;
    form.onsubmit=event=>{event.preventDefault();if(company!==state.erpSession?.company?.id){dialog.close();return;}completed=true;resolve(rows.map((x,i)=>({recepcionMercanciaLineaId:x.recepcionMercanciaLineaId,bodegaId:Number(selects[i].value)})));dialog.close();};
    dialog.addEventListener('close',()=>{dialog.remove();if(!completed)reject(new Error('Contabilización cancelada. El borrador se conserva.'));},{once:true});dialog.showModal();
  });
}

function appendInvoiceTransfer(panel,entry){
  if(!hasPermission('INVENTARIO.TRASLADO.DESPACHAR')||!hasPermission('INVENTARIO.TRASLADO.RECIBIR'))return;
  const button=document.createElement('button');button.type='button';button.className='button primary';button.textContent='Trasladar factura completa';
  button.onclick=()=>void openInvoiceTransfer(entry);panel.append(button);
}
async function openInvoiceTransfer(entry){
  const company=state.erpSession?.company?.id,base='/api/v1/companies/'+company;
  try{
    const rows=await apiRequest(base+'/inventory/aging?recepcionId='+entry.recepcionMercanciaId);
    if(company!==state.erpSession?.company?.id)return;
    const dialog=originDialog('Trasladar factura '+entry.numeroDocumento,'Se trasladará toda la mercancía disponible de esta entrada a una sola bodega. Las unidades que ya estén en el destino permanecen allí. Si falta mercancía o no está disponible, se rechazará toda la operación.');
    const table=buildDataTable(['Artículo','Bodega actual','Disponible','Entrada original'],rows.map(x=>[x.codigo+' · '+x.descripcion,x.bodega,x.cantidad,x.fechaEntrada]));
    const scroll=document.createElement('div');scroll.className='origin-scroll';scroll.append(table);dialog.append(scroll);
    const form=document.createElement('form');const controls=document.createElement('div');controls.className='workflow-controls';
    const destination=originWarehouseSelect();const period=document.createElement('select');period.required=true;period.add(new Option('Selecciona periodo…',''));
    (state.apiContext?.periods||[]).filter(x=>['ABIERTO','REABIERTO'].includes(x.estado)).forEach(x=>period.add(new Option(x.codigo,x.periodoInventarioId)));
    const date=document.createElement('input');date.type='date';date.required=true;date.value=new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Bogota'}).format(new Date());
    controls.append(originField('Bodega destino',destination),originField('Periodo abierto',period),originField('Fecha del traslado',date));form.append(controls);
    const error=document.createElement('p');error.className='login-error';error.setAttribute('role','alert');form.append(error);
    const actions=document.createElement('div');actions.className='saved-detail-actions';const cancel=document.createElement('button');cancel.type='button';cancel.className='button secondary';cancel.textContent='Cerrar';cancel.onclick=()=>dialog.close();
    const submit=document.createElement('button');submit.className='button primary';submit.type='submit';submit.textContent='Confirmar traslado completo';submit.disabled=!rows.length;actions.append(cancel,submit);form.append(actions);dialog.append(form);
    let operation=crypto.randomUUID(),pending=false;
    [destination,period,date].forEach(x=>x.addEventListener('change',()=>{operation=crypto.randomUUID();}));
    dialog.addEventListener('cancel',event=>{if(pending)event.preventDefault();});
    form.onsubmit=async event=>{event.preventDefault();if(company!==state.erpSession?.company?.id){dialog.close();return;}pending=true;submit.disabled=true;cancel.disabled=true;destination.disabled=period.disabled=date.disabled=true;error.textContent='';
      try{
        const result=await apiRequest(base+'/receipts/'+entry.recepcionMercanciaId+'/transfer',{method:'POST',body:JSON.stringify({bodegaDestinoId:Number(destination.value),periodoInventarioId:Number(period.value),fechaContable:date.value,operacionGuid:operation})});
        if(company===state.erpSession?.company?.id){await loadApiCompanyContext();showSuccess(result.traslados?'Factura trasladada. Se conservaron su origen, edad y cuenta por pagar.':'Toda la mercancía ya se encuentra en la bodega destino.');}
        dialog.close();
      }catch(e){error.textContent=e.message;}finally{pending=false;submit.disabled=false;cancel.disabled=false;destination.disabled=period.disabled=date.disabled=false;}
    };
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
  }catch(error){showError(error.message);}
}

let originAgeBand=null,originAgeRows=[],originAgeRequest=0;
// Extend the shared inventory refresh used by navigation and toolbar filters.
const refreshInventoryStandard=refreshInventory;
const originSearchPlaceholder=elements.inventorySearch.placeholder;
refreshInventory=async function(){
  if(state.inventoryView==='aging')return refreshInventoryAging();
  elements.inventorySearch.placeholder=originSearchPlaceholder;
  elements.inventoryTable.after(elements.inventoryOperationPanel);
  return refreshInventoryStandard();
};
const originAgeBands=[['0–30 días',0,30,'#208573'],['31–60 días',31,60,'#b99230'],['61–90 días',61,90,'#d17b3c'],['91–180 días',91,180,'#ba5551'],['Más de 180',181,Infinity,'#8a3f59']];
async function refreshInventoryAging(){
  const request=++originAgeRequest,company=state.erpSession?.company?.id;
  elements.inventorySearch.placeholder='Artículo, factura o proveedor';
  elements.breadcrumbCurrent.textContent='Edad de artículos';elements.inventoryStatus.textContent='Consultando entradas originales…';
  elements.inventoryNotice.hidden=true;elements.inventoryOperationPanel.hidden=false;
  elements.inventoryStats.replaceChildren();elements.inventoryOperationPanel.replaceChildren();elements.inventoryTable.replaceChildren(emptyMessage('Consultando entradas originales…'));
  try{
    const params=new URLSearchParams();if(elements.inventoryWarehouse.value)params.set('bodegaId',elements.inventoryWarehouse.value);if(elements.inventorySearch.value.trim())params.set('q',elements.inventorySearch.value.trim());
    const rows=await apiRequest('/api/v1/companies/'+company+'/inventory/aging?'+params);
    if(request!==originAgeRequest||state.inventoryView!=='aging'||company!==state.erpSession?.company?.id)return;
    originAgeRows=rows;renderInventoryAging();
  }catch(error){if(state.inventoryView!=='aging'||request!==originAgeRequest)return;originAgeRows=[];elements.inventoryStats.replaceChildren();elements.inventoryOperationPanel.replaceChildren();elements.inventoryTable.replaceChildren(emptyMessage(error.message));elements.inventoryStatus.textContent='No fue posible consultar';}
}
function renderInventoryAging(){
  const rows=originAgeRows,quantity=rows.reduce((s,x)=>s+x.cantidad,0);
  const average=quantity?Math.round(rows.reduce((s,x)=>s+Math.max(0,x.dias)*x.cantidad,0)/quantity):0;
  const cards=[['Unidades disponibles',quantity],['Referencias',new Set(rows.map(x=>x.articuloId)).size],['Edad promedio ponderada',average+' días'],['Mayor antigüedad',rows.reduce((max,x)=>Math.max(max,x.dias),0)+' días']];
  elements.inventoryStats.replaceChildren();cards.forEach(([label,value])=>{const card=document.createElement('article'),strong=document.createElement('strong'),span=document.createElement('span');strong.textContent=value;span.textContent=label;card.append(strong,span);elements.inventoryStats.append(card);});
  const panel=elements.inventoryOperationPanel;panel.replaceChildren();elements.inventoryTable.before(panel);
  const title=document.createElement('h2');title.textContent='Edad de artículos · desde su entrada';const note=document.createElement('p');note.textContent='Edad desde la fecha contable de la entrada original, no desde la factura ni desde un traslado. Primero las entradas más antiguas. No incluye saldos sin recepción identificable ni unidades en tránsito.';panel.append(title,note);
  const bands=document.createElement('div');bands.className='payable-bands';
  originAgeBands.forEach(([name,min,max,color],index)=>{const subset=rows.filter(x=>x.dias>=min&&x.dias<=max);const button=document.createElement('button');button.type='button';button.style.setProperty('--band-color',color);button.classList.toggle('selected',originAgeBand===index);button.setAttribute('aria-pressed',String(originAgeBand===index));
    const label=document.createElement('span'),value=document.createElement('strong'),detail=document.createElement('small');label.textContent=name;value.textContent=new Intl.NumberFormat('es-CO').format(subset.reduce((s,x)=>s+x.cantidad,0));detail.textContent=subset.length+' entradas / bodegas';button.append(label,value,detail);button.onclick=()=>{originAgeBand=originAgeBand===index?null:index;renderInventoryAging();};bands.append(button);
  });panel.append(bands);
  const filtered=originAgeBand===null?rows:rows.filter(x=>x.dias>=originAgeBands[originAgeBand][1]&&x.dias<=originAgeBands[originAgeBand][2]);
  const headings=['Código','Artículo','Factura','Proveedor','Entrada','Fecha entrada (contable)','Bodega actual','Disponible','Edad (días)','Control'];
  const values=filtered.map(x=>[x.codigo,x.descripcion,x.factura,x.proveedor,x.entrada,x.fechaEntrada,x.bodega,x.cantidad,x.dias,x.serializado?'Por unidad serializada':'Por entrada (FIFO)']);
  elements.inventoryTable.replaceChildren(buildDataTable(headings,values));elements.inventoryTable.hidden=false;
  const actions=document.createElement('div');actions.className='saved-detail-actions';const all=document.createElement('button');all.type='button';all.className='button secondary';all.textContent='Todas las edades';all.onclick=()=>{originAgeBand=null;renderInventoryAging();};
  const exportButton=document.createElement('button');exportButton.type='button';exportButton.className='button primary';exportButton.textContent='Descargar informe CSV';exportButton.disabled=!filtered.length;
  exportButton.onclick=()=>{const cell=v=>'"'+String(v??'').replace(/^[=+@-]/,"'$&").replaceAll('"','""')+'"';const blob=new Blob(['\uFEFF'+[headings,...values].map(row=>row.map(cell).join(';')).join('\r\n')],{type:'text/csv;charset=utf-8'});const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download='edad-articulos.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
  actions.append(all,exportButton);panel.append(actions);elements.inventoryStatus.textContent=filtered.length+' entradas / bodegas · '+(originAgeBand===null?'Todas las edades':originAgeBands[originAgeBand][0]);
}
