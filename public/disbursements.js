/* Egresos definitivos: aplicación ERP única y seguimiento Zeus independiente. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const dialog=document.createElement('dialog');dialog.id='disbursementDialog';dialog.className='erp-dialog egreso-dialog';
  dialog.setAttribute('aria-label','Comprobantes de egreso');document.body.append(dialog);
  let generation=0,company=null,current=null,options=null,dirty=false,busy=false,next=null,accounts=[];
  let beneficiaryTimer=null,beneficiaryRequest=0;
  let searchTerm='';
  const beneficiaryLabel=x=>x?`${x.identificacion} · ${x.nombre}`:'';
  const $e=s=>dialog.querySelector(s);
  const url=()=>`/api/v1/companies/${company}/disbursements`;
  const valid=token=>token===generation&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  const money=(n,c)=>new Intl.NumberFormat('es-CO',{style:'currency',currency:c||'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(n||0);
  const notice=(text,error=false)=>{const e=$e('[data-notice]');if(e){e.textContent=text;e.classList.toggle('error',error);}};
  function close(force=false){if(!force&&(busy||dirty&&!confirm('¿Descartar los datos sin contabilizar?')))return;generation++;dirty=false;dialog.close();current=null;company=null;}
  window.resetEgresos=()=>close(true);
  dialog.addEventListener('cancel',e=>{e.preventDefault();close();});
  function shell(){
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">TESORERÍA · ${esc(state.erpSession?.company?.name||'Empresa activa')}</span><h2>Comprobantes de egreso</h2></div><button type="button" class="dialog-close" data-close aria-label="Cerrar">×</button></div>
      <form data-find-form class="egreso-toolbar"><label>Buscar egresos guardados<input data-find maxlength="120" placeholder="CE, proveedor, identificación o comprobante Zeus" value="${esc(searchTerm)}" required></label><button class="button secondary">Buscar</button><button type="button" class="button secondary" data-create>Nuevo egreso</button></form><p data-notice role="status" aria-live="polite"></p><div data-content></div>`;
    $e('[data-close]').onclick=()=>close();
    $e('[data-find-form]').onsubmit=e=>{e.preventDefault();if(busy||dirty&&!confirm('¿Descartar los datos sin contabilizar para buscar?'))return;searchTerm=$e('[data-find]').value.trim();void listing();};
    $e('[data-create]').onclick=()=>{if(!busy&&(!dirty||confirm('¿Descartar los datos sin contabilizar?')))void edit();};
  }
  async function listing(before=null){
    const token=++generation;current=null;dirty=false;shell();notice('Consultando egresos…');
    if(!searchTerm){notice('Busca por comprobante, proveedor o identificación.');return;}
    try{
      const data=await apiRequest(url()+'?q='+encodeURIComponent(searchTerm)+(before?'&antes='+before:''));if(!valid(token))return;
      next=data.siguiente;
      $e('[data-content]').innerHTML=`<div class="egreso-toolbar"><button type="button" class="button primary" data-new>Nuevo egreso</button><button type="button" class="button secondary" data-refresh>Actualizar</button></div>
        <div class="table-wrap"><table><thead><tr><th>Comprobante</th><th>Fecha contable</th><th>Beneficiario</th><th>Total</th><th>ERP / Zeus</th><th>Detalle / acción</th></tr></thead><tbody>${data.items.map(x=>`<tr><td>CE-${x.id}</td><td>${esc(x.fecha)}</td><td>${esc(x.beneficiario)}</td><td>${esc(money(x.total,x.moneda))}</td><td>ERP contabilizado<br>Zeus: ${esc(x.zeusEstado)} ${esc(x.fuente||'')} ${esc(x.documento||'')}</td><td>${esc(x.error||'')}<button type="button" class="button secondary" data-open="${x.id}">Ver</button>${x.zeusEstado==='RECHAZADO'?`<button class="button secondary" data-retry="${x.id}">Reintentar solo Zeus</button>`:''}${x.zeusEstado==='INCIERTO'&&hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')?`<button class="button secondary" data-reconcile="${x.id}">Conciliar Zeus</button>`:''}</td></tr>`).join('')||'<tr><td colspan="6">No hay egresos contabilizados.</td></tr>'}</tbody></table></div>
        <div class="egreso-toolbar"><button type="button" class="button secondary" data-first>Primera página</button><button type="button" class="button secondary" data-next ${next?'':'disabled'}>Siguientes</button></div>`;
      notice('');$e('[data-new]').onclick=()=>edit();$e('[data-refresh]').onclick=()=>listing(before);$e('[data-first]').onclick=()=>listing();$e('[data-next]').onclick=()=>listing(next);
      dialog.querySelectorAll('[data-open]').forEach(b=>b.onclick=()=>view(Number(b.dataset.open)));
      for(const action of ['retry','reconcile'])dialog.querySelectorAll(`[data-${action}]`).forEach(b=>b.onclick=async()=>{if(busy)return;busy=true;b.disabled=true;try{const result=await apiRequest(url()+`/${b.dataset[action]}/${action}`,{method:'POST'});if(valid(token)){await listing(before);if(result?.error)notice(result.error,true);}}catch(e){if(valid(token))notice(e.message,true);}finally{busy=false;if(valid(token))b.disabled=false;}});
    }catch(e){if(valid(token))notice(e.message,true);}
  }
  window.openEgresos=async()=>{
    if(!state.erpSession?.api||!hasPermission('TESORERIA.EGRESO.CONTABILIZAR')){showError('Requiere conexión al ERP y permiso para contabilizar egresos.');return;}
    if(dialog.open)return;
    company=state.erpSession.company.id;searchTerm='';dialog.showModal();await edit();
  };
  document.querySelector('#disbursementsNav').addEventListener('click',window.openEgresos);
  function blank(){return {operacionGuid:crypto.randomUUID(),version:0,sucursalId:'',terceroId:'',fechaContable:new Date().toLocaleDateString('sv-SE',{timeZone:'America/Bogota'}),moneda:'COP',medioPago:'TRANSFERENCIA',bancoCaja:'',cuentaSalida:'',referencia:'',concepto:'',lineas:[]};}
  async function edit(id=null){
    const token=++generation;shell();notice('Cargando…');
    try{
      const data=id?await apiRequest(url()+'/'+id):{datos:blank()};if(!valid(token))return;
      current={id,datos:data.datos};
      const result=await apiRequest(url()+'/options'+(current.datos.terceroId?'?terceroId='+current.datos.terceroId:''));if(!valid(token))return;
      options=result;dirty=false;form();notice('');
      const configured=await apiRequest(url()+'/accounts');if(!valid(token))return;accounts=configured;accountHint();
    }catch(e){if(valid(token))notice(e.message,true);}
  }
  function form(){
    const d=current.datos;
    const input=(name,label,max,required=false,type='text')=>`<label>${label}<input name="${name}" type="${type}" value="${esc(d[name])}" maxlength="${max}" ${required?'required':''}></label>`;
    $e('[data-content]').innerHTML=`<form data-form><fieldset><div class="egreso-toolbar"><h3>Nuevo egreso</h3></div>
      <div class="egreso-grid"><label>Sucursal<select name="sucursalId" required><option value="">Selecciona…</option>${options.sucursales.map(x=>`<option value="${x.id}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label>
      ${input('fechaContable','Fecha contable',10,true,'date')}${input('moneda','Moneda',3,true)}
      <label>Medio de pago<select name="medioPago"><option>TRANSFERENCIA</option><option>EFECTIVO</option><option>CHEQUE</option></select></label>
      <label class="egreso-wide">Beneficiario<input data-beneficiary list="egresoBeneficiarios" placeholder="Buscar por nombre o identificación…" autocomplete="off" required aria-describedby="egresoBeneficiaryStatus"><input type="hidden" name="terceroId"><datalist id="egresoBeneficiarios"></datalist></label>
      ${input('referencia','Referencia del pago / cheque',20)}<p data-account class="egreso-help"></p>
      <label class="egreso-wide">Concepto<input name="concepto" value="${esc(d.concepto)}" maxlength="300" required></label></div>
      <p data-options-note id="egresoBeneficiaryStatus" class="egreso-help" role="status" aria-live="polite"></p>
      <h3>Facturas pendientes del proveedor</h3><div class="table-wrap" data-pending></div>
      <div class="egreso-toolbar"><h3>Facturas y gastos</h3><button type="button" class="button secondary" data-invoice>Agregar factura</button><button type="button" class="button secondary" data-expense>Agregar gasto ocasional</button></div>
      <div class="table-wrap"><table><thead><tr><th>Tipo / factura</th><th>Concepto</th><th>Cuenta de gasto</th><th>Abono / valor</th><th></th></tr></thead><tbody data-lines></tbody></table></div>
      <p class="egreso-help">La cuenta de proveedor se toma de cada obligación. Los gastos directos no incluyen desglose de IVA ni retención: causa primero esas compras y selecciónalas como factura.</p>
      <div class="egreso-toolbar"><strong data-total></strong><button type="submit" class="button primary">Contabilizar egreso</button><button type="button" class="button secondary" data-back>Volver</button></div>
      </fieldset></form>`;
    for(const name of ['sucursalId','terceroId','medioPago'])$e(`[name="${name}"]`).value=d[name];
    current.beneficiario=options.beneficiarios.find(x=>String(x.id)===String(d.terceroId));
    $e('[data-beneficiary]').value=beneficiaryLabel(current.beneficiario);beneficiaryOptions();
    $e('[data-form]').addEventListener('input',()=>{dirty=true;});
    $e('[data-beneficiary]').oninput=beneficiaryInput;
    $e('[data-beneficiary]').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();beneficiaryInput();}};
    for(const name of ['sucursalId','medioPago'])$e(`[name="${name}"]`).onchange=()=>{capture();accountHint();};
    $e('[name="moneda"]').readOnly=true;
    $e('[name="moneda"]').onchange=()=>{capture();renderLines();};
    $e('[data-invoice]').onclick=()=>{capture();if(!d.terceroId){notice('Selecciona primero un beneficiario.',true);return;}d.lineas.push({tipo:'FACTURA',documentoPorPagarId:null,cuenta:'',concepto:'',valor:0});dirty=true;renderLines();};
    $e('[data-expense]').onclick=()=>{capture();d.lineas.push({tipo:'GASTO',documentoPorPagarId:null,cuenta:'',concepto:'',valor:0});dirty=true;renderLines();};
    $e('[data-back]').onclick=()=>{if(!dirty||confirm('¿Salir sin guardar los cambios?'))void listing();};
    $e('[data-form]').onsubmit=save;renderLines();accountHint();
  }
  function capture(){
    const f=$e('[data-form]');if(!f)return;const data=new FormData(f);
    for(const name of ['sucursalId','terceroId','fechaContable','moneda','medioPago','referencia','concepto'])current.datos[name]=data.get(name);
    current.datos.moneda=String(current.datos.moneda).trim().toUpperCase();
  }
  function renderLines(){
    const d=current.datos;
    $e('[data-pending]').innerHTML=`<table><thead><tr><th>Pagar</th><th>Factura</th><th>Vencimiento</th><th>Valor original</th><th>Saldo pendiente</th></tr></thead><tbody>${options.facturas.filter(x=>x.moneda.trim()===d.moneda).map(x=>`<tr><td><input type="checkbox" data-pick="${x.id}" aria-label="Pagar factura ${esc(x.numero)}" ${d.lineas.some(l=>l.documentoPorPagarId===x.id)?'checked':''}></td><td>${esc(x.numero)}</td><td>${esc(x.vence)}</td><td>${money(x.original,x.moneda)}</td><td>${money(x.saldo,x.moneda)}</td></tr>`).join('')||'<tr><td colspan="5">Selecciona un proveedor con facturas pendientes.</td></tr>'}</tbody></table>`;
    dialog.querySelectorAll('[data-pick]').forEach(box=>box.onchange=()=>{const inv=options.facturas.find(x=>x.id===Number(box.dataset.pick));d.lineas=d.lineas.filter(l=>l.documentoPorPagarId!==inv.id);if(box.checked)d.lineas.push({tipo:'FACTURA',documentoPorPagarId:inv.id,cuenta:'',concepto:'Abono factura '+inv.numero,valor:Math.floor(inv.saldo*100+1e-6)/100});dirty=true;renderLines();});
    $e('[data-lines]').innerHTML=d.lineas.map((l,i)=>`<tr data-row="${i}"><td>${l.tipo==='FACTURA'?`<select data-factura required aria-label="Factura"><option value="">Selecciona factura…</option>${options.facturas.filter(x=>x.moneda.trim()===d.moneda).map(x=>`<option value="${x.id}" ${Number(l.documentoPorPagarId)===x.id?'selected':''}>${esc(x.numero+' · Saldo '+money(x.saldo,x.moneda))}</option>`).join('')}${l.documentoPorPagarId&&!options.facturas.some(x=>x.id===Number(l.documentoPorPagarId)&&x.moneda.trim()===d.moneda)?`<option value="${l.documentoPorPagarId}" selected>Obligación ${l.documentoPorPagarId}: revisar saldo / moneda</option>`:''}</select>`:'Gasto ocasional'}</td>
      <td><input data-concepto aria-label="Concepto de línea" maxlength="200" required value="${esc(l.concepto)}"></td><td>${l.tipo==='GASTO'?`<input data-cuenta aria-label="Cuenta del gasto" maxlength="20" value="${esc(l.cuenta)}">`:'De la obligación'}</td>
      <td><input data-valor aria-label="Abono o valor" type="number" step="0.01" min="0.01" max="1000000000000" required value="${esc(l.valor)}"></td><td><button class="button secondary" type="button" data-remove aria-label="Quitar línea">Quitar</button></td></tr>`).join('');
    dialog.querySelectorAll('[data-row]').forEach(row=>{
      const i=Number(row.dataset.row),l=d.lineas[i];
      row.querySelector('[data-factura]')?.addEventListener('change',e=>{const inv=options.facturas.find(x=>x.id===Number(e.target.value));l.documentoPorPagarId=inv?.id??null;l.concepto=inv?'Abono factura '+inv.numero:'';l.valor=inv?Math.floor(inv.saldo*100+1e-6)/100:0;dirty=true;renderLines();});
      row.querySelector('[data-concepto]').oninput=e=>{l.concepto=e.target.value;};
      row.querySelector('[data-cuenta]')?.addEventListener('input',e=>{l.cuenta=e.target.value;});
      row.querySelector('[data-valor]').oninput=e=>{l.valor=Number(e.target.value);total();};
      row.querySelector('[data-remove]').onclick=()=>{d.lineas.splice(i,1);dirty=true;renderLines();};
    });total();
  }
  function total(){const d=current.datos;try{$e('[data-total]').textContent='Total a pagar: '+money(d.lineas.reduce((s,l)=>s+Math.round(l.valor*100),0)/100,d.moneda);}catch{$e('[data-total]').textContent='Revisa la moneda';}}
  function beneficiaryOptions(){
    $e('#egresoBeneficiarios').innerHTML=options.beneficiarios.map(x=>`<option value="${esc(beneficiaryLabel(x))}"></option>`).join('');
  }
  function beneficiaryInput(){
    clearTimeout(beneficiaryTimer);const request=++beneficiaryRequest;
    if(busy)return;
    const input=$e('[data-beneficiary]'),term=input.value;
    const selected=[current.beneficiario,...options.beneficiarios].find(x=>x&&beneficiaryLabel(x)===term);
    input.setCustomValidity(selected?'':'Selecciona un beneficiario de los resultados.');
    if(selected){void changeSupplier(selected);return;}
    const token=generation;
    $e('[data-options-note]').textContent='Buscando beneficiarios…';
    beneficiaryTimer=setTimeout(async()=>{
      if(!valid(token)||request!==beneficiaryRequest)return;
      try{
        const data=await apiRequest(url()+'/options?q='+encodeURIComponent(term.trim().slice(0,120)));
        if(!valid(token)||request!==beneficiaryRequest||$e('[data-beneficiary]')?.value!==term)return;
        options.beneficiarios=data.beneficiarios;beneficiaryOptions();
        $e('[data-options-note]').textContent=data.masBeneficiarios?'Escribe más letras o números para afinar la búsqueda.':data.beneficiarios.length?'Selecciona el beneficiario en los resultados.':'No se encontraron beneficiarios.';
      }catch(e){if(valid(token)&&request===beneficiaryRequest)$e('[data-options-note]').textContent='No se pudo buscar: '+e.message;}
    },250);
  }
  async function changeSupplier(selected){
    if(String(current.datos.terceroId)===String(selected.id)){$e('[data-options-note]').textContent='';return;}
    const restore=()=>{$e('[data-beneficiary]').value=beneficiaryLabel(current.beneficiario);$e('[data-beneficiary]').setCustomValidity('');};
    if(current.datos.lineas.some(l=>l.tipo==='FACTURA')&&!confirm('Al cambiar beneficiario se quitarán las facturas seleccionadas. ¿Continuar?')){restore();return;}
    capture();const token=generation;busy=true;$e('fieldset').disabled=true;
    try{
      const data=await apiRequest(url()+'/options?terceroId='+encodeURIComponent(selected.id));if(!valid(token))return;
      current.beneficiario=selected;current.datos.terceroId=String(selected.id);$e('[name="terceroId"]').value=selected.id;
      current.datos.lineas=current.datos.lineas.filter(l=>l.tipo!=='FACTURA');dirty=true;
      options.facturas=data.facturas;renderLines();$e('[data-options-note]').textContent='';notice('');
    }catch(e){if(valid(token)){restore();notice('No se pudieron cargar las facturas: '+e.message,true);}}
    finally{busy=false;if(valid(token)&&$e('fieldset'))$e('fieldset').disabled=false;}
  }
  async function save(event){
    event.preventDefault();if(busy)return;capture();
    if(!current.beneficiario||$e('[data-beneficiary]').value!==beneficiaryLabel(current.beneficiario)){notice('Selecciona un beneficiario de los resultados.',true);return;}
    if(!current.datos.lineas.length){notice('Agrega al menos una factura o gasto.',true);return;}
    if(!confirm('Se contabilizará el egreso y se descontarán los abonos de la cartera. ¿Continuar?'))return;
    const token=++generation;const target=url()+(current.id?'/'+current.id:'');
    const body={...current.datos,sucursalId:Number(current.datos.sucursalId),terceroId:Number(current.datos.terceroId)};
    busy=true;$e('fieldset').disabled=true;notice('Validando y contabilizando egreso…');
    try{
      const result=await apiRequest(target,{method:current.id?'PUT':'POST',body:JSON.stringify(body)});if(!valid(token))return;
      dirty=false;searchTerm='CE-'+result.id;await listing();notice('Egreso CE-'+result.id+' contabilizado en el ERP. Consulta aquí el resultado de Zeus. No vuelvas a registrar este pago.');
    }catch(e){if(valid(token))notice(e.message,true);}
    finally{busy=false;if(valid(token)&&$e('fieldset'))$e('fieldset').disabled=false;}
  }
  function accountHint(){const a=accounts.find(x=>x.sucursalId===Number(current?.datos.sucursalId)&&x.medioPago===current?.datos.medioPago);if($e('[data-account]'))$e('[data-account]').textContent=a?`Salida: ${a.cuenta} · ${a.nombre}`:'Falta configurar caja/banco de esta sucursal y medio de pago.';}
  async function view(id){const token=++generation;shell();try{const result=await apiRequest(url()+'/'+id);if(!valid(token))return;const d=result.datos;$e('[data-content]').innerHTML=`<h3>CE-${id} · Contabilizado</h3><p>${esc(d.concepto)} · ${esc(d.fechaContable)} · ${money(result.asiento.origen.total)}</p><div class="table-wrap"><table><thead><tr><th>Cuenta</th><th>Concepto</th><th>Débito</th><th>Crédito</th></tr></thead><tbody>${result.asiento.movimientos.map(m=>`<tr><td>${esc(m.regla.cuenta)}</td><td>${esc(m.regla.concepto)}</td><td>${m.valor>0?money(m.valor):''}</td><td>${m.valor<0?money(-m.valor):''}</td></tr>`).join('')}</tbody></table></div><h3>Aplicaciones a facturas</h3><p>${result.asiento.egreso.facturas.map(f=>esc(f.numero)+' · '+money(f.valor)).join('<br>')||'Sin aplicaciones de cartera'}</p><button class="button secondary" data-back>Volver</button>`;$e('[data-back]').onclick=()=>listing();}catch(e){if(valid(token))notice(e.message,true);}}
  window.loadZeusCashAccounts=configure;
  async function configure(scope){
    const root=document.querySelector('#zeusCashAccounts');if(!root||!zeusCurrent(scope))return;
    const company=state.erpSession.company.id;
    const url=()=>`/api/v1/companies/${company}/disbursements`;
    const $e=s=>root.querySelector(s),valid=()=>zeusCurrent(scope)&&root.isConnected&&String(company)===String(state.erpSession?.company?.id);
    let busy=false;const token=0;
    root.innerHTML='<p data-notice role="status"></p><div data-content></div>';
    const notice=(text)=>{if(valid())$e('[data-notice]').textContent=text;};
    notice('Consultando cuentas y medios de pago de Zeus…');
    try{const [{opts,saved},chart]=await Promise.all([apiRequest(url()+'/cash-configuration'),apiRequest(url()+'/cash-chart')]);if(!valid(token))return;
      $e('[data-content]').innerHTML=`<form data-config-form><fieldset><h3>Caja / banco por sucursal</h3><div class="egreso-grid"><label>Sucursal<select name="branch" required>${opts.sucursales.map(x=>`<option value="${x.id}">${esc(x.nombre)}</option>`).join('')}</select></label><label>Medio de pago<select name="method"><option>TRANSFERENCIA</option><option>EFECTIVO</option><option>CHEQUE</option></select></label><label class="egreso-wide">Cuenta en Zeus<select name="account" required><option value="">Selecciona…</option>${chart.cuentas.map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label><label class="egreso-wide">Medio de pago en Zeus<select name="currency" required><option value="">Selecciona…</option>${chart.medios.map(x=>`<option value="${esc(x.codigo)}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label></div><div class="egreso-toolbar"><button class="button primary">Guardar configuración</button><button type="button" class="button secondary" data-back>Volver</button></div></fieldset></form>`;
      const selected=()=>saved.find(x=>x.sucursalId===Number($e('[name="branch"]').value)&&x.medioPago===$e('[name="method"]').value);
      const fill=()=>{const s=selected();$e('[name="account"]').value=s?.cuenta||'';$e('[name="currency"]').value=s?.monedaZeus||'';};$e('[name="branch"]').onchange=fill;$e('[name="method"]').onchange=fill;fill();
      $e('[data-back]').remove();$e('[data-config-form]').onsubmit=async e=>{e.preventDefault();e.stopPropagation();if(busy||!valid())return;const body={sucursalId:Number($e('[name="branch"]').value),medioPago:$e('[name="method"]').value,cuenta:$e('[name="account"]').value,monedaZeus:$e('[name="currency"]').value,version:selected()?.version||0};busy=true;$e('fieldset').disabled=true;try{await apiRequest(url()+'/accounts',{method:'PUT',body:JSON.stringify(body)});if(valid(token)){await configure(scope);notice('Configuración guardada.');}}catch(err){if(valid(token))notice(err.message,true);}finally{busy=false;if(valid(token)&&$e('fieldset'))$e('fieldset').disabled=false;}};notice('');
    }catch(e){if(valid(token))notice(e.message,true);}
  }
})();
