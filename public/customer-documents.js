/* Facturas y recibos definitivos. La contabilidad Zeus conserva seguimiento independiente. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const today=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'America/Bogota'});
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog customer-documents-dialog';document.body.append(dialog);
  const serialDialog=document.createElement('dialog');serialDialog.className='erp-dialog customer-serial-dialog';document.body.append(serialDialog);
  const $=selector=>dialog.querySelector(selector);
  let mode='',view='create',company=0,token=0,busy=false,dirty=false,options=null,accounts=[],dimensions=null,search='',receiptFilter='',next=null;
  let operation='',client=null,lines=[],conceptLines=[],applications=[],advances=[];
  const endpoint=()=>`/api/v1/companies/${company}/${mode==='invoice'?'sales-invoices':'cash-receipts'}`;
  const current=t=>t===token&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  const notice=(message,error=false)=>{const area=$('[data-message]');if(area){area.textContent=message;area.classList.toggle('error',error);}};
  const clientLabel=c=>c?`${c.identificacion} · ${c.nombre}`:'';
  function close(force=false){if(!force&&mode==='invoice'&&view!=='create'){void create();return;}if(!force&&(busy||dirty&&!confirm('¿Salir sin contabilizar el documento?')))return;token++;dirty=false;if(serialDialog.open)serialDialog.close();dialog.close();mode='';company=0;}
  window.resetCustomerDocuments=()=>close(true);
  dialog.addEventListener('cancel',event=>{event.preventDefault();close();});
  function shell(){
    const title=mode==='invoice'?'Facturas de venta':'Recibos de caja';
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">${mode==='invoice'?'VENTAS':'TESORERÍA'} · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>${title}</h2></div><button class="dialog-close" type="button" data-close aria-label="Cerrar">×</button></div>
      <form class="customer-document-search" data-search-form><label class="customer-search-query">Buscar documentos guardados<input name="buscar" maxlength="100" placeholder="Número, cliente, identificación o comprobante Zeus" value="${esc(search)}"></label>${mode==='receipt'?`<label class="customer-search-filter">Tipo<select name="tipo"><option value="" ${receiptFilter===''?'selected':''}>Todos</option><option value="ANTICIPO" ${receiptFilter==='ANTICIPO'?'selected':''}>Anticipos</option><option value="CARTERA" ${receiptFilter==='CARTERA'?'selected':''}>Recaudos de cartera</option><option value="NORMAL" ${receiptFilter==='NORMAL'?'selected':''}>Otros recibos</option></select></label>`:''}<button class="button secondary" type="submit">Buscar</button><button type="button" class="button primary" data-new>Nuevo</button></form>
      <div class="customer-create-nav" data-create-nav hidden><button type="button" class="button secondary" data-view-list>← Ver documentos guardados</button></div>
      <p data-message role="status" aria-live="polite"></p><div data-content></div>`;
    $('[data-close]').onclick=()=>close();
    $('[data-new]').onclick=()=>{if(!busy&&(!dirty||confirm('¿Descartar los datos sin contabilizar?')))void create();};
    $('[data-view-list]').onclick=()=>{if(!busy&&(!dirty||confirm('¿Salir sin contabilizar el documento?')))void listing();};
    $('[data-search-form]').onsubmit=event=>{event.preventDefault();if(busy||dirty&&!confirm('¿Descartar el documento sin contabilizar?'))return;search=event.target.elements.buscar.value.trim();if(mode==='receipt')receiptFilter=event.target.elements.tipo.value;void listing();};
  }
  async function listing(before=null){
    const t=++token;view='list';dirty=false;shell();notice('Consultando documentos…');
    $('[data-content]').innerHTML=`<div class="egreso-toolbar"><button type="button" class="button secondary" data-return-create>← Volver a ${mode==='invoice'?'facturación':'recibos'}</button></div>`;
    $('[data-return-create]').onclick=()=>void create();
    try{
      const response=await apiRequest(endpoint()+`?q=${encodeURIComponent(search)}${before?`&antes=${before}`:''}${mode==='receipt'&&receiptFilter?`&tipo=${encodeURIComponent(receiptFilter)}`:''}`);
      if(!current(t))return;next=response.siguiente;
      $('[data-content]').innerHTML=`<div class="customer-list-heading"><strong>Documentos guardados</strong><button type="button" class="button secondary" data-return-create>← Volver a ${mode==='invoice'?'facturación':'recibos'}</button></div><div class="table-wrap"><table><thead><tr><th>Documento</th><th>Fecha</th><th>Cliente</th><th>Total</th><th>Saldo / tipo</th><th>Zeus</th></tr></thead><tbody>${response.items.map(row=>`<tr><td>${mode==='invoice'?`<button type="button" class="customer-document-link" data-view-invoice="${row.id}" aria-label="Ver factura ${esc(row.numero)}">${esc(row.numero)}</button>`:esc(row.numero||'RC-'+row.id)}</td><td>${esc(row.fecha)}</td><td>${esc(row.cliente)}</td><td>${money(row.total)}</td><td>${mode==='invoice'?money(row.saldo)+' · anticipo '+money(row.anticipo):esc(row.tipo)+(row.concepto?`<br><small>${esc(row.concepto)}</small>`:'')}</td><td>${esc(row.zeusEstado)} ${esc([row.fuente,row.documento].filter(Boolean).join(' · '))}<br><small>${esc(row.error||'')}</small>${row.zeusEstado==='RECHAZADO'?(mode==='invoice'?`<button type="button" class="button secondary" data-cost-center="${row.id}">Corregir centro de costo</button>`:'')+`<button type="button" class="button secondary" data-retry="${row.id}">Reintentar Zeus</button>`:''}${row.zeusEstado==='INCIERTO'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')?`<button type="button" class="button secondary" data-reconcile="${row.id}">Conciliar</button>`:''}</td></tr>`).join('')||'<tr><td colspan="6">No se encontraron documentos.</td></tr>'}</tbody></table></div>
        <div class="egreso-toolbar"><button type="button" class="button secondary" data-first>Primera página</button><button type="button" class="button secondary" data-next ${next?'':'disabled'}>Siguientes</button></div>`;
      notice('');$('[data-return-create]').onclick=()=>void create();$('[data-first]').onclick=()=>listing();$('[data-next]').onclick=()=>listing(next);
      dialog.querySelectorAll('[data-view-invoice]').forEach(button=>button.onclick=()=>void viewInvoice(Number(button.dataset.viewInvoice),before));
      for(const action of ['retry','reconcile'])dialog.querySelectorAll(`[data-${action}]`).forEach(button=>button.onclick=async()=>{
        if(busy)return;busy=true;button.disabled=true;
        try{const result=await apiRequest(endpoint()+`/${button.dataset[action]}/${action}`,{method:'POST'});await listing(before);if(result?.error)notice(result.error,true);}
        catch(error){if(current(t))notice(error.message,true);}finally{busy=false;}
      });
      dialog.querySelectorAll('[data-cost-center]').forEach(button=>button.onclick=()=>void correctCostCenter(Number(button.dataset.costCenter),before,t));
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function viewInvoice(id,before){
    const t=++token;view='detail';notice('Cargando factura…');
    try{
      const data=await apiRequest(endpoint()+`/${id}`);if(!current(t))return;
      const h=data.header;
      const table=(headers,rows,empty)=>`<div class="table-wrap"><table><thead><tr>${headers.map(x=>`<th>${x}</th>`).join('')}</tr></thead><tbody>${rows||`<tr><td colspan="${headers.length}">${empty}</td></tr>`}</tbody></table></div>`;
      $('[data-content]').innerHTML=`<div class="customer-list-heading"><strong>Factura ${esc(h.numero)}</strong><button type="button" class="button secondary" data-back-results>← Volver a resultados</button></div>
        <div class="customer-invoice-detail-grid"><div><small>Cliente</small><strong>${esc(h.cliente)}</strong><span>${esc(h.identificacion)}</span></div><div><small>Sucursal</small><strong>${esc(h.sucursalCodigo+' · '+h.sucursal)}</strong></div><div><small>Fecha contable</small><strong>${esc(h.fecha)}</strong></div><div><small>Zeus</small><strong>${esc(h.zeusEstado)}</strong><span>${esc([h.fuente,h.documento].filter(Boolean).join(' · '))}</span></div></div>
        ${h.error?`<p class="error">${esc(h.error)}</p>`:''}
        <h3>Artículos</h3>${table(['Artículo','Bodega','Cantidad','Precio con IVA','IVA','Total'],data.articulos.map(x=>`<tr><td>${esc(x.codigo+' · '+x.descripcion)}</td><td>${esc(x.bodegaCodigo+' · '+x.bodega)}</td><td>${esc(x.cantidad)}</td><td>${money(x.precio)}</td><td>${esc(x.ivaTarifa)} %</td><td>${money(x.base+x.iva)}</td></tr>`).join(''),'Sin artículos.')}
        <h3>Conceptos</h3>${table(['Concepto','Cuenta Zeus','Centro de costo','Valor'],data.conceptos.map(x=>`<tr><td>${esc(x.codigo+' · '+x.nombre)}</td><td>${esc(x.cuenta)}</td><td>${esc(x.centroCosto||'—')}</td><td>${money(x.valor)}</td></tr>`).join(''),'Sin conceptos.')}
        <h3>Anticipos aplicados</h3>${table(['Recibo','Fecha','Concepto','Valor aplicado'],data.anticipos.map(x=>`<tr><td>RC-${esc(x.reciboId)}</td><td>${esc(x.fecha)}</td><td>${esc(x.concepto)}</td><td>${money(x.valor)}</td></tr>`).join(''),'Sin anticipos aplicados.')}
        <h3>Plan de cuotas</h3><p class="egreso-help">Primer vencimiento: ${esc(h.primerVencimiento)} · ${esc(h.cuotas)} cuota(s) · ${h.frecuencia==='CADA_30_DIAS'?'Cada 30 días':'Mismo día de cada mes'}</p>
        ${table(['Cuota','Vencimiento','Valor','Saldo'],data.cuotas.map(x=>`<tr><td>${esc(x.numero)}</td><td>${esc(x.vence)}</td><td>${money(x.valor)}</td><td>${money(x.saldo)}</td></tr>`).join(''),'La cuota inicial cubrió toda la factura.')}
        <div class="customer-invoice-totals"><span>Total ${money(h.total)}</span><span>Anticipos ${money(h.anticipo)}</span><strong>Saldo ${money(h.saldo)}</strong></div>`;
      $('[data-back-results]').onclick=()=>void listing(before);notice('');
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function correctCostCenter(id,before,t){
    notice('Consultando los movimientos rechazados…');
    try{
      const result=await apiRequest(endpoint()+`/${id}/cost-centers`);if(!current(t))return;
      if(!result.faltantes.length){notice('No hay centros de costo obligatorios sin completar en este comprobante. Revisa el detalle del rechazo.',true);return;}
      $('[data-content]').innerHTML=`<form data-correction><fieldset><h3>Corregir centro de costo · Factura ${id}</h3><p>Se aplicará el centro elegido únicamente a estos movimientos que Zeus exige y quedaron vacíos. No cambia valores ni inventario del ERP.</p>
        <div class="table-wrap"><table><thead><tr><th>Movimiento</th><th>Cuenta Zeus</th></tr></thead><tbody>${result.faltantes.map(x=>`<tr><td>${esc(x.concepto)}</td><td>${esc(x.cuenta)}</td></tr>`).join('')}</tbody></table></div>
        <div class="egreso-grid"><label>Centro de costo Zeus<select name="centroCosto" required><option value="">Selecciona centro…</option>${result.centrosCosto.map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label></div>
        <div class="egreso-toolbar"><button type="submit" class="button primary">Guardar y reintentar Zeus</button><button type="button" class="button secondary" data-back>Volver</button></div></fieldset></form>`;
      $('[data-back]').onclick=()=>listing(before);
      $('[data-correction]').onsubmit=async event=>{
        event.preventDefault();if(busy)return;busy=true;const button=event.target.querySelector('[type="submit"]');button.disabled=true;
        try{
          await apiRequest(endpoint()+`/${id}/cost-centers`,{method:'POST',body:JSON.stringify({centroCosto:event.target.elements.centroCosto.value})});
          await apiRequest(endpoint()+`/${id}/retry`,{method:'POST'});await listing(before);
          notice(`Factura ${id}: centro de costo guardado y envío a Zeus reactivado.`);
        }catch(error){if(current(t))notice(error.message,true);}finally{busy=false;if(button.isConnected)button.disabled=false;}
      };notice('');
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function open(selected){
    const permission=selected==='invoice'?'VENTAS.FACTURA.CONTABILIZAR':'TESORERIA.RECIBO.CONTABILIZAR';
    if(!state.erpSession?.api||!hasPermission(permission)){showError('Requiere conexión al ERP y permiso para contabilizar este documento.');return;}
    if(dialog.open)return;mode=selected;company=state.erpSession.company.id;search='';receiptFilter='';dialog.showModal();await create();
  }
  document.querySelector('#cashReceiptsNav').addEventListener('click',()=>void open('receipt'));
  document.querySelector('#salesInvoicesNav').addEventListener('click',()=>void open('invoice'));
  async function create(){
    const t=++token;view='create';operation=crypto.randomUUID();client=null;lines=[];conceptLines=[];applications=[];advances=[];dirty=false;shell();$('[data-search-form]').hidden=true;$('[data-create-nav]').hidden=false;notice('Cargando catálogos…');
    try{
      const [opts,chart,dims]=await Promise.all([apiRequest(endpoint()+'/options'),mode==='invoice'?Promise.resolve([]):apiRequest(endpoint()+'/accounts'),mode==='invoice'?apiRequest(endpoint()+'/accounting-dimensions'):Promise.resolve(null)]);
      if(!current(t))return;options=opts;accounts=chart;dimensions=dims;
      if(mode==='invoice')invoiceForm();else receiptForm();notice('');
    }catch(error){if(current(t))notice(error.message,true);}
  }
  function clientField(){return `<label class="egreso-wide">Cliente<input data-client list="customerDocumentClients" placeholder="Busca por nombre o identificación…" autocomplete="off" required><input name="clienteId" type="hidden"><datalist id="customerDocumentClients"></datalist></label><small class="egreso-help" data-client-hint></small>`;}
  function setClientOptions(){
    $('#customerDocumentClients').innerHTML=(mode==='invoice'?options.clientes:options.clientes).map(c=>`<option value="${esc(clientLabel(c))}"></option>`).join('');
  }
  function wireClient(){
    setClientOptions();let timer,sequence=0;
    $('[data-client]').oninput=()=>{
      const input=$('[data-client]'),selected=options.clientes.find(c=>clientLabel(c)===input.value);
      input.setCustomValidity(selected?'':'Selecciona un cliente de los resultados.');
      if(selected){if(client?.id!==selected.id){client=selected;$('[name="clienteId"]').value=selected.id;dirty=true;void refreshClient();}return;}
      client=null;$('[name="clienteId"]').value='';applications=[];advances=[];renderAllocations();
      if(mode==='invoice')return;
      clearTimeout(timer);const t=token,request=++sequence,term=input.value.trim();if(term.length<2)return;
      timer=setTimeout(async()=>{
        try{const result=await apiRequest(endpoint()+'/options?q='+encodeURIComponent(term));if(!current(t)||request!==sequence||$('[data-client]')?.value!==term)return;options.clientes=result.clientes;setClientOptions();}
        catch(error){if(current(t))$('[data-client-hint]').textContent=error.message;}
      },250);
    };
  }
  async function refreshClient(){
    if(!client)return;const t=token,selected=client.id;
    try{const result=await apiRequest(endpoint()+`/options?clienteId=${selected}`);if(!current(t)||client?.id!==selected)return;
      if(mode==='invoice')options.anticipos=result.anticipos;else{options.facturas=result.facturas;options.anticipos=result.anticipos;}
      applications=[];advances=[];renderAllocations();$('[data-client-hint]').textContent='';
    }catch(error){if(current(t))notice('No se pudieron consultar saldos del cliente: '+error.message,true);}
  }
  function receiptForm(){
    $('[data-content]').innerHTML=`<form data-document><fieldset><h3>Nuevo recibo de caja</h3><div class="egreso-grid">
      <label>Sucursal<select name="sucursalId" required><option value="">Selecciona…</option>${options.sucursales.map(x=>`<option value="${x.id}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label>
      <label>Fecha contable<input name="fechaContable" type="date" value="${today()}" required></label>
      <label>Tipo de recibo<select name="tipo"><option value="ANTICIPO">Anticipo de cliente</option><option value="CARTERA">Recaudo de cartera</option><option value="NORMAL">Recibo normal</option></select></label>
      <label>Medio de pago<select name="medioPago"><option>TRANSFERENCIA</option><option>EFECTIVO</option><option>CHEQUE</option></select></label>
      ${clientField()}<label>Referencia / cheque<input name="referencia" maxlength="20"></label>
      <p class="egreso-help" data-account-hint></p><label class="egreso-wide">Concepto<input name="concepto" maxlength="300" required></label>
      <label data-contra-wrap class="egreso-wide" hidden>Cuenta de contrapartida en Zeus<select name="cuentaContrapartida"><option value="">Selecciona cuenta…</option>${accounts.map(a=>`<option value="${esc(a.codigo)}">${esc(a.codigo+' · '+a.nombre)}</option>`).join('')}</select></label>
      <label>Valor recibido<input name="total" type="number" min="0.01" step="0.01" required></label></div>
      <div data-allocations></div><div class="egreso-toolbar"><strong data-summary></strong><button class="button primary" type="submit">Contabilizar recibo</button></div></fieldset></form>`;
    wireClient();const f=$('[data-document]');f.oninput=()=>{dirty=true;summary();};
    f.elements.tipo.onchange=()=>{applications=[];renderAllocations();};
    f.elements.sucursalId.onchange=accountHint;f.elements.medioPago.onchange=accountHint;
    f.elements.fechaContable.onchange=()=>{applications=[];renderAllocations();dirty=true;};
    f.onsubmit=submitReceipt;renderAllocations();accountHint();
  }
  function accountHint(){
    const f=$('[data-document]');if(!f||mode!=='receipt')return;
    const account=options.cuentas.find(x=>String(x.sucursalId)===f.elements.sucursalId.value&&x.medioPago===f.elements.medioPago.value);
    $('[data-account-hint]').textContent=account?`Caja/banco automático: ${account.cuenta} · ${account.nombre}`:'Falta configurar caja/banco para esta sucursal y medio de pago.';
  }
  function renderAllocations(){
    const area=$('[data-allocations]');if(!area)return;
    if(mode==='invoice'){renderAdvances();return;}
    const f=$('[data-document]'),kind=f.elements.tipo.value;
    $('[data-contra-wrap]').hidden=kind!=='NORMAL';f.elements.cuentaContrapartida.required=kind==='NORMAL';
    f.elements.total.readOnly=kind==='CARTERA';
    if(kind!=='CARTERA'){area.innerHTML=kind==='ANTICIPO'?'<p class="egreso-help">El saldo del anticipo quedará disponible para aplicarlo a una factura futura.</p>':'<p class="egreso-help">Selecciona la cuenta contable específica para este ingreso. No modifica cartera.</p>';summary();return;}
    const selected=x=>applications.find(a=>a.facturaVentaId===x.id&&(a.facturaVentaCuotaId??null)===(x.cuotaId??null));
    area.innerHTML=`<h3>Cuotas y facturas pendientes del cliente</h3><div class="table-wrap"><table><thead><tr><th>Aplicar</th><th>Factura / cuota</th><th>Vencimiento</th><th>Saldo</th><th>Valor a recaudar</th></tr></thead><tbody>${(options.facturas||[]).map((x,i)=>{const future=x.vence>f.elements.fechaContable.value;return `<tr><td><input type="checkbox" data-pick="${i}" ${selected(x)?'checked':''} ${x.zeusEstado==='CONTABILIZADO'&&!future?'':'disabled'}></td><td>${esc(x.numero)}${x.numeroCuota?' · cuota '+x.numeroCuota:''}</td><td>${esc(x.vence)}${future?' · aún no vence':''}</td><td>${money(x.saldo)}</td><td><input type="number" data-amount="${i}" min="0.01" max="${x.saldo}" step="0.01" value="${selected(x)?.valor||x.saldo}" ${selected(x)?'':'disabled'}></td></tr>`;}).join('')||'<tr><td colspan="5">Selecciona un cliente con facturas pendientes.</td></tr>'}</tbody></table></div><small class="egreso-help">Solo se recaudan cuotas vencidas y confirmadas en Zeus. Los anticipos se registran por separado.</small>`;
    area.querySelectorAll('[data-pick]').forEach(box=>box.onchange=()=>{
      const invoice=options.facturas[Number(box.dataset.pick)];
      applications=applications.filter(a=>!(a.facturaVentaId===invoice.id&&(a.facturaVentaCuotaId??null)===(invoice.cuotaId??null)));
      if(box.checked)applications.push({facturaVentaId:invoice.id,facturaVentaCuotaId:invoice.cuotaId??null,valor:invoice.saldo});
      renderAllocations();dirty=true;
    });
    area.querySelectorAll('[data-amount]').forEach(input=>input.oninput=()=>{
      const invoice=options.facturas[Number(input.dataset.amount)],item=selected(invoice);if(item)item.valor=Number(input.value);
      summary();dirty=true;
    });summary();
  }
  function summary(){
    const f=$('[data-document]');if(!f)return;
    if(mode==='receipt'){
      if(f.elements.tipo.value==='CARTERA')f.elements.total.value=String(Math.round(applications.reduce((s,x)=>s+Math.round(x.valor*100),0))/100||'');
      $('[data-summary]').textContent='Total recibido: '+money(Number(f.elements.total.value));
    }else invoiceSummary();
  }
  async function submitReceipt(event){
    event.preventDefault();if(busy)return;const f=event.target;
    if(!client){notice('Selecciona un cliente de los resultados.',true);return;}
    const kind=f.elements.tipo.value,total=Number(f.elements.total.value);
    if(kind==='CARTERA'&&(!applications.length||Math.round(applications.reduce((s,a)=>s+a.valor,0)*100)!==Math.round(total*100))){notice('Selecciona facturas y comprueba que los abonos sumen el total.',true);return;}
    if(!options.cuentas.some(x=>String(x.sucursalId)===f.elements.sucursalId.value&&x.medioPago===f.elements.medioPago.value)){notice('Configura la caja o el banco de esta sucursal.',true);return;}
    const body={operacionGuid:operation,sucursalId:Number(f.elements.sucursalId.value),clienteId:client.id,fechaContable:f.elements.fechaContable.value,tipo:kind,medioPago:f.elements.medioPago.value,referencia:f.elements.referencia.value,concepto:f.elements.concepto.value,total,cuentaContrapartida:kind==='NORMAL'?f.elements.cuentaContrapartida.value:null,aplicaciones:kind==='CARTERA'?applications:[]};
    await send(body,'Recibo');
  }
  function invoiceForm(){
    $('[data-content]').innerHTML=`<form data-document><fieldset><h3>Nueva factura de venta</h3><p class="egreso-help">Precio unitario con IVA incluido. Esta referencia ERP no reemplaza la facturación electrónica.</p><div class="egreso-grid">
      <label>Sucursal<select name="sucursalId" required><option value="">Selecciona…</option>${options.sucursales.map(x=>`<option value="${x.id}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label>
      <label>Referencia ERP<input name="numero" maxlength="15" value="FV-${Date.now().toString(36).toUpperCase()}" required></label>
      <label>Fecha contable<input name="fechaContable" type="date" value="${today()}" required></label>
      ${clientField()}</div>
      <div class="egreso-grid"><label data-concept-warehouse hidden>Bodega para cuenta de clientes<select name="bodegaCarteraId"><option value="">Selecciona bodega…</option></select></label></div>
      <div class="egreso-toolbar"><h3>Artículos y conceptos</h3><button type="button" class="button secondary" data-add-line>Agregar artículo</button><button type="button" class="button secondary" data-add-concept>Agregar concepto</button></div>
      <div class="table-wrap"><table><thead><tr><th>Artículo / bodega</th><th>Cantidad</th><th>Precio unitario con IVA</th><th>IVA</th><th>Seriales</th><th></th></tr></thead><tbody data-lines></tbody></table></div>
      <div class="table-wrap"><table><thead><tr><th>Concepto de venta</th><th>Cuenta de ingreso Zeus</th><th>Valor</th><th>Centro de costo Zeus</th><th></th></tr></thead><tbody data-concept-lines></tbody></table></div>
      <div data-allocations></div><div class="customer-invoice-settings"><label class="customer-center-field">Centro de costo de la factura<select name="centroCostoIngreso"><option value="">Sin centro de costo</option>${(dimensions?.centrosCosto||[]).map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select><small data-general-center-hint>Se aplica a los artículos cuando Zeus lo exige.</small></label>
      <section class="customer-installment-settings"><h3>Plan de cuotas</h3><div class="customer-installment-fields"><label>Primer vencimiento<input name="vencimiento" type="date" value="${today()}" required></label><label>Número de cuotas<input name="cuotas" type="number" min="1" max="120" step="1" value="1" required></label><label>Vencimiento de las siguientes cuotas<select name="frecuenciaCuotas" required><option value="DIA_FIJO_MES">Mismo día de cada mes</option><option value="CADA_30_DIAS">Cada 30 días</option></select></label></div><small>Mensual: conserva el día del primer vencimiento. También puedes elegir cada 30 días.</small></section></div>
      <div data-installments></div>
      <div class="egreso-toolbar"><strong data-summary></strong><button class="button primary" type="submit">Emitir y contabilizar factura</button></div></fieldset></form>`;
    wireClient();const f=$('[data-document]');f.oninput=()=>{dirty=true;summary();};
    f.elements.frecuenciaCuotas.onchange=()=>{dirty=true;summary();};f.elements.vencimiento.onchange=()=>{dirty=true;summary();};
    f.elements.sucursalId.onchange=()=>{lines=[];f.elements.bodegaCarteraId.value='';addLine();};
    $('[data-add-line]').onclick=()=>addLine();$('[data-add-concept]').onclick=addConcept;f.onsubmit=submitInvoice;addLine(false);renderConcepts();renderAllocations();
  }
  function articleChoices(){
    const branch=$('[data-document]')?.elements.sucursalId.value;
    return (options.articulos||[]).filter(a=>String(a.sucursalId)===branch);
  }
  function addLine(markDirty=true){lines.push({articuloId:0,bodegaId:0,cantidad:1,precioUnitarioConIva:0,unidadesSerializadas:[]});renderLines();if(markDirty)dirty=true;}
  function renderLines(){
    const area=$('[data-lines]');if(!area)return;const choices=articleChoices();
    const f=$('[data-document]'),warehouseWrap=$('[data-concept-warehouse]');warehouseWrap.hidden=lines.length>0;
    const warehouses=(options.bodegas||[]).filter(x=>String(x.sucursalId)===f.elements.sucursalId.value);
    const selectedWarehouse=f.elements.bodegaCarteraId.value;
    f.elements.bodegaCarteraId.innerHTML='<option value="">Selecciona bodega…</option>'+warehouses.map(x=>`<option value="${x.id}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('');
    f.elements.bodegaCarteraId.value=selectedWarehouse;f.elements.bodegaCarteraId.required=lines.length===0;
    area.innerHTML=lines.map((line,index)=>{
      const item=choices.find(a=>a.id===line.articuloId&&a.bodegaId===line.bodegaId);
      return `<tr data-line="${index}"><td><select data-article required><option value="">Selecciona artículo y bodega…</option>${choices.map(a=>`<option value="${a.id}|${a.bodegaId}" ${a.id===line.articuloId&&a.bodegaId===line.bodegaId?'selected':''}>${esc(a.codigo+' · '+a.descripcion+' · '+a.bodegaCodigo+' · Disponible '+a.existencia)}</option>`).join('')}</select></td>
        <td><input data-qty type="number" min="0.000001" step="0.000001" value="${esc(line.cantidad)}" required></td>
        <td><input data-price type="number" min="0.01" step="0.01" value="${esc(line.precioUnitarioConIva||'')}" required></td>
        <td>${item?.iva==null?'IVA sin clasificar':esc(item.iva+' %')}</td>
        <td>${item?.serial?`<button type="button" class="button secondary customer-serial-trigger" data-choose-serial>Buscar seriales</button><small class="customer-serial-count">${line.unidadesSerializadas.length} de ${esc(line.cantidad)} seleccionada(s)</small>`:'—'}</td>
        <td><button type="button" class="button secondary" data-remove>Quitar</button></td></tr>`;
    }).join('');
    area.querySelectorAll('[data-line]').forEach(row=>{
      const line=lines[Number(row.dataset.line)];
      row.querySelector('[data-article]').onchange=event=>{const [id,warehouse]=event.target.value.split('|').map(Number);line.articuloId=id||0;line.bodegaId=warehouse||0;line.unidadesSerializadas=[];renderLines();dirty=true;};
      row.querySelector('[data-qty]').oninput=event=>{line.cantidad=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-price]').oninput=event=>{line.precioUnitarioConIva=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-choose-serial]')?.addEventListener('click',()=>openSerialPicker(Number(row.dataset.line)));
      row.querySelector('[data-remove]').onclick=()=>{lines.splice(Number(row.dataset.line),1);renderLines();dirty=true;};
    });updateGeneralCenterHint();summary();
  }
  function openSerialPicker(index){
    const line=lines[index],article=articleChoices().find(x=>x.id===line.articuloId&&x.bodegaId===line.bodegaId);
    if(!article){notice('Selecciona primero el artículo y la bodega.',true);return;}
    const units=new Map();
    for(const serial of options.seriales||[]){
      if(serial.articuloId!==line.articuloId||serial.bodegaId!==line.bodegaId)continue;
      if(!units.has(serial.id))units.set(serial.id,{id:serial.id,identifiers:[]});
      units.get(serial.id).identifiers.push(`${serial.tipo}: ${serial.valor}`);
    }
    const available=[...units.values()],chosen=new Set(line.unidadesSerializadas);
    const reserved=new Set(lines.flatMap((other,i)=>i===index?[]:other.unidadesSerializadas));
    const required=Number(line.cantidad);
    if(!Number.isInteger(required)||required<1){notice('Para artículos serializados, escribe primero una cantidad entera mayor que cero.',true);return;}
    serialDialog.innerHTML=`<div class="customer-serial-heading"><div><span class="dialog-kicker">UNIDADES DISPONIBLES</span><h2>${esc(article.descripcion)}</h2><small>${esc(article.bodegaCodigo)} · ${esc(article.codigo)}</small></div><button type="button" class="dialog-close" data-close-serial aria-label="Cerrar">×</button></div>
      <label class="customer-serial-search">Buscar por chasis, motor, VIN o código<input data-serial-search type="search" autocomplete="off" placeholder="Escribe parte del serial…"></label>
      <div class="customer-serial-status" data-serial-status role="status"></div><div class="customer-serial-options" data-serial-options></div>
      <div class="customer-serial-actions"><button type="button" class="button secondary" data-cancel-serial>Cancelar</button><button type="button" class="button primary" data-save-serial>Usar unidades seleccionadas</button></div>`;
    const status=serialDialog.querySelector('[data-serial-status]'),list=serialDialog.querySelector('[data-serial-options]');
    function renderOptions(){
      const term=serialDialog.querySelector('[data-serial-search]').value.trim().toLocaleLowerCase('es-CO');
      const shown=available.filter(unit=>!term||unit.identifiers.some(value=>value.toLocaleLowerCase('es-CO').includes(term))||String(unit.id).includes(term));
      status.textContent=`${chosen.size} de ${required} unidad(es) seleccionada(s) · ${shown.length} resultado(s)`;
      list.innerHTML=shown.map(unit=>`<label class="customer-serial-option"><input type="checkbox" data-unit-id="${unit.id}" ${chosen.has(unit.id)?'checked':''} ${reserved.has(unit.id)?'disabled':''}><span><strong>Unidad ${unit.id}</strong><small>${esc(unit.identifiers.join(' · '))}</small>${reserved.has(unit.id)?'<small>Ya asignada en otra línea</small>':''}</span></label>`).join('')||'<p class="egreso-help">No se encontraron unidades con ese dato.</p>';
      list.querySelectorAll('[data-unit-id]').forEach(box=>box.onchange=()=>{
        const id=Number(box.dataset.unitId);
        if(box.checked&&chosen.size>=required){box.checked=false;status.textContent=`Solo puedes elegir ${required} unidad(es).`;return;}
        if(box.checked)chosen.add(id);else chosen.delete(id);
        status.textContent=`${chosen.size} de ${required} unidad(es) seleccionada(s) · ${shown.length} resultado(s)`;
      });
    }
    serialDialog.querySelector('[data-serial-search]').oninput=renderOptions;
    serialDialog.querySelector('[data-close-serial]').onclick=()=>serialDialog.close();
    serialDialog.querySelector('[data-cancel-serial]').onclick=()=>serialDialog.close();
    serialDialog.querySelector('[data-save-serial]').onclick=()=>{
      if(chosen.size!==required){status.textContent=`Selecciona exactamente ${required} unidad(es) para continuar.`;return;}
      line.unidadesSerializadas=[...chosen];serialDialog.close();renderLines();dirty=true;
    };
    renderOptions();serialDialog.showModal();serialDialog.querySelector('[data-serial-search]').focus();
  }
  function updateGeneralCenterHint(){
    const hint=$('[data-general-center-hint]');if(!hint)return;
    const required=(dimensions?.cuentasRequierenCentroCosto||[]);
    const accounts=lines.map(x=>(options.bodegas||[]).find(b=>b.id===x.bodegaId)?.cuentaIngreso).filter(Boolean);
    const matching=accounts.filter(x=>required.includes(x));
    const control=$('[name="centroCostoIngreso"]');control.required=matching.length>0;
    hint.textContent=matching.length?`Obligatorio: la cuenta de ingreso ${[...new Set(matching)].join(', ')} exige centro de costo.`:'Se aplica a artículos y demás movimientos generales cuando Zeus lo exige.';
  }
  function addConcept(){conceptLines.push({conceptoVentaId:0,valor:0,centroCosto:''});renderConcepts();dirty=true;}
  function renderConcepts(){
    const area=$('[data-concept-lines]');if(!area)return;
    area.innerHTML=conceptLines.map((line,index)=>{const selected=(options.conceptos||[]).find(x=>x.id===line.conceptoVentaId);
      const required=(dimensions?.cuentasRequierenCentroCosto||[]).includes(selected?.cuentaIngresoZeus);
      return `<tr data-concept-line="${index}"><td><select data-concept required><option value="">Selecciona concepto…</option>${(options.conceptos||[]).map(x=>`<option value="${x.id}" ${x.id===line.conceptoVentaId?'selected':''}>${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></td><td>${esc(selected?.cuentaIngresoZeus||'—')}</td><td><input data-concept-value type="number" min="0.01" step="0.01" value="${esc(line.valor||'')}" required></td><td><select data-concept-center aria-label="Centro de costo de ${esc(selected?.nombre||'concepto')}" ${required?'required':''}><option value="">${required?'Centro de costo obligatorio':'Sin centro de costo'}</option>${(dimensions?.centrosCosto||[]).map(x=>`<option value="${esc(x.codigo)}" ${x.codigo===line.centroCosto?'selected':''}>${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></td><td><button type="button" class="button secondary" data-remove-concept>Quitar</button></td></tr>`;
    }).join('');
    area.querySelectorAll('[data-concept-line]').forEach(row=>{const line=conceptLines[Number(row.dataset.conceptLine)];
      row.querySelector('[data-concept]').onchange=event=>{line.conceptoVentaId=Number(event.target.value);renderConcepts();dirty=true;};
      row.querySelector('[data-concept-value]').oninput=event=>{line.valor=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-concept-center]').onchange=event=>{line.centroCosto=event.target.value;dirty=true;};
      row.querySelector('[data-remove-concept]').onclick=()=>{conceptLines.splice(Number(row.dataset.conceptLine),1);renderConcepts();dirty=true;};
    });summary();
  }
  function renderAdvances(){
    const area=$('[data-allocations]');if(!area)return;
    area.classList.add('customer-advance-list');
    const advancesWithoutDetails=(options.anticipos||[]).some(x=>!x.concepto||!x.fecha||!x.zeusEstado);
    area.innerHTML=`<h3>Cuota inicial / anticipos disponibles</h3><p class="egreso-help">Aplica en bloque hasta cubrir la factura o elige recibos individuales. Puedes ajustar cada importe.</p>${advancesWithoutDetails?'<p class="egreso-help">El servidor aún no entrega fecha, concepto o estado de algunos anticipos. Actualiza el backend para verlos.</p>':''}<div class="egreso-toolbar"><button type="button" class="button secondary" data-apply-advances>Aplicar anticipos disponibles</button><button type="button" class="button secondary" data-clear-advances ${advances.length?'':'disabled'}>Quitar selección</button></div><div class="table-wrap"><table><thead><tr><th>Aplicar</th><th>Recibo / fecha</th><th>Concepto</th><th>Saldo disponible</th><th>Valor a descontar</th></tr></thead><tbody>${(options.anticipos||[]).map(x=>`<tr><td><input type="checkbox" data-pick-advance="${x.id}" ${advances.some(a=>a.reciboCajaId===x.id)?'checked':''} ${x.zeusEstado&&x.zeusEstado!=='CONTABILIZADO'?'disabled':''}></td><td>RC-${x.id}<br><small>${esc(x.fecha||'—')}</small></td><td>${esc(x.concepto||'—')}</td><td>${money(x.saldo)}</td><td><input data-advance-value="${x.id}" type="number" min="0.01" max="${x.saldo}" step="0.01" value="${advances.find(a=>a.reciboCajaId===x.id)?.valor||x.saldo}" ${advances.some(a=>a.reciboCajaId===x.id)?'':'disabled'}></td></tr>`).join('')||'<tr><td colspan="5">No hay anticipos disponibles. Registra primero un recibo de caja si el cliente pagó cuota inicial.</td></tr>'}</tbody></table></div><strong data-advance-summary></strong>`;
    area.querySelector('[data-apply-advances]').onclick=()=>{
      let remaining=lines.reduce((sum,x)=>sum+Math.round(x.cantidad*x.precioUnitarioConIva*100),0)
        +conceptLines.reduce((sum,x)=>sum+Math.round(x.valor*100),0);
      if(remaining<=0){notice('Agrega primero los artículos o conceptos y sus valores para calcular cuánto anticipo aplicar.',true);return;}
      advances=[];
      for(const x of [...(options.anticipos||[])].sort((a,b)=>String(a.fecha||'').localeCompare(String(b.fecha||''))||a.id-b.id)){
        if(remaining<=0)break;
        if(x.zeusEstado&&x.zeusEstado!=='CONTABILIZADO')continue;
        const cents=Math.min(Math.round(x.saldo*100),remaining);
        if(cents>0){advances.push({reciboCajaId:x.id,valor:cents/100});remaining-=cents;}
      }
      renderAdvances();dirty=true;notice(advances.length?'Anticipos aplicados hasta el valor de la factura. Puedes ajustar cada importe antes de guardar.':'No hay anticipos disponibles para aplicar.');
    };
    area.querySelector('[data-clear-advances]').onclick=()=>{advances=[];renderAdvances();dirty=true;notice('Selección de anticipos retirada.');};
    area.querySelectorAll('[data-pick-advance]').forEach(box=>box.onchange=()=>{const id=Number(box.dataset.pickAdvance),advance=options.anticipos.find(x=>x.id===id);advances=advances.filter(x=>x.reciboCajaId!==id);if(box.checked)advances.push({reciboCajaId:id,valor:advance.saldo});renderAdvances();dirty=true;});
    area.querySelectorAll('[data-advance-value]').forEach(input=>input.oninput=()=>{const x=advances.find(a=>a.reciboCajaId===Number(input.dataset.advanceValue));if(x)x.valor=Number(input.value);summary();dirty=true;});summary();
  }
  function invoiceSummary(){
    const f=$('[data-document]');if(!f)return;
    const goods=Math.round(lines.reduce((s,x)=>s+Math.round(x.cantidad*x.precioUnitarioConIva*100),0))/100;
    const concepts=Math.round(conceptLines.reduce((s,x)=>s+Math.round(x.valor*100),0))/100;
    const advance=Math.round(advances.reduce((s,x)=>s+Math.round(x.valor*100),0))/100;
    const total=goods+concepts,balance=Math.round((total-advance)*100)/100,terms=Number(f.elements.cuotas.value);
    const cents=Math.round(balance*100),calendar=$('[data-installments]');
    $('[data-summary]').textContent=`Artículos ${money(goods)} + conceptos ${money(concepts)} = total ${money(total)} · Cuota inicial ${money(advance)} · Saldo a financiar ${money(balance)}`;
    const advanceSummary=$('[data-advance-summary]');if(advanceSummary)advanceSummary.textContent=`${advances.length} anticipo(s) seleccionado(s) · Total a aplicar: ${money(advance)}`;
    if(!Number.isInteger(terms)||terms<1||terms>120||!f.elements.vencimiento.value||cents<0){calendar.innerHTML='<p class="egreso-help">Completa el primer vencimiento y el número de cuotas para ver el calendario.</p>';return;}
    if(cents===0){calendar.innerHTML='<p class="egreso-help">No queda saldo de cartera: la cuota inicial cubre toda la factura.</p>';return;}
    if(cents<terms){calendar.innerHTML='<p class="egreso-help">El saldo no alcanza para asignar al menos $0,01 a cada cuota.</p>';return;}
    const regular=Math.floor(cents/terms),frequency=f.elements.frecuenciaCuotas.value;
    const dateAt=index=>{
      const [year,month,day]=f.elements.vencimiento.value.split('-').map(Number);
      let date;
      if(frequency==='CADA_30_DIAS')date=new Date(Date.UTC(year,month-1,day+30*index));
      else{const targetMonth=month-1+index,lastDay=new Date(Date.UTC(year,targetMonth+1,0)).getUTCDate();date=new Date(Date.UTC(year,targetMonth,Math.min(day,lastDay)));}
      return date.toISOString().slice(0,10);
    };
    calendar.innerHTML=`<h3>Calendario de cartera · ${terms} cuota(s)</h3><div class="table-wrap"><table><thead><tr><th>Cuota</th><th>Vencimiento</th><th>Valor en cuenta 13</th></tr></thead><tbody>${Array.from({length:terms},(_,i)=>`<tr><td>${i+1}</td><td>${dateAt(i)}</td><td>${money((i===terms-1?cents-regular*(terms-1):regular)/100)}</td></tr>`).join('')}</tbody></table></div>`;
  }
  async function submitInvoice(event){
    event.preventDefault();if(busy)return;const f=event.target;
    if(!client){notice('Selecciona un cliente de los resultados.',true);return;}
    if(lines.some(x=>!x.articuloId||!x.bodegaId||x.cantidad<=0||x.precioUnitarioConIva<=0)){notice('Completa artículos, cantidades y precios.',true);return;}
    if(!lines.length&&!conceptLines.length){notice('Agrega al menos un artículo o un concepto.',true);return;}
    for(const line of lines){const a=options.articulos.find(x=>x.id===line.articuloId&&x.bodegaId===line.bodegaId);
      if(a?.iva==null||a.inventario&&line.cantidad>a.existencia||a?.serial&&line.unidadesSerializadas.length!==line.cantidad){notice('Revisa el IVA, las existencias y los seriales seleccionados.',true);return;}}
    if(conceptLines.some(x=>!x.conceptoVentaId||!Number.isFinite(x.valor)||x.valor<=0)){notice('Completa los conceptos y sus valores.',true);return;}
    const required=dimensions?.cuentasRequierenCentroCosto||[];
    if(conceptLines.some(x=>required.includes(options.conceptos.find(c=>c.id===x.conceptoVentaId)?.cuentaIngresoZeus)&&!x.centroCosto)){notice('Selecciona el centro de costo de cada concepto cuya cuenta Zeus lo exija.',true);return;}
    const totalCents=lines.reduce((s,x)=>s+Math.round(x.cantidad*x.precioUnitarioConIva*100),0)+conceptLines.reduce((s,x)=>s+Math.round(x.valor*100),0);
    const financedCents=totalCents-advances.reduce((s,x)=>s+Math.round(x.valor*100),0);
    if(financedCents<0){notice('La cuota inicial no puede superar el total de la factura.',true);return;}
    if(financedCents>0&&financedCents<Number(f.elements.cuotas.value)){notice('Cada cuota debe tener al menos $0,01.',true);return;}
    const body={operacionGuid:operation,numero:f.elements.numero.value,clienteId:client.id,sucursalId:Number(f.elements.sucursalId.value),fechaContable:f.elements.fechaContable.value,vencimiento:f.elements.vencimiento.value,lineas:lines,conceptos:conceptLines,cuotas:Number(f.elements.cuotas.value),frecuenciaCuotas:f.elements.frecuenciaCuotas.value,anticipos:advances,bodegaCarteraId:lines.length?null:Number(f.elements.bodegaCarteraId.value),centroCostoIngreso:f.elements.centroCostoIngreso.value||null};
    await send(body,'Factura');
  }
  async function send(body,title){
    busy=true;const submit=$('[data-document] button[type="submit"]');submit.disabled=true;notice('Contabilizando en ERP…');
    try{const result=await apiRequest(endpoint(),{method:'POST',body:JSON.stringify(body)});dirty=false;await listing();notice(`${title} ${result.numero||result.id} contabilizado en ERP. Zeus: ${result.zeusEstado||'PENDIENTE'}. Consulta el seguimiento para confirmar el comprobante.`);}
    catch(error){notice(error.message,true);}
    finally{busy=false;if(submit.isConnected)submit.disabled=false;}
  }
})();
