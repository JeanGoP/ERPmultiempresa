/* Facturas y recibos definitivos. La contabilidad Zeus conserva seguimiento independiente. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const today=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'America/Bogota'});
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog customer-documents-dialog';document.body.append(dialog);
  const serialDialog=document.createElement('dialog');serialDialog.className='erp-dialog customer-serial-dialog';document.body.append(serialDialog);
  const $=selector=>dialog.querySelector(selector);
  let mode='',view='create',company=0,token=0,busy=false,dirty=false,options=null,accounts=[],dimensions=null,dimensionsError='',search='',receiptFilter='',next=null;
  let operation='',client=null,lines=[],conceptLines=[],applications=[],advances=[],extraInstallments=[];
  const endpoint=()=>`/api/v1/companies/${company}/${mode==='invoice'?'sales-invoices':'cash-receipts'}`;
  const current=t=>t===token&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  const notice=(message,error=false)=>{const area=$('[data-message]');if(area){area.textContent=message;area.classList.toggle('error',error);}};
  const clientLabel=c=>c?`${c.identificacion} · ${c.nombre}`:'';
  const portfolioLabel=value=>({MOTO:'Motos',OTROS:'Otros artículos',MIXTA:'Mixta',SIN_CLASIFICAR:'Sin clasificar'})[value]||'Sin clasificar';
  function close(force=false){if(!force&&mode==='invoice'&&view!=='create'&&view!=='approvals'&&hasPermission('VENTAS.FACTURA.CONTABILIZAR')){void create();return;}if(!force&&(busy||dirty&&!confirm('¿Salir sin contabilizar el documento?')))return;token++;dirty=false;if(serialDialog.open)serialDialog.close();dialog.close();mode='';company=0;}
  window.resetCustomerDocuments=()=>close(true);
  dialog.addEventListener('cancel',event=>{event.preventDefault();close();});
  function shell(){
    const title=mode==='invoice'?'Facturas de venta':'Recibos de caja';
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">${mode==='invoice'?'VENTAS':'TESORERÍA'} · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>${title}</h2></div><button class="dialog-close" type="button" data-close aria-label="Cerrar">×</button></div>
      <form class="customer-document-search" data-search-form><label class="customer-search-query">Buscar documentos guardados<input name="buscar" maxlength="100" placeholder="Número, cliente, identificación o comprobante Zeus" value="${esc(search)}"></label>${mode==='receipt'?`<label class="customer-search-filter">Tipo<select name="tipo"><option value="" ${receiptFilter===''?'selected':''}>Todos</option><option value="ANTICIPO" ${receiptFilter==='ANTICIPO'?'selected':''}>Anticipos</option><option value="CARTERA" ${receiptFilter==='CARTERA'?'selected':''}>Recaudos de cartera</option><option value="NORMAL" ${receiptFilter==='NORMAL'?'selected':''}>Otros recibos</option></select></label>`:''}<button class="button secondary" type="submit">Buscar</button>${mode==='invoice'?'<button type="button" class="button secondary" data-approvals>Autorizaciones</button>':''}<button type="button" class="button primary" data-new>Nuevo</button></form>
      <div class="customer-create-nav" data-create-nav hidden><button type="button" class="button secondary" data-view-list>← Ver documentos guardados</button>${mode==='invoice'?'<button type="button" class="button secondary" data-approvals>Autorizaciones</button>':''}</div>
      <p data-message role="status" aria-live="polite"></p><div data-content></div>`;
    $('[data-close]').onclick=()=>close();
    $('[data-new]').onclick=()=>{if(!busy&&(!dirty||confirm('¿Descartar los datos sin contabilizar?')))void create();};
    $('[data-view-list]').onclick=()=>{if(!busy&&(!dirty||confirm('¿Salir sin contabilizar el documento?')))void listing();};
    dialog.querySelectorAll('[data-approvals]').forEach(button=>button.onclick=()=>{if(!busy&&(!dirty||confirm('¿Salir sin guardar los datos de esta factura?')))void approvalListing();});
    $('[data-search-form]').onsubmit=event=>{event.preventDefault();if(busy||dirty&&!confirm('¿Descartar el documento sin contabilizar?'))return;search=event.target.elements.buscar.value.trim();if(mode==='receipt')receiptFilter=event.target.elements.tipo.value;void listing();};
  }
  async function approvalListing(){
    const t=++token;view='approvals';dirty=false;shell();$('[data-search-form]').hidden=true;$('[data-create-nav]').hidden=true;notice('Consultando autorizaciones…');
    $('[data-content]').innerHTML='<p>Consultando solicitudes…</p>';
    try{
      const result=await apiRequest(`/api/v1/companies/${company}/sales-price-approvals`);if(!current(t))return;
      $('[data-content]').innerHTML=`<div class="customer-list-heading"><strong>Autorizaciones de precio y descuento</strong>${hasPermission('VENTAS.FACTURA.CONTABILIZAR')?'<button type="button" class="button secondary" data-back-create>← Volver a facturación</button>':''}</div><p class="egreso-help">La aprobación corresponde a los valores exactos solicitados. Solo quien la solicitó puede emitir la factura; si cambia el costo o la política, debe hacer otra solicitud.</p><div class="table-wrap"><table><thead><tr><th>Solicitud / factura</th><th>Excepción</th><th>Motivo</th><th>Estado</th><th>Acción</th></tr></thead><tbody>${result.items.map(x=>`<tr><td>#${x.id} · ${esc(x.numero)}<small>${esc(x.cliente)} · ${money(x.totalEstimado)}<br>${esc(x.cuotas)} cuota(s), primer vencimiento ${esc(x.primerVencimiento)} · solicitó usuario ${esc(x.solicitadoPor)}</small></td><td>${(x.excepciones||[]).map(e=>`<div>${e.tipo==='BAJO_COSTO'?'Bajo costo':'Descuento fuera de política'} · ${esc(e.articulo||e.articuloId)}<br><small>Precio ${money(e.precio)} · mínimo ${money(e.umbral)}</small></div>`).join('')}</td><td>${esc(x.motivo)}</td><td>${esc(x.estado)}${x.respuesta?`<small>${esc(x.respuesta)}</small>`:''}</td><td>${x.estado==='PENDIENTE'&&x.puedeResolver?`<button type="button" class="button secondary" data-approve="${x.id}">Aprobar</button> <button type="button" class="button secondary" data-reject="${x.id}">Rechazar</button>`:''}${x.estado==='APROBADA'&&x.propia?`<button type="button" class="button primary" data-issue="${x.id}">Emitir factura</button>`:''}${x.facturaId&&hasPermission('VENTAS.FACTURA.CONTABILIZAR')?`<button type="button" class="button secondary" data-issued="${x.facturaId}">Ver factura</button>`:''}</td></tr>`).join('')||'<tr><td colspan="5">No hay solicitudes de autorización.</td></tr>'}</tbody></table></div>`;
      $('[data-back-create]')?.addEventListener('click',()=>void create());notice('');
      dialog.querySelectorAll('[data-issued]').forEach(button=>button.onclick=()=>void viewInvoice(Number(button.dataset.issued),null));
      for(const action of ['approve','reject','issue'])dialog.querySelectorAll(`[data-${action}]`).forEach(button=>button.onclick=async()=>{
        if(busy)return;const id=Number(button.dataset[action]);let response='';
        if(action==='approve'){if(!confirm(`¿Aprobar la solicitud #${id} con los precios exactos mostrados?`))return;response=prompt('Observación de la aprobación (opcional):','')||'';}
        if(action==='reject'){response=prompt('Motivo del rechazo:','')?.trim()||'';if(!response)return;}
        if(action==='issue'&&!confirm(`¿Emitir la factura aprobada en la solicitud #${id}? Se verificarán de nuevo inventario, costo y descuento.`))return;
        busy=true;button.disabled=true;
        try{
          const result=await apiRequest(`/api/v1/companies/${company}/sales-price-approvals/${id}/${action}`,{method:'POST',...(action==='issue'?{}:{body:JSON.stringify({respuesta:response})})});
          await approvalListing();notice(action==='issue'?`Factura ${result.id} contabilizada en ERP; revisa su estado en Zeus.`:`Solicitud ${action==='approve'?'aprobada':'rechazada'}.`);
        }catch(error){if(current(t))notice(error.message,true);}finally{busy=false;if(button.isConnected)button.disabled=false;}
      });
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function listing(before=null){
    const t=++token;view='list';dirty=false;shell();notice('Consultando documentos…');
    $('[data-content]').innerHTML=`<div class="egreso-toolbar"><button type="button" class="button secondary" data-return-create>← Volver a ${mode==='invoice'?'facturación':'recibos'}</button></div>`;
    $('[data-return-create]').onclick=()=>void create();
    try{
      const response=await apiRequest(endpoint()+`?q=${encodeURIComponent(search)}${before?`&antes=${before}`:''}${mode==='receipt'&&receiptFilter?`&tipo=${encodeURIComponent(receiptFilter)}`:''}`);
      if(!current(t))return;next=response.siguiente;
      $('[data-content]').innerHTML=`<div class="customer-list-heading"><strong>Documentos guardados</strong><button type="button" class="button secondary" data-return-create>← Volver a ${mode==='invoice'?'facturación':'recibos'}</button></div><div class="table-wrap"><table><thead><tr><th>Documento</th><th>Fecha</th><th>Cliente</th><th>Total</th><th>Saldo / tipo</th><th>Zeus</th></tr></thead><tbody>${response.items.map(row=>`<tr><td>${mode==='invoice'?`<button type="button" class="customer-document-link" data-view-invoice="${row.id}" aria-label="Ver factura ${esc(row.numero)}">${esc(row.numero)}</button>`:esc(row.numero||'RC-'+row.id)}</td><td>${esc(row.fecha)}</td><td>${esc(row.cliente)}</td><td>${money(row.total)}</td><td>${mode==='invoice'?money(row.saldo)+' · anticipo '+money(row.anticipo)+'<br><small>'+esc(portfolioLabel(row.claseCartera))+'</small>':esc(row.tipo)+(row.tipo==='ANTICIPO'?` · disponible ${money(row.saldoAnticipo)}`:'')+(row.concepto?`<br><small>${esc(row.concepto)}</small>`:'')}</td><td>${esc(row.zeusEstado)} ${esc([row.fuente,row.documento].filter(Boolean).join(' · '))}<br><small>${esc(row.error||'')}</small>${row.zeusEstado==='RECHAZADO'?(mode==='invoice'?`<button type="button" class="button secondary" data-cost-center="${row.id}">Corregir centro de costo</button>`:'')+`<button type="button" class="button secondary" data-retry="${row.id}">Reintentar Zeus</button>`:''}${row.zeusEstado==='INCIERTO'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')?`<button type="button" class="button secondary" data-reconcile="${row.id}">Conciliar</button>`:''}</td></tr>`).join('')||'<tr><td colspan="6">No se encontraron documentos.</td></tr>'}</tbody></table></div>
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
      const [data,notes]=await Promise.all([apiRequest(endpoint()+`/${id}`),apiRequest(endpoint()+`/${id}/refinancings`)]);if(!current(t))return;
      const h=data.header;
      const table=(headers,rows,empty)=>`<div class="table-wrap"><table><thead><tr>${headers.map(x=>`<th>${x}</th>`).join('')}</tr></thead><tbody>${rows||`<tr><td colspan="${headers.length}">${empty}</td></tr>`}</tbody></table></div>`;
      $('[data-content]').innerHTML=`<div class="customer-list-heading"><strong>Factura ${esc(h.numero)}</strong><button type="button" class="button secondary" data-back-results>← Volver a resultados</button></div>
        <div class="customer-invoice-detail-grid"><div><small>Cliente</small><strong>${esc(h.cliente)}</strong><span>${esc(h.identificacion)}</span></div><div><small>Sucursal</small><strong>${esc(h.sucursalCodigo+' · '+h.sucursal)}</strong></div><div><small>Cartera / fecha</small><strong>${esc(portfolioLabel(h.claseCartera))}</strong><span>${esc(h.fecha)}</span></div><div><small>Zeus</small><strong>${esc(h.zeusEstado)}</strong><span>${esc([h.fuente,h.documento].filter(Boolean).join(' · '))}</span></div></div>
        <form class="customer-reclassify" data-reclassify><label>Clasificar esta factura<select name="claseCartera" required><option value="">Sin clasificar</option><option value="MOTO" ${h.claseCartera==='MOTO'?'selected':''}>Motos</option><option value="OTROS" ${h.claseCartera==='OTROS'?'selected':''}>Otros artículos</option><option value="MIXTA" ${h.claseCartera==='MIXTA'?'selected':''}>Mixta</option></select></label><button type="submit" class="button secondary">Guardar clasificación</button><small>No cambia valores ni movimientos en Zeus.</small></form>
        ${h.observacion?`<p class="customer-invoice-observation"><strong>Observación:</strong> ${esc(h.observacion)}</p>`:''}
        ${h.error?`<p class="error">${esc(h.error)}</p>`:''}
        <h3>Artículos</h3>${table(['Artículo','Bodega','Cantidad','Precio con IVA','IVA','Total'],data.articulos.map(x=>`<tr><td>${esc(x.codigo+' · '+x.descripcion)}</td><td>${esc(x.bodegaCodigo+' · '+x.bodega)}</td><td>${esc(x.cantidad)}</td><td>${money(x.precio)}</td><td>${esc(x.ivaTarifa)} %</td><td>${money(x.base+x.iva)}</td></tr>`).join(''),'Sin artículos.')}
        <h3>Conceptos</h3>${table(['Concepto','Cuenta Zeus','Centro de costo','Valor'],data.conceptos.map(x=>`<tr><td>${esc(x.codigo+' · '+x.nombre)}</td><td>${esc(x.cuenta)}</td><td>${esc(x.centroCosto||'—')}</td><td>${money(x.valor)}</td></tr>`).join(''),'Sin conceptos.')}
        <h3>Anticipos aplicados</h3>${table(['Recibo','Fecha','Concepto','Valor aplicado'],data.anticipos.map(x=>`<tr><td>RC-${esc(x.reciboId)}</td><td>${esc(x.fecha)}</td><td>${esc(x.concepto)}</td><td>${money(x.valor)}</td></tr>`).join(''),'Sin anticipos aplicados.')}
        <h3>Plan de cuotas</h3><p class="egreso-help">Primer vencimiento: ${esc(h.primerVencimiento)} · ${esc(h.cuotas)} cuota(s) · ${h.frecuencia==='PERSONALIZADA'?'Fechas pactadas en nota de cartera':h.frecuencia==='CADA_30_DIAS'?'Cada 30 días':'Mismo día de cada mes'}</p>
        ${table(['Cuota','Tipo','Vencimiento','Valor','Saldo'],data.cuotas.map(x=>`<tr><td>${esc(x.numero)}</td><td>${x.tipo==='EXTRA'?'Extra':'Ordinaria'}</td><td>${esc(x.vence)}</td><td>${money(x.valor)}</td><td>${money(x.saldo)}</td></tr>`).join(''),'La cuota inicial cubrió toda la factura.')}
        <div class="customer-invoice-totals"><span>Total ${money(h.total)}</span><span>Anticipos ${money(h.anticipo)}</span><strong>Saldo ${money(h.saldo)}</strong></div>
        <section class="customer-refinancing"><div class="customer-list-heading"><strong>Notas de cartera y refinanciaciones</strong>${h.zeusEstado==='CONTABILIZADO'&&h.saldo>0&&(!notes.items.length||['CONTABILIZADO','CANCELADO'].includes(notes.items[0].zeusEstado))?'<button type="button" class="button secondary" data-new-refinancing>Refinanciar cartera</button>':''}</div>
          ${notes.items.length?table(['Fecha / plan','Saldo anterior','Nuevo saldo','Incremento','Estado Zeus','Acción'],notes.items.map(n=>`<tr><td>${esc(n.fecha)}<small>${esc(n.motivo)}</small><details><summary>Comparar cuotas</summary><strong>Anteriores</strong>${(n.planAnterior||[]).map(x=>`<small>${esc(x.vencimiento)} · ${money(x.saldo)}</small>`).join('')}<strong>Nuevas</strong>${(n.planNuevo||[]).map(x=>`<small>${esc(x.vencimiento)} · ${money(x.valor)}</small>`).join('')}</details></td><td>${money(n.saldoAnterior)}</td><td>${money(n.nuevoSaldo)}</td><td>${money(n.incremento)}${n.cuentaIngreso?`<small>Ingreso ${esc(n.cuentaIngreso)}${n.centroCosto?` · CC ${esc(n.centroCosto)}`:''}</small>`:''}</td><td>${esc(n.zeusEstado)}<small>${esc([n.fuente,n.documento].filter(Boolean).join(' · '))}</small><small>${esc(n.error||'')}</small></td><td>${n.zeusEstado==='POR_APROBAR'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')?`<button type="button" class="button secondary" data-note-approve="${n.id}">Aprobar</button>`:''}${n.zeusEstado==='RECHAZADO'?`<button type="button" class="button secondary" data-note-retry="${n.id}">Reintentar</button>`:''}${['POR_APROBAR','RECHAZADO'].includes(n.zeusEstado)?` <button type="button" class="button secondary" data-note-cancel="${n.id}">Descartar</button>`:''}${n.zeusEstado==='INCIERTO'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')?`<button type="button" class="button secondary" data-note-reconcile="${n.id}">Conciliar</button>`:''}</td></tr>`).join(''),'Sin notas.'):''}
          <div data-refinancing-form></div></section>`;
      $('[data-back-results]').onclick=()=>void listing(before);notice('');
      $('[data-reclassify]').onsubmit=async event=>{event.preventDefault();const button=event.target.querySelector('button');button.disabled=true;
        try{await apiRequest(endpoint()+`/${id}/portfolio-class`,{method:'PUT',body:JSON.stringify({claseCartera:event.target.elements.claseCartera.value})});if(current(t)){await viewInvoice(id,before);notice('Clasificación guardada.');}}
        catch(error){if(current(t))notice(error.message,true);}finally{if(button.isConnected)button.disabled=false;}
      };
      $('[data-new-refinancing]')?.addEventListener('click',()=>void openRefinancing(id,before,t,data));
      for(const action of ['approve','retry','cancel','reconcile'])dialog.querySelectorAll(`[data-note-${action}]`).forEach(button=>button.onclick=async()=>{
        if(busy)return;if(action==='approve'&&!confirm('¿Aprobar el envío de esta nota a Zeus? Debes ser una persona distinta de quien la preparó.'))return;
        if(action==='cancel'&&!confirm('¿Descartar esta nota sin enviar o rechazada? La cartera original permanecerá intacta.'))return;
        busy=true;button.disabled=true;
        try{
          const noteId=Number(button.dataset['note'+action[0].toUpperCase()+action.slice(1)]);
          const url=action==='cancel'?endpoint()+`/${id}/refinancings/${noteId}/cancel`:`/api/v1/companies/${company}/portfolio-notes/${noteId}/${action}`;
          await apiRequest(url,{method:'POST'});await viewInvoice(id,before);
        }catch(error){notice(error.message,true);}finally{busy=false;}
      });
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function openRefinancing(id,before,t,data){
    notice('Consultando cuentas de Zeus…');
    try{
      const options=await apiRequest(endpoint()+'/refinancing-options');if(!current(t))return;
      const old=data.cuotas.filter(x=>Number(x.saldo)>0),first=old[0];
      if(!first){notice('La factura no tiene cuotas abiertas para refinanciar.',true);return;}
      const host=$('[data-refinancing-form]');
      host.innerHTML=`<form data-refinance><h3>Nueva nota de cartera</h3><p class="egreso-help">Se acreditarán las cuotas abiertas y se crearán los nuevos vencimientos. El plan actual permanece vigente hasta que Zeus confirme la nota. Por ahora no se permiten reducciones del saldo.</p>
        <div class="egreso-grid"><label>Fecha contable<input type="date" name="fechaContable" value="${today()}" required></label><label class="egreso-wide">Motivo<input name="motivo" maxlength="300" placeholder="Motivo de la refinanciación" required></label></div>
        <div class="table-wrap"><table><thead><tr><th>Nuevo vencimiento</th><th>Valor</th><th>Tipo</th><th></th></tr></thead><tbody data-new-dues></tbody></table></div>
        <button type="button" class="button secondary" data-add-due>Agregar cuota</button>
        <div class="egreso-grid"><label>Cuenta de ingreso para el incremento<select name="cuentaIngresoZeus"><option value="">Sin incremento</option>${options.cuentas.map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label><label>Centro de costo de ese ingreso<select name="centroCostoZeus"><option value="">Sin centro de costo</option>${options.centrosCosto.map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label></div>
        <p data-refinance-total role="status"></p><div class="egreso-toolbar"><button type="submit" class="button primary">Solicitar aprobación de la nota</button><button type="button" class="button secondary" data-cancel-refinance>Cancelar</button></div></form>`;
      const form=host.querySelector('form'),body=form.querySelector('[data-new-dues]');
      const appendDue=(date,value,type='ORDINARIA')=>{
        const row=document.createElement('tr');row.innerHTML=`<td><input type="date" name="vence" value="${esc(date)}" required></td><td><input type="number" name="valor" min="0.01" step="0.01" value="${esc(value)}" required></td><td><select name="tipo"><option value="ORDINARIA" ${type==='ORDINARIA'?'selected':''}>Ordinaria</option><option value="EXTRA" ${type==='EXTRA'?'selected':''}>Extra</option></select></td><td><button type="button" class="button secondary" data-remove-due aria-label="Quitar cuota">×</button></td>`;
        body.append(row);row.querySelector('[data-remove-due]').onclick=()=>{row.remove();updateTotal();};row.querySelectorAll('input').forEach(x=>x.addEventListener('input',updateTotal));updateTotal();
      };
      const updateTotal=()=>{const cents=[...body.querySelectorAll('[name="valor"]')].reduce((sum,x)=>sum+Math.round((Number(x.value)||0)*100),0);const delta=cents-Math.round(Number(data.header.saldo)*100);form.querySelector('[data-refinance-total]').textContent=`Saldo anterior ${money(data.header.saldo)} · Nuevo saldo ${money(cents/100)} · Incremento ${money(delta/100)}${delta<0?' — No se permite reducir el saldo en esta operación.':''}`;};
      const plusDays=(date,days)=>new Date(Date.parse(date+'T00:00:00Z')+days*86400000).toISOString().slice(0,10);
      old.forEach((x,i)=>appendDue(plusDays(today(),30*(i+1)),x.saldo,x.tipo));
      form.querySelector('[data-add-due]').onclick=()=>appendDue(plusDays(body.lastElementChild?.querySelector('[name="vence"]')?.value||today(),30),'0.01');
      form.querySelector('[data-cancel-refinance]').onclick=()=>{host.innerHTML='';notice('');};
      form.onsubmit=async event=>{
        event.preventDefault();if(busy)return;
        const rows=[...body.rows];const dues=rows.map(row=>({vencimiento:row.querySelector('[name="vence"]').value,valor:Number(row.querySelector('[name="valor"]').value),tipo:row.querySelector('[name="tipo"]').value}));
        const delta=dues.reduce((sum,x)=>sum+Math.round(x.valor*100),0)-Math.round(Number(data.header.saldo)*100);
        if(!dues.length||delta<0){notice('El nuevo plan debe conservar o incrementar el saldo y contener al menos una cuota.',true);return;}
        if(delta>0&&!form.elements.cuentaIngresoZeus.value){notice('Selecciona la cuenta de ingreso para el incremento.',true);return;}
        busy=true;form.querySelector('[type="submit"]').disabled=true;
        try{await apiRequest(endpoint()+`/${id}/refinancings`,{method:'POST',body:JSON.stringify({operacionGuid:crypto.randomUUID(),fechaContable:form.elements.fechaContable.value,motivo:form.elements.motivo.value,cuotas:dues,cuentaIngresoZeus:form.elements.cuentaIngresoZeus.value||null,centroCostoZeus:form.elements.centroCostoZeus.value||null})});await viewInvoice(id,before);notice('Nota preparada. Otro usuario autorizado debe aprobarla antes del envío a Zeus.');}
        catch(error){notice(error.message,true);form.querySelector('[type="submit"]').disabled=false;}finally{busy=false;}
      };notice('');
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
  async function open(selected,showList=false,approvalsOnly=false){
    const permission=selected==='invoice'?'VENTAS.FACTURA.CONTABILIZAR':'TESORERIA.RECIBO.CONTABILIZAR';
    if(!state.erpSession?.api||!(hasPermission(permission)||approvalsOnly&&selected==='invoice'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR'))){showError('Requiere conexión al ERP y el permiso correspondiente.');return;}
    if(dialog.open)return;mode=selected;company=state.erpSession.company.id;search='';receiptFilter=showList&&selected==='receipt'?'ANTICIPO':'';dialog.showModal();if(approvalsOnly)await approvalListing();else if(showList)await listing();else await create();
  }
  document.querySelector('#cashReceiptsNav').addEventListener('click',()=>void open('receipt'));
  document.querySelector('#customerAdvancesNav').addEventListener('click',()=>void open('receipt',true));
  document.querySelector('#salesInvoicesNav').addEventListener('click',()=>void open('invoice'));
  document.querySelector('#salesApprovalsNav').addEventListener('click',()=>void open('invoice',false,true));
  window.openSavedSalesInvoice=async id=>{
    if(!state.erpSession?.api||!hasPermission('VENTAS.FACTURA.CONTABILIZAR'))return;
    if(dialog.open)return;mode='invoice';company=state.erpSession.company.id;search='';receiptFilter='';dialog.showModal();shell();await viewInvoice(id,null);
  };
  async function create(){
    const t=++token;view='create';operation=crypto.randomUUID();client=null;lines=[];conceptLines=[];applications=[];advances=[];extraInstallments=[];dimensions=null;dimensionsError='';dirty=false;shell();$('[data-search-form]').hidden=true;$('[data-create-nav]').hidden=false;notice('Cargando catálogos…');
    try{
      const [opts,chart,dims]=await Promise.all([apiRequest(endpoint()+'/options'),mode==='invoice'?Promise.resolve([]):apiRequest(endpoint()+'/accounts'),mode==='invoice'?apiRequest(endpoint()+'/accounting-dimensions').catch(error=>({error:error.message})):Promise.resolve(null)]);
      if(!current(t))return;options=opts;accounts=chart;dimensions=dims?.error?null:dims;dimensionsError=dims?.error||'';
      if(mode==='invoice')invoiceForm();else receiptForm();notice(dimensionsError?`No se pudieron consultar los centros de costo de Zeus: ${dimensionsError}`:'',Boolean(dimensionsError));
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function retryDimensions(){
    const t=token,button=$('[data-retry-dimensions]');if(!button||busy)return;
    button.disabled=true;notice('Consultando centros de costo de Zeus…');
    try{
      const result=await apiRequest(endpoint()+'/accounting-dimensions');if(!current(t)||view!=='create')return;
      dimensions=result;dimensionsError='';
      const select=$('[name="centroCostoIngreso"]');
      select.innerHTML='<option value="">Sin centro de costo</option>'+result.centrosCosto.map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('');
      $('[data-dimensions-warning]').remove();$('[data-document] button[type="submit"]').disabled=false;
      renderConcepts();updateGeneralCenterHint();notice('Centros de costo de Zeus cargados.');
    }catch(error){if(current(t))notice(`No se pudieron consultar los centros de costo de Zeus: ${error.message}`,true);}
    finally{if(button.isConnected)button.disabled=false;}
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
      <label class="customer-portfolio-filter" data-portfolio-filter-wrap hidden>Mostrar cartera de<select name="claseCarteraFiltro"><option value="">Todas las facturas</option><option value="MOTO">Motos</option><option value="OTROS">Otros artículos</option><option value="MIXTA">Mixta</option><option value="SIN_CLASIFICAR">Sin clasificar</option></select></label>
      <div data-allocations></div><div class="egreso-toolbar"><strong data-summary></strong><button class="button primary" type="submit">Contabilizar recibo</button></div></fieldset></form>`;
    wireClient();const f=$('[data-document]');f.oninput=()=>{dirty=true;summary();};
    f.elements.tipo.onchange=()=>{applications=[];renderAllocations();};
    f.elements.claseCarteraFiltro.onchange=()=>renderAllocations();
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
    $('[data-portfolio-filter-wrap]').hidden=kind!=='CARTERA';
    $('[data-contra-wrap]').hidden=kind!=='NORMAL';f.elements.cuentaContrapartida.required=kind==='NORMAL';
    f.elements.total.readOnly=kind==='CARTERA';
    if(kind!=='CARTERA'){area.innerHTML=kind==='ANTICIPO'?'<p class="egreso-help">El saldo del anticipo quedará disponible para aplicarlo a una factura futura.</p>':'<p class="egreso-help">Selecciona la cuenta contable específica para este ingreso. No modifica cartera.</p>';summary();return;}
    const selected=x=>applications.find(a=>a.facturaVentaId===x.id&&(a.facturaVentaCuotaId??null)===(x.cuotaId??null));
    const shown=(options.facturas||[]).filter(x=>!f.elements.claseCarteraFiltro.value||x.claseCartera===f.elements.claseCarteraFiltro.value);
    area.innerHTML=`<h3>Cuotas y facturas pendientes del cliente</h3><div class="table-wrap"><table><thead><tr><th>Aplicar</th><th>Factura / cuota</th><th>Cartera</th><th>Vencimiento</th><th>Saldo</th><th>Valor a recaudar</th></tr></thead><tbody>${shown.map((x,i)=>{const future=x.vence>f.elements.fechaContable.value;return `<tr><td><input type="checkbox" data-pick="${i}" ${selected(x)?'checked':''} ${x.zeusEstado==='CONTABILIZADO'&&!future?'':'disabled'}></td><td>${esc(x.numero)}${x.numeroCuota?' · cuota '+x.numeroCuota:''}</td><td>${esc(portfolioLabel(x.claseCartera))}</td><td>${esc(x.vence)}${future?' · aún no vence':''}</td><td>${money(x.saldo)}</td><td><input type="number" data-amount="${i}" min="0.01" max="${x.saldo}" step="0.01" value="${selected(x)?.valor||x.saldo}" ${selected(x)?'':'disabled'}></td></tr>`;}).join('')||'<tr><td colspan="6">No hay cuotas pendientes en esta categoría.</td></tr>'}</tbody></table></div><small class="egreso-help">Solo se recaudan cuotas vencidas y confirmadas en Zeus. Los anticipos se registran por separado.</small>`;
    area.querySelectorAll('[data-pick]').forEach(box=>box.onchange=()=>{
      const invoice=shown[Number(box.dataset.pick)];
      applications=applications.filter(a=>!(a.facturaVentaId===invoice.id&&(a.facturaVentaCuotaId??null)===(invoice.cuotaId??null)));
      if(box.checked)applications.push({facturaVentaId:invoice.id,facturaVentaCuotaId:invoice.cuotaId??null,valor:invoice.saldo});
      renderAllocations();dirty=true;
    });
    area.querySelectorAll('[data-amount]').forEach(input=>input.oninput=()=>{
      const invoice=shown[Number(input.dataset.amount)],item=selected(invoice);if(item)item.valor=Number(input.value);
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
    $('[data-content]').innerHTML=`${dimensionsError?'<div class="workflow-notice error" data-dimensions-warning role="alert">No se pudieron consultar los centros de costo de Zeus. Puedes preparar la factura, pero no emitirla hasta cargar esos datos. <button type="button" class="button secondary" data-retry-dimensions>Reintentar centros de costo</button></div>':''}<form data-document><fieldset><h3>Nueva factura de venta</h3><p class="egreso-help">Precio unitario con IVA incluido. Esta referencia ERP no reemplaza la facturación electrónica.</p><div class="egreso-grid">
      <label>Sucursal<select name="sucursalId" required><option value="">Selecciona…</option>${options.sucursales.map(x=>`<option value="${x.id}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label>
      <label>Referencia ERP<input name="numero" maxlength="15" value="FV-${Date.now().toString(36).toUpperCase()}" required></label>
      <label>Fecha contable<input name="fechaContable" type="date" value="${today()}" required></label>
      ${clientField()}</div>
      <div class="customer-invoice-meta"><label>Tipo de cartera<select name="claseCartera" required><option value="">Selecciona…</option><option value="MOTO">Motos</option><option value="OTROS">Otros artículos</option><option value="MIXTA">Mixta</option></select></label><label>Observación de la venta o garantía<textarea name="observacion" maxlength="1000" rows="2" placeholder="Información que conviene conservar con la factura"></textarea></label></div>
      <div class="egreso-grid"><label data-concept-warehouse hidden>Bodega para cuenta de clientes<select name="bodegaCarteraId"><option value="">Selecciona bodega…</option></select></label></div>
      <div class="egreso-toolbar"><h3>Artículos y conceptos</h3><button type="button" class="button secondary" data-add-line>Agregar artículo</button><button type="button" class="button secondary" data-add-concept>Agregar concepto</button></div>
      <div class="table-wrap"><table><thead><tr><th>Artículo / bodega</th><th>Cantidad</th><th>Precio unitario con IVA</th><th>IVA</th><th>Seriales</th><th></th></tr></thead><tbody data-lines></tbody></table></div>
      <div class="table-wrap"><table><thead><tr><th>Concepto de venta</th><th>Cuenta de ingreso Zeus</th><th>Valor</th><th>Centro de costo Zeus</th><th></th></tr></thead><tbody data-concept-lines></tbody></table></div>
      <div class="customer-profit-preview" data-profit-preview></div>
      <div data-allocations></div><div class="customer-invoice-settings"><label class="customer-center-field">Centro de costo de la factura<select name="centroCostoIngreso"><option value="">Sin centro de costo</option>${(dimensions?.centrosCosto||[]).map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select><small data-general-center-hint>Se aplica a los artículos cuando Zeus lo exige.</small></label>
      <section class="customer-installment-settings"><h3>Plan de cuotas</h3><div class="customer-installment-fields"><label>Primer vencimiento<input name="vencimiento" type="date" value="${today()}" required></label><label>Número de cuotas ordinarias<input name="cuotas" type="number" min="1" max="120" step="1" value="1" required></label><label>Vencimiento de las siguientes cuotas<select name="frecuenciaCuotas" required><option value="DIA_FIJO_MES">Mismo día de cada mes</option><option value="CADA_30_DIAS">Cada 30 días</option></select></label></div><small>Mensual: conserva el día del primer vencimiento. También puedes elegir cada 30 días.</small><div class="customer-extra-heading"><strong>Cuotas extraordinarias</strong><button type="button" class="button secondary" data-add-extra>+ Agregar cuota extra</button></div><div data-extra-rows></div></section></div>
      <div data-installments></div>
      <label class="customer-approval-reason">Motivo de excepción de precio o descuento <textarea name="motivoAutorizacion" maxlength="500" rows="2" placeholder="Solo cuando el precio supera el descuento libre o está bajo costo"></textarea></label>
      <div class="egreso-toolbar"><strong data-summary></strong><button class="button primary" type="submit" ${dimensionsError?'disabled':''}>Emitir factura o solicitar autorización</button></div></fieldset></form>`;
    $('[data-retry-dimensions]')?.addEventListener('click',()=>void retryDimensions());
    wireClient();const f=$('[data-document]');f.oninput=()=>{dirty=true;summary();};
    f.elements.frecuenciaCuotas.onchange=()=>{dirty=true;summary();};f.elements.vencimiento.onchange=()=>{dirty=true;summary();};
    f.elements.sucursalId.onchange=()=>{lines=[];f.elements.bodegaCarteraId.value='';addLine();};
    $('[data-add-line]').onclick=()=>addLine();$('[data-add-concept]').onclick=addConcept;
    $('[data-add-extra]').onclick=()=>{extraInstallments.push({vencimiento:'',valor:0});renderExtraInstallments();dirty=true;};
    f.onsubmit=submitInvoice;addLine(false);renderConcepts();renderAllocations();renderExtraInstallments();
  }
  function renderExtraInstallments(){
    const area=$('[data-extra-rows]');if(!area)return;
    area.innerHTML=extraInstallments.map((x,i)=>`<div class="customer-extra-row" data-extra="${i}"><label>Vencimiento<input data-extra-date type="date" value="${esc(x.vencimiento)}" required></label><label>Valor<input data-extra-amount type="number" min="0.01" step="0.01" value="${x.valor||''}" required></label><button type="button" class="button secondary" data-remove-extra>Quitar</button></div>`).join('');
    area.querySelectorAll('[data-extra]').forEach(row=>{const x=extraInstallments[Number(row.dataset.extra)];
      row.querySelector('[data-extra-date]').onchange=event=>{x.vencimiento=event.target.value;dirty=true;summary();};
      row.querySelector('[data-extra-amount]').oninput=event=>{x.valor=Number(event.target.value);dirty=true;summary();};
      row.querySelector('[data-remove-extra]').onclick=()=>{extraInstallments.splice(Number(row.dataset.extra),1);renderExtraInstallments();dirty=true;};
    });summary();
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
        <td><input data-price type="number" min="0.01" step="0.01" value="${esc(line.precioUnitarioConIva||'')}" required>${item?.precioListaConIva?`<small>Lista ${money(item.precioListaConIva)} · libre ${esc(options.maxDescuentoVentaPct)} %</small>`:'<small>Sin precio de lista</small>'}${item?.inventario&&item.costoPromedio>0&&item.iva!=null?`<button type="button" class="customer-cost-price" data-cost-price>Usar costo + IVA</button>`:''}</td>
        <td>${item?.iva==null?'IVA sin clasificar':esc(item.iva+' %')}</td>
        <td>${item?.serial?`<button type="button" class="button secondary customer-serial-trigger" data-choose-serial>Buscar seriales</button><small class="customer-serial-count">${line.unidadesSerializadas.length} de ${esc(line.cantidad)} seleccionada(s)</small>`:'—'}</td>
        <td><button type="button" class="button secondary" data-remove>Quitar</button></td></tr>`;
    }).join('');
    area.querySelectorAll('[data-line]').forEach(row=>{
      const line=lines[Number(row.dataset.line)];
      row.querySelector('[data-article]').onchange=event=>{const [id,warehouse]=event.target.value.split('|').map(Number);line.articuloId=id||0;line.bodegaId=warehouse||0;line.precioUnitarioConIva=choices.find(a=>a.id===id&&a.bodegaId===warehouse)?.precioListaConIva||0;line.unidadesSerializadas=[];renderLines();dirty=true;};
      row.querySelector('[data-qty]').oninput=event=>{line.cantidad=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-price]').oninput=event=>{line.precioUnitarioConIva=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-cost-price]')?.addEventListener('click',()=>{const item=articleChoices().find(a=>a.id===line.articuloId&&a.bodegaId===line.bodegaId);if(!item||item.costoPromedio==null||item.iva==null)return;line.precioUnitarioConIva=Math.round(item.costoPromedio*(1+item.iva/100)*100)/100;renderLines();dirty=true;});
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
    const priced=lines.filter(x=>x.articuloId&&x.bodegaId&&x.cantidad>0&&x.precioUnitarioConIva>0);
    const inventoryLines=priced.map(x=>({line:x,item:(options.articulos||[]).find(a=>a.id===x.articuloId&&a.bodegaId===x.bodegaId)})).filter(x=>x.item?.inventario);
    const unknownCost=inventoryLines.some(x=>x.item.costoPromedio==null||x.item.iva==null);
    const netRevenue=inventoryLines.reduce((sum,x)=>sum+(x.item.iva==null?0:Math.round(x.line.cantidad*x.line.precioUnitarioConIva/(1+x.item.iva/100)*100)/100),0);
    const estimatedCost=inventoryLines.reduce((sum,x)=>sum+x.line.cantidad*(x.item.costoPromedio||0),0);
    const margin=netRevenue-estimatedCost;
    const preview=$('[data-profit-preview]');
    if(preview)preview.innerHTML=inventoryLines.length?`<strong>Rentabilidad estimada de artículos inventariables</strong><span>Venta sin IVA: ${unknownCost?'pendiente':money(netRevenue)} · Costo promedio actual: ${unknownCost?'no disponible':money(estimatedCost)} · Margen: ${unknownCost?'no calculable':money(margin)}</span><small>Es una estimación: el costo definitivo se registra al emitir la factura y puede diferir para unidades serializadas.</small>`:'';
    const concepts=Math.round(conceptLines.reduce((s,x)=>s+Math.round(x.valor*100),0))/100;
    const advance=Math.round(advances.reduce((s,x)=>s+Math.round(x.valor*100),0))/100;
    const total=goods+concepts,balance=Math.round((total-advance)*100)/100,terms=Number(f.elements.cuotas.value);
    const cents=Math.round(balance*100),extraCents=extraInstallments.reduce((sum,x)=>sum+Math.round(x.valor*100),0),regularCents=cents-extraCents,calendar=$('[data-installments]');
    $('[data-summary]').textContent=`Artículos ${money(goods)} + conceptos ${money(concepts)} = total ${money(total)} · Cuota inicial ${money(advance)} · Saldo a financiar ${money(balance)}`;
    const advanceSummary=$('[data-advance-summary]');if(advanceSummary)advanceSummary.textContent=`${advances.length} anticipo(s) seleccionado(s) · Total a aplicar: ${money(advance)}`;
    if(!Number.isInteger(terms)||terms<1||terms>120||terms+extraInstallments.length>120||!f.elements.vencimiento.value||cents<0){calendar.innerHTML='<p class="egreso-help">Completa el primer vencimiento y el número de cuotas para ver el calendario.</p>';return;}
    if(cents===0){calendar.innerHTML='<p class="egreso-help">No queda saldo de cartera: la cuota inicial cubre toda la factura.</p>';return;}
    if(regularCents<terms||extraInstallments.some(x=>!x.vencimiento||x.valor<=0||x.vencimiento<f.elements.fechaContable.value)||new Set(extraInstallments.map(x=>x.vencimiento)).size!==extraInstallments.length){calendar.innerHTML='<p class="egreso-help">Revisa las cuotas extras: fecha válida y distinta, valor positivo y saldo suficiente para las cuotas ordinarias.</p>';return;}
    const regular=Math.floor(regularCents/terms),frequency=f.elements.frecuenciaCuotas.value;
    const dateAt=index=>{
      const [year,month,day]=f.elements.vencimiento.value.split('-').map(Number);
      let date;
      if(frequency==='CADA_30_DIAS')date=new Date(Date.UTC(year,month-1,day+30*index));
      else{const targetMonth=month-1+index,lastDay=new Date(Date.UTC(year,targetMonth+1,0)).getUTCDate();date=new Date(Date.UTC(year,targetMonth,Math.min(day,lastDay)));}
      return date.toISOString().slice(0,10);
    };
    const schedule=Array.from({length:terms},(_,i)=>({tipo:'Ordinaria',vence:dateAt(i),valor:(i===terms-1?regularCents-regular*(terms-1):regular)/100}))
      .concat(extraInstallments.map(x=>({tipo:'Extra',vence:x.vencimiento,valor:x.valor})))
      .sort((a,b)=>a.vence.localeCompare(b.vence)||(a.tipo==='Ordinaria'?-1:1));
    calendar.innerHTML=`<h3>Calendario de cartera · ${schedule.length} cuota(s)</h3><div class="table-wrap"><table><thead><tr><th>Cuota</th><th>Tipo</th><th>Vencimiento</th><th>Valor en cuenta 13</th></tr></thead><tbody>${schedule.map((x,i)=>`<tr><td>${i+1}</td><td>${x.tipo}</td><td>${x.vence}</td><td>${money(x.valor)}</td></tr>`).join('')}</tbody></table></div>`;
  }
  async function submitInvoice(event){
    event.preventDefault();if(busy)return;const f=event.target;
    if(dimensionsError||!dimensions){notice('Consulta los centros de costo de Zeus antes de emitir la factura o solicitar autorización.',true);return;}
    if(!client){notice('Selecciona un cliente de los resultados.',true);return;}
    if(lines.some(x=>!x.articuloId||!x.bodegaId||x.cantidad<=0||x.precioUnitarioConIva<=0)){notice('Completa artículos, cantidades y precios.',true);return;}
    if(!lines.length&&!conceptLines.length){notice('Agrega al menos un artículo o un concepto.',true);return;}
    const priceIssues=[];
    for(const line of lines){const a=options.articulos.find(x=>x.id===line.articuloId&&x.bodegaId===line.bodegaId);
      if(a?.iva==null||a.inventario&&line.cantidad>a.existencia||a?.serial&&line.unidadesSerializadas.length!==line.cantidad){notice('Revisa el IVA, las existencias y los seriales seleccionados.',true);return;}
      if(a.precioListaConIva&&line.precioUnitarioConIva<Math.round(a.precioListaConIva*(1-options.maxDescuentoVentaPct/100)*100)/100)priceIssues.push(`${a.codigo}: descuento superior a ${options.maxDescuentoVentaPct} %`);
      if(a.inventario&&a.costoPromedio>0&&line.precioUnitarioConIva<Math.round(a.costoPromedio*(1+a.iva/100)*100)/100)priceIssues.push(`${a.codigo}: precio bajo costo`);}
    if(conceptLines.some(x=>!x.conceptoVentaId||!Number.isFinite(x.valor)||x.valor<=0)){notice('Completa los conceptos y sus valores.',true);return;}
    const required=dimensions?.cuentasRequierenCentroCosto||[];
    if(conceptLines.some(x=>required.includes(options.conceptos.find(c=>c.id===x.conceptoVentaId)?.cuentaIngresoZeus)&&!x.centroCosto)){notice('Selecciona el centro de costo de cada concepto cuya cuenta Zeus lo exija.',true);return;}
    const totalCents=lines.reduce((s,x)=>s+Math.round(x.cantidad*x.precioUnitarioConIva*100),0)+conceptLines.reduce((s,x)=>s+Math.round(x.valor*100),0);
    const financedCents=totalCents-advances.reduce((s,x)=>s+Math.round(x.valor*100),0);
    if(financedCents<0){notice('La cuota inicial no puede superar el total de la factura.',true);return;}
    const extraCents=extraInstallments.reduce((s,x)=>s+Math.round(x.valor*100),0);
    if(financedCents>0&&financedCents-extraCents<Number(f.elements.cuotas.value)){notice('Las cuotas extras deben dejar al menos $0,01 para cada cuota ordinaria.',true);return;}
    const body={operacionGuid:operation,numero:f.elements.numero.value,clienteId:client.id,sucursalId:Number(f.elements.sucursalId.value),fechaContable:f.elements.fechaContable.value,vencimiento:f.elements.vencimiento.value,lineas:lines,conceptos:conceptLines,cuotas:Number(f.elements.cuotas.value),frecuenciaCuotas:f.elements.frecuenciaCuotas.value,anticipos:advances,bodegaCarteraId:lines.length?null:Number(f.elements.bodegaCarteraId.value),centroCostoIngreso:f.elements.centroCostoIngreso.value||null,claseCartera:f.elements.claseCartera.value,observacion:f.elements.observacion.value.trim()||null,cuotasExtras:extraInstallments};
    if(priceIssues.length){
      const reason=f.elements.motivoAutorizacion.value.trim();
      if(reason.length<10){notice(`Esta factura requiere autorización (${priceIssues.join('; ')}). Escribe un motivo de al menos 10 caracteres.`,true);return;}
      busy=true;const submit=f.querySelector('[type="submit"]');submit.disabled=true;notice('Guardando solicitud de autorización…');
      try{const result=await apiRequest(`/api/v1/companies/${company}/sales-price-approvals`,{method:'POST',body:JSON.stringify({factura:body,motivo:reason})});dirty=false;await approvalListing();notice(`Solicitud #${result.id} pendiente. Otro usuario autorizado debe aprobarla; aún no se emitió ni contabilizó la factura.`);}
      catch(error){notice(error.message,true);}finally{busy=false;if(submit.isConnected)submit.disabled=false;}
      return;
    }
    await send(body,'Factura');
  }
  async function send(body,title){
    busy=true;const submit=$('[data-document] button[type="submit"]');submit.disabled=true;notice('Contabilizando en ERP…');
    try{const result=await apiRequest(endpoint(),{method:'POST',body:JSON.stringify(body)});dirty=false;await listing();notice(`${title} ${result.numero||result.id} contabilizado en ERP. Zeus: ${result.zeusEstado||'PENDIENTE'}. Consulta el seguimiento para confirmar el comprobante.`);}
    catch(error){notice(error.message,true);}
    finally{busy=false;if(submit.isConnected)submit.disabled=false;}
  }
})();
