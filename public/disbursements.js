/* Borradores persistentes; deliberadamente no contabiliza ni modifica saldos. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const dialog=document.createElement('dialog');dialog.id='disbursementDialog';dialog.className='erp-dialog egreso-dialog';
  dialog.setAttribute('aria-label','Comprobantes de egreso');document.body.append(dialog);
  let generation=0,company=null,current=null,options=null,dirty=false,busy=false,next=null;
  const $e=s=>dialog.querySelector(s);
  const url=()=>`/api/v1/companies/${company}/disbursement-drafts`;
  const valid=token=>token===generation&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  const money=(n,c)=>new Intl.NumberFormat('es-CO',{style:'currency',currency:c||'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(n||0);
  const notice=(text,error=false)=>{const e=$e('[data-notice]');if(e){e.textContent=text;e.classList.toggle('error',error);}};
  function close(force=false){if(!force&&(busy||dirty&&!confirm('Hay cambios sin guardar. ¿Cerrar el borrador?')))return;generation++;dirty=false;dialog.close();current=null;company=null;}
  window.resetEgresos=()=>close(true);
  dialog.addEventListener('cancel',e=>{e.preventDefault();close();});
  function shell(){
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">TESORERÍA · ${esc(state.erpSession?.company?.name||'Empresa activa')}</span><h2>Comprobantes de egreso</h2></div><button type="button" class="dialog-close" data-close aria-label="Cerrar">×</button></div>
      <p class="egreso-stage">Borradores · No descuentan cartera ni mueven banco/caja. Contabilización y envío a Zeus pendientes de habilitar.</p>
      <p data-notice role="status" aria-live="polite"></p><div data-content></div>`;
    $e('[data-close]').onclick=()=>close();
  }
  async function listing(before=null){
    const token=++generation;current=null;dirty=false;shell();notice('Consultando borradores…');
    try{
      const data=await apiRequest(url()+(before?'?antes='+before:''));if(!valid(token))return;
      next=data.siguiente;
      $e('[data-content]').innerHTML=`<div class="egreso-toolbar"><button type="button" class="button primary" data-new>Nuevo borrador</button><button type="button" class="button secondary" data-refresh>Actualizar</button></div>
        <div class="table-wrap"><table><thead><tr><th>Borrador</th><th>Fecha contable</th><th>Beneficiario</th><th>Total</th><th>Estado</th><th></th></tr></thead><tbody>${data.items.map(x=>`<tr><td>B-${x.id}</td><td>${esc(x.fecha)}</td><td>${esc(x.beneficiario)}</td><td>${esc(money(x.total,x.moneda))}</td><td>Borrador</td><td><button type="button" class="button secondary" data-open="${x.id}">Abrir</button></td></tr>`).join('')||'<tr><td colspan="6">No hay borradores guardados.</td></tr>'}</tbody></table></div>
        <div class="egreso-toolbar"><button type="button" class="button secondary" data-first>Primera página</button><button type="button" class="button secondary" data-next ${next?'':'disabled'}>Siguientes</button></div>`;
      notice('');$e('[data-new]').onclick=()=>edit();$e('[data-refresh]').onclick=()=>listing(before);$e('[data-first]').onclick=()=>listing();$e('[data-next]').onclick=()=>listing(next);
      dialog.querySelectorAll('[data-open]').forEach(b=>b.onclick=()=>edit(Number(b.dataset.open)));
    }catch(e){if(valid(token))notice(e.message,true);}
  }
  window.openEgresos=async()=>{
    if(!state.erpSession?.api||!hasPermission('TESORERIA.EGRESO.PREPARAR')){showError('Requiere conexión al ERP y permiso para preparar egresos.');return;}
    if(dialog.open)return;
    company=state.erpSession.company.id;dialog.showModal();await listing();
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
    }catch(e){if(valid(token))notice(e.message,true);}
  }
  function form(){
    const d=current.datos;
    const input=(name,label,max,required=false,type='text')=>`<label>${label}<input name="${name}" type="${type}" value="${esc(d[name])}" maxlength="${max}" ${required?'required':''}></label>`;
    $e('[data-content]').innerHTML=`<form data-form><fieldset><div class="egreso-toolbar"><h3>${current.id?'Borrador B-'+current.id:'Nuevo egreso'}</h3><span>Sin contabilizar</span></div>
      <div class="egreso-grid"><label>Sucursal<select name="sucursalId" required><option value="">Selecciona…</option>${options.sucursales.map(x=>`<option value="${x.id}">${esc(x.codigo+' · '+x.nombre)}</option>`).join('')}</select></label>
      ${input('fechaContable','Fecha contable',10,true,'date')}${input('moneda','Moneda',3,true)}
      <label>Medio de pago<select name="medioPago"><option>TRANSFERENCIA</option><option>EFECTIVO</option><option>CHEQUE</option></select></label>
      <label class="egreso-wide">Buscar beneficiario por nombre o identificación<div class="egreso-search"><input data-search maxlength="120"><button type="button" class="button secondary" data-search-button>Buscar</button></div></label>
      <label class="egreso-wide">Beneficiario<select name="terceroId" required><option value="">Selecciona…</option>${options.beneficiarios.map(x=>`<option value="${x.id}">${esc(x.identificacion+' · '+x.nombre)}</option>`).join('')}</select></label>
      ${input('bancoCaja','Banco / caja (provisional)',100)}${input('cuentaSalida','Cuenta de salida (sin validar en Zeus)',20)}${input('referencia','Referencia del pago',80)}
      <label class="egreso-wide">Concepto<input name="concepto" value="${esc(d.concepto)}" maxlength="300" required></label></div>
      <p data-options-note class="egreso-help"></p>
      <div class="egreso-toolbar"><h3>Facturas y gastos</h3><button type="button" class="button secondary" data-invoice>Agregar factura</button><button type="button" class="button secondary" data-expense>Agregar gasto ocasional</button></div>
      <div class="table-wrap"><table><thead><tr><th>Tipo / factura</th><th>Concepto</th><th>Cuenta de gasto</th><th>Abono / valor</th><th></th></tr></thead><tbody data-lines></tbody></table></div>
      <p class="egreso-help">Las cuentas son propuestas del borrador, aún no validadas en Zeus. Los abonos no reservan saldo; se comprobarán nuevamente al contabilizar. No repitas como gasto una obligación ya registrada.</p>
      <div class="egreso-toolbar"><strong data-total></strong><button type="submit" class="button primary">Guardar borrador</button><button type="button" class="button secondary" data-back>Volver a borradores</button></div>
      </fieldset></form>`;
    for(const name of ['sucursalId','terceroId','medioPago'])$e(`[name="${name}"]`).value=d[name];
    $e('[data-options-note]').textContent=options.masBeneficiarios?'Hay más beneficiarios: busca por identificación o nombre.':'';
    $e('[data-form]').addEventListener('input',()=>{dirty=true;});
    $e('[name="terceroId"]').onchange=()=>changeSupplier();
    $e('[name="moneda"]').onchange=()=>{capture();renderLines();};
    $e('[data-search-button]').onclick=()=>search();
    $e('[data-search]').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();void search();}};
    $e('[data-invoice]').onclick=()=>{capture();if(!d.terceroId){notice('Selecciona primero un beneficiario.',true);return;}d.lineas.push({tipo:'FACTURA',documentoPorPagarId:null,cuenta:'',concepto:'',valor:0});dirty=true;renderLines();};
    $e('[data-expense]').onclick=()=>{capture();d.lineas.push({tipo:'GASTO',documentoPorPagarId:null,cuenta:'',concepto:'',valor:0});dirty=true;renderLines();};
    $e('[data-back]').onclick=()=>{if(!dirty||confirm('¿Salir sin guardar los cambios?'))void listing();};
    $e('[data-form]').onsubmit=save;renderLines();
  }
  function capture(){
    const f=$e('[data-form]');if(!f)return;const data=new FormData(f);
    for(const name of ['sucursalId','terceroId','fechaContable','moneda','medioPago','bancoCaja','cuentaSalida','referencia','concepto'])current.datos[name]=data.get(name);
    current.datos.moneda=String(current.datos.moneda).trim().toUpperCase();
  }
  function renderLines(){
    const d=current.datos;
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
    if(options.masFacturas)notice('Se muestran las primeras 500 facturas con saldo. Este borrador permite hasta 100 líneas.');
  }
  function total(){const d=current.datos;try{$e('[data-total]').textContent='Total propuesto: '+money(d.lineas.reduce((s,l)=>s+Math.round(l.valor*100),0)/100,d.moneda);}catch{$e('[data-total]').textContent='Revisa la moneda';}}
  async function search(){
    if(busy)return;
    capture();const token=++generation;const term=$e('[data-search]').value;
    busy=true;$e('fieldset').disabled=true;
    try{const data=await apiRequest(url()+'/options?q='+encodeURIComponent(term)+(current.datos.terceroId?'&terceroId='+current.datos.terceroId:''));if(!valid(token))return;options=data;form();}
    catch(e){if(valid(token))notice(e.message,true);}
    finally{busy=false;if(valid(token)&&$e('fieldset'))$e('fieldset').disabled=false;}
  }
  async function changeSupplier(){
    const previous=current.datos.terceroId;
    if(current.datos.lineas.some(l=>l.tipo==='FACTURA')&&!confirm('Al cambiar beneficiario se quitarán las facturas seleccionadas. ¿Continuar?')){$e('[name="terceroId"]').value=previous;return;}
    capture();current.datos.lineas=current.datos.lineas.filter(l=>l.tipo!=='FACTURA');dirty=true;
    options.facturas=[];renderLines();await search();
  }
  async function save(event){
    event.preventDefault();if(busy)return;capture();
    if(!current.datos.lineas.length){notice('Agrega al menos una factura o gasto.',true);return;}
    const token=++generation;const target=url()+(current.id?'/'+current.id:'');
    const body={...current.datos,sucursalId:Number(current.datos.sucursalId),terceroId:Number(current.datos.terceroId)};
    busy=true;$e('fieldset').disabled=true;notice('Guardando borrador…');
    try{
      const result=await apiRequest(target,{method:current.id?'PUT':'POST',body:JSON.stringify(body)});if(!valid(token))return;
      current.id=result.id;current.datos.version=result.version;dirty=false;form();notice('Borrador B-'+result.id+' guardado. No se afectó cartera ni se envió a Zeus.');
    }catch(e){if(valid(token))notice(e.message,true);}
    finally{busy=false;if(valid(token)&&$e('fieldset'))$e('fieldset').disabled=false;}
  }
})();
