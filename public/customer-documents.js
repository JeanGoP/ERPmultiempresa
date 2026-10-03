/* Facturas y recibos definitivos. La contabilidad Zeus conserva seguimiento independiente. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const today=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'America/Bogota'});
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog customer-documents-dialog';document.body.append(dialog);
  const $=selector=>dialog.querySelector(selector);
  let mode='',company=0,token=0,busy=false,dirty=false,options=null,accounts=[],search='',next=null;
  let operation='',client=null,lines=[],applications=[],advances=[];
  const endpoint=()=>`/api/v1/companies/${company}/${mode==='invoice'?'sales-invoices':'cash-receipts'}`;
  const current=t=>t===token&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  const notice=(message,error=false)=>{const area=$('[data-message]');if(area){area.textContent=message;area.classList.toggle('error',error);}};
  const clientLabel=c=>c?`${c.identificacion} · ${c.nombre}`:'';
  function close(force=false){if(!force&&(busy||dirty&&!confirm('¿Salir sin contabilizar el documento?')))return;token++;dirty=false;dialog.close();mode='';company=0;}
  window.resetCustomerDocuments=()=>close(true);
  dialog.addEventListener('cancel',event=>{event.preventDefault();close();});
  function shell(){
    const title=mode==='invoice'?'Facturas de venta':'Recibos de caja';
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">${mode==='invoice'?'VENTAS':'TESORERÍA'} · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>${title}</h2></div><button class="dialog-close" type="button" data-close aria-label="Cerrar">×</button></div>
      <form class="egreso-toolbar" data-search-form><label>Buscar documentos guardados<input name="buscar" maxlength="100" placeholder="Número, cliente, identificación o Zeus" value="${esc(search)}"></label><button class="button secondary">Buscar</button><button type="button" class="button primary" data-new>Nuevo</button></form>
      <p data-message role="status" aria-live="polite"></p><div data-content></div>`;
    $('[data-close]').onclick=()=>close();
    $('[data-new]').onclick=()=>{if(!busy&&(!dirty||confirm('¿Descartar los datos sin contabilizar?')))void create();};
    $('[data-search-form]').onsubmit=event=>{event.preventDefault();if(busy||dirty&&!confirm('¿Descartar el documento sin contabilizar?'))return;search=event.target.elements.buscar.value.trim();void listing();};
  }
  async function listing(before=null){
    const t=++token;dirty=false;shell();notice('Consultando documentos…');
    try{
      const response=await apiRequest(endpoint()+`?q=${encodeURIComponent(search)}${before?`&antes=${before}`:''}`);
      if(!current(t))return;next=response.siguiente;
      $('[data-content]').innerHTML=`<div class="table-wrap"><table><thead><tr><th>Documento</th><th>Fecha</th><th>Cliente</th><th>Total</th><th>Saldo / tipo</th><th>Zeus</th></tr></thead><tbody>${response.items.map(row=>`<tr><td>${esc(row.numero||'RC-'+row.id)}</td><td>${esc(row.fecha)}</td><td>${esc(row.cliente)}</td><td>${money(row.total)}</td><td>${mode==='invoice'?money(row.saldo)+' · anticipo '+money(row.anticipo):esc(row.tipo)}</td><td>${esc(row.zeusEstado)} ${esc([row.fuente,row.documento].filter(Boolean).join(' · '))}<br><small>${esc(row.error||'')}</small>${row.zeusEstado==='RECHAZADO'?`<button type="button" class="button secondary" data-retry="${row.id}">Reintentar Zeus</button>`:''}${row.zeusEstado==='INCIERTO'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')?`<button type="button" class="button secondary" data-reconcile="${row.id}">Conciliar</button>`:''}</td></tr>`).join('')||'<tr><td colspan="6">No se encontraron documentos.</td></tr>'}</tbody></table></div>
        <div class="egreso-toolbar"><button type="button" class="button secondary" data-first>Primera página</button><button type="button" class="button secondary" data-next ${next?'':'disabled'}>Siguientes</button></div>`;
      notice('');$('[data-first]').onclick=()=>listing();$('[data-next]').onclick=()=>listing(next);
      for(const action of ['retry','reconcile'])dialog.querySelectorAll(`[data-${action}]`).forEach(button=>button.onclick=async()=>{
        if(busy)return;busy=true;button.disabled=true;
        try{const result=await apiRequest(endpoint()+`/${button.dataset[action]}/${action}`,{method:'POST'});await listing(before);if(result?.error)notice(result.error,true);}
        catch(error){if(current(t))notice(error.message,true);}finally{busy=false;}
      });
    }catch(error){if(current(t))notice(error.message,true);}
  }
  async function open(selected){
    const permission=selected==='invoice'?'VENTAS.FACTURA.CONTABILIZAR':'TESORERIA.RECIBO.CONTABILIZAR';
    if(!state.erpSession?.api||!hasPermission(permission)){showError('Requiere conexión al ERP y permiso para contabilizar este documento.');return;}
    if(dialog.open)return;mode=selected;company=state.erpSession.company.id;search='';dialog.showModal();await create();
  }
  document.querySelector('#cashReceiptsNav').addEventListener('click',()=>void open('receipt'));
  document.querySelector('#salesInvoicesNav').addEventListener('click',()=>void open('invoice'));
  async function create(){
    const t=++token;operation=crypto.randomUUID();client=null;lines=[];applications=[];advances=[];dirty=false;shell();notice('Cargando catálogos…');
    try{
      const [opts,chart]=await Promise.all([apiRequest(endpoint()+'/options'),apiRequest(endpoint()+(mode==='invoice'?'/financing-accounts':'/accounts'))]);
      if(!current(t))return;options=opts;accounts=chart;
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
    area.innerHTML=`<h3>Facturas pendientes del cliente</h3><div class="table-wrap"><table><thead><tr><th>Aplicar</th><th>Factura</th><th>Vencimiento</th><th>Saldo</th><th>Valor a recaudar</th></tr></thead><tbody>${(options.facturas||[]).map(x=>`<tr><td><input type="checkbox" data-pick="${x.id}" ${applications.some(a=>a.facturaVentaId===x.id)?'checked':''} ${x.zeusEstado==='CONTABILIZADO'?'':'disabled'}></td><td>${esc(x.numero)}</td><td>${esc(x.vence)}</td><td>${money(x.saldo)}</td><td><input type="number" data-amount="${x.id}" min="0.01" max="${x.saldo}" step="0.01" value="${applications.find(a=>a.facturaVentaId===x.id)?.valor||x.saldo}" ${applications.some(a=>a.facturaVentaId===x.id)?'':'disabled'}></td></tr>`).join('')||'<tr><td colspan="5">Selecciona un cliente con facturas pendientes.</td></tr>'}</tbody></table></div><small class="egreso-help">Solo se recaudan facturas confirmadas en Zeus.</small>`;
    area.querySelectorAll('[data-pick]').forEach(box=>box.onchange=()=>{
      const id=Number(box.dataset.pick),invoice=options.facturas.find(x=>x.id===id);
      applications=applications.filter(a=>a.facturaVentaId!==id);
      if(box.checked)applications.push({facturaVentaId:id,valor:invoice.saldo});
      renderAllocations();dirty=true;
    });
    area.querySelectorAll('[data-amount]').forEach(input=>input.oninput=()=>{
      const item=applications.find(a=>a.facturaVentaId===Number(input.dataset.amount));if(item)item.valor=Number(input.value);
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
      <label>Vencimiento<input name="vencimiento" type="date" value="${today()}" required></label>${clientField()}
      <label>Financiación<input name="financiacion" type="number" step="0.01" min="0" value="0"></label>
      <label>Cuenta de financiación 4135<select name="cuentaFinanciacion"><option value="">Sin financiación</option>${accounts.map(a=>`<option value="${esc(a.codigo)}">${esc(a.codigo+' · '+a.nombre)}</option>`).join('')}</select></label>
      <label>Número de cuotas<input name="cuotas" type="number" min="1" max="120" step="1" value="1" required></label></div>
      <div class="egreso-toolbar"><h3>Artículos y conceptos</h3><button type="button" class="button secondary" data-add-line>Agregar línea</button></div>
      <div class="table-wrap"><table><thead><tr><th>Artículo / bodega</th><th>Cantidad</th><th>Precio unitario con IVA</th><th>IVA</th><th>Seriales</th><th></th></tr></thead><tbody data-lines></tbody></table></div>
      <div data-allocations></div><div class="egreso-toolbar"><strong data-summary></strong><button class="button primary" type="submit">Emitir y contabilizar factura</button></div></fieldset></form>`;
    wireClient();const f=$('[data-document]');f.oninput=()=>{dirty=true;summary();};
    f.elements.sucursalId.onchange=()=>{lines=[];addLine();};
    $('[data-add-line]').onclick=addLine;f.onsubmit=submitInvoice;addLine();renderAllocations();
  }
  function articleChoices(){
    const branch=$('[data-document]')?.elements.sucursalId.value;
    return (options.articulos||[]).filter(a=>String(a.sucursalId)===branch);
  }
  function addLine(){lines.push({articuloId:0,bodegaId:0,cantidad:1,precioUnitarioConIva:0,unidadesSerializadas:[]});renderLines();dirty=true;}
  function renderLines(){
    const area=$('[data-lines]');if(!area)return;const choices=articleChoices();
    area.innerHTML=lines.map((line,index)=>{
      const item=choices.find(a=>a.id===line.articuloId&&a.bodegaId===line.bodegaId);
      const serials=(options.seriales||[]).filter(x=>x.articuloId===line.articuloId&&x.bodegaId===line.bodegaId);
      const available=[...new Map(serials.map(x=>[x.id,x])).values()];
      return `<tr data-line="${index}"><td><select data-article required><option value="">Selecciona artículo y bodega…</option>${choices.map(a=>`<option value="${a.id}|${a.bodegaId}" ${a.id===line.articuloId&&a.bodegaId===line.bodegaId?'selected':''}>${esc(a.codigo+' · '+a.descripcion+' · '+a.bodegaCodigo+' · Disponible '+a.existencia)}</option>`).join('')}</select></td>
        <td><input data-qty type="number" min="0.000001" step="0.000001" value="${esc(line.cantidad)}" required></td>
        <td><input data-price type="number" min="0.01" step="0.01" value="${esc(line.precioUnitarioConIva||'')}" required></td>
        <td>${item?.iva==null?'IVA sin clasificar':esc(item.iva+' %')}</td>
        <td>${item?.serial?`<select data-serial multiple size="${Math.min(4,Math.max(2,available.length))}" aria-label="Unidades serializadas">${available.map(x=>`<option value="${x.id}" ${line.unidadesSerializadas.includes(x.id)?'selected':''}>${esc(x.tipo+' '+x.valor+' · '+x.id)}</option>`).join('')}</select><small>Selecciona ${esc(line.cantidad)} unidad(es) con Ctrl/Cmd.</small>`:'—'}</td>
        <td><button type="button" class="button secondary" data-remove>Quitar</button></td></tr>`;
    }).join('');
    area.querySelectorAll('[data-line]').forEach(row=>{
      const line=lines[Number(row.dataset.line)];
      row.querySelector('[data-article]').onchange=event=>{const [id,warehouse]=event.target.value.split('|').map(Number);line.articuloId=id||0;line.bodegaId=warehouse||0;line.unidadesSerializadas=[];renderLines();dirty=true;};
      row.querySelector('[data-qty]').oninput=event=>{line.cantidad=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-price]').oninput=event=>{line.precioUnitarioConIva=Number(event.target.value);summary();dirty=true;};
      row.querySelector('[data-serial]')?.addEventListener('change',event=>{line.unidadesSerializadas=Array.from(event.target.selectedOptions,x=>Number(x.value));dirty=true;});
      row.querySelector('[data-remove]').onclick=()=>{lines.splice(Number(row.dataset.line),1);renderLines();dirty=true;};
    });summary();
  }
  function renderAdvances(){
    const area=$('[data-allocations]');if(!area)return;
    area.innerHTML=`<h3>Anticipos disponibles del cliente</h3><div class="table-wrap"><table><thead><tr><th>Aplicar</th><th>Recibo</th><th>Saldo disponible</th><th>Valor a descontar</th></tr></thead><tbody>${(options.anticipos||[]).map(x=>`<tr><td><input type="checkbox" data-pick-advance="${x.id}" ${advances.some(a=>a.reciboCajaId===x.id)?'checked':''}></td><td>RC-${x.id}</td><td>${money(x.saldo)}</td><td><input data-advance-value="${x.id}" type="number" min="0.01" max="${x.saldo}" step="0.01" value="${advances.find(a=>a.reciboCajaId===x.id)?.valor||x.saldo}" ${advances.some(a=>a.reciboCajaId===x.id)?'':'disabled'}></td></tr>`).join('')||'<tr><td colspan="4">No hay anticipos disponibles.</td></tr>'}</tbody></table></div>`;
    area.querySelectorAll('[data-pick-advance]').forEach(box=>box.onchange=()=>{const id=Number(box.dataset.pickAdvance),advance=options.anticipos.find(x=>x.id===id);advances=advances.filter(x=>x.reciboCajaId!==id);if(box.checked)advances.push({reciboCajaId:id,valor:advance.saldo});renderAdvances();dirty=true;});
    area.querySelectorAll('[data-advance-value]').forEach(input=>input.oninput=()=>{const x=advances.find(a=>a.reciboCajaId===Number(input.dataset.advanceValue));if(x)x.valor=Number(input.value);summary();dirty=true;});summary();
  }
  function invoiceSummary(){
    const f=$('[data-document]');if(!f)return;
    const goods=Math.round(lines.reduce((s,x)=>s+Math.round(x.cantidad*x.precioUnitarioConIva*100),0))/100;
    const financing=Number(f.elements.financiacion.value)||0;
    const advance=Math.round(advances.reduce((s,x)=>s+Math.round(x.valor*100),0))/100;
    const total=goods+financing,balance=total-advance,terms=Number(f.elements.cuotas.value)||1;
    $('[data-summary]').textContent=`Total ${money(total)} · Anticipos ${money(advance)} · Saldo ${money(balance)} · ${terms} cuota(s) de aprox. ${money(balance/terms)}`;
  }
  async function submitInvoice(event){
    event.preventDefault();if(busy)return;const f=event.target;
    if(!client){notice('Selecciona un cliente de los resultados.',true);return;}
    if(!lines.length||lines.some(x=>!x.articuloId||!x.bodegaId||x.cantidad<=0||x.precioUnitarioConIva<=0)){notice('Completa artículos, cantidades y precios.',true);return;}
    for(const line of lines){const a=options.articulos.find(x=>x.id===line.articuloId&&x.bodegaId===line.bodegaId);
      if(a?.iva==null||a.inventario&&line.cantidad>a.existencia||a?.serial&&line.unidadesSerializadas.length!==line.cantidad){notice('Revisa el IVA, las existencias y los seriales seleccionados.',true);return;}}
    const financing=Number(f.elements.financiacion.value)||0;
    if(financing>0&&!f.elements.cuentaFinanciacion.value){notice('Selecciona una cuenta 4135 para la financiación.',true);return;}
    const body={operacionGuid:operation,numero:f.elements.numero.value,clienteId:client.id,sucursalId:Number(f.elements.sucursalId.value),fechaContable:f.elements.fechaContable.value,vencimiento:f.elements.vencimiento.value,lineas:lines,financiacion:financing,cuentaFinanciacion:f.elements.cuentaFinanciacion.value||null,cuotas:Number(f.elements.cuotas.value),anticipos:advances};
    await send(body,'Factura');
  }
  async function send(body,title){
    busy=true;const submit=$('[data-document] button[type="submit"]');submit.disabled=true;notice('Contabilizando en ERP…');
    try{const result=await apiRequest(endpoint(),{method:'POST',body:JSON.stringify(body)});dirty=false;await listing();notice(`${title} ${result.numero||result.id} contabilizado en ERP. Zeus: ${result.zeusEstado||'PENDIENTE'}. Consulta el seguimiento para confirmar el comprobante.`);}
    catch(error){notice(error.message,true);}
    finally{busy=false;if(submit.isConnected)submit.disabled=false;}
  }
})();
