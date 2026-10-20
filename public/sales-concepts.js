/* Maestro de conceptos de venta: las cuentas se eligen del plan activo de Zeus. */
(() => {
  const nav=document.querySelector('#salesConceptsNav');if(!nav)return;
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog sales-concepts-dialog';document.body.append(dialog);
  const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const inBody=concept=>concept.mostrarEnCuerpo??concept.ubicacionFormato!=='TOTALES';
  const inTotals=concept=>concept.mostrarEnTotales??concept.ubicacionFormato==='TOTALES';
  let company=0,items=[],accounts=[],editing=null,busy=false;
  const $=selector=>dialog.querySelector(selector);
  const url=()=>`/api/v1/companies/${company}/master-data/sales-concepts`;
  const notice=(message,error=false)=>{const el=$('[data-message]');if(el){el.textContent=message;el.classList.toggle('error',error);}};
  async function load(){
    notice('Cargando conceptos y plan de cuentas…');
    try{
      const [concepts,chart]=await Promise.all([apiRequest(url()),apiRequest(url()+'/accounts')]);
      if(!dialog.open||company!==state.erpSession?.company?.id)return;
      items=concepts;accounts=chart;render();notice('');
    }catch(error){notice(error.message,true);}
  }
  function render(){
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">VENTAS · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>Conceptos de venta</h2></div><button type="button" class="dialog-close" data-close aria-label="Cerrar">×</button></div>
      <p data-message role="status" aria-live="polite"></p>
      <form data-form><div class="egreso-grid"><label>Código<input name="codigo" maxlength="30" required placeholder="FINANCIACION"></label><label class="egreso-wide">Nombre<input name="nombre" maxlength="120" required placeholder="Financiación"></label>
      <label class="egreso-wide">Cuenta de ingreso en Zeus<select name="cuentaIngresoZeus" required><option value="">Selecciona cuenta…</option>${accounts.map(a=>`<option value="${esc(a.codigo)}">${esc(a.codigo+' · '+a.nombre)}</option>`).join('')}</select></label>
      <label><input name="activo" type="checkbox" checked> Activo</label></div>
      <fieldset class="sales-concept-format"><legend>Mostrar en el formato</legend><label><input name="mostrarEnCuerpo" type="checkbox" checked> En el cuerpo de la factura</label><label><input name="mostrarEnTotales" type="checkbox"> En los totales de la factura</label></fieldset>
      <p class="egreso-help">El código FINANCIACION requiere una cuenta 4135. Puedes marcar ambas opciones, una sola o ninguna; la selección se conserva en cada factura emitida.</p>
      <div class="egreso-toolbar"><button type="submit" class="button primary">Guardar concepto</button><button type="button" class="button secondary" data-clear>Nuevo</button></div></form>
      <div class="table-wrap"><table><thead><tr><th>Código</th><th>Concepto</th><th>Cuenta Zeus</th><th>Formato</th><th>Estado</th><th></th></tr></thead><tbody>${items.map(x=>`<tr><td>${esc(x.codigo)}</td><td>${esc(x.nombre)}</td><td>${esc(x.cuentaIngresoZeus)}</td><td>${[inBody(x)?'Cuerpo':'',inTotals(x)?'Totales':''].filter(Boolean).join(' y ')||'No mostrar'}</td><td>${x.activo?'Activo':'Inactivo'}</td><td><button type="button" class="button secondary" data-edit="${x.id}">Editar</button></td></tr>`).join('')||'<tr><td colspan="6">Aún no hay conceptos.</td></tr>'}</tbody></table></div>`;
    $('[data-close]').onclick=()=>dialog.close();$('[data-clear]').onclick=()=>{editing=null;$('[data-form]').reset();notice('');};
    $('[data-form]').onsubmit=save;
    dialog.querySelectorAll('[data-edit]').forEach(button=>button.onclick=()=>{editing=items.find(x=>x.id===Number(button.dataset.edit));const f=$('[data-form]');f.elements.codigo.value=editing.codigo;f.elements.nombre.value=editing.nombre;f.elements.cuentaIngresoZeus.value=editing.cuentaIngresoZeus;f.elements.mostrarEnCuerpo.checked=inBody(editing);f.elements.mostrarEnTotales.checked=inTotals(editing);f.elements.activo.checked=editing.activo;f.scrollIntoView({block:'start',behavior:'smooth'});});
  }
  async function save(event){
    event.preventDefault();if(busy)return;const f=event.target;
    const input={codigo:f.elements.codigo.value.trim().toUpperCase(),nombre:f.elements.nombre.value.trim(),cuentaIngresoZeus:f.elements.cuentaIngresoZeus.value,mostrarEnCuerpo:f.elements.mostrarEnCuerpo.checked,mostrarEnTotales:f.elements.mostrarEnTotales.checked,activo:f.elements.activo.checked,version:editing?.version||0};
    input.ubicacionFormato=input.mostrarEnTotales&&!input.mostrarEnCuerpo?'TOTALES':'CUERPO'; // Compatibilidad durante el despliegue del backend.
    if(input.codigo==='FINANCIACION'&&!input.cuentaIngresoZeus.startsWith('4135')){notice('La financiación requiere una cuenta 4135.',true);return;}
    busy=true;const button=f.querySelector('[type="submit"]');button.disabled=true;
    try{await apiRequest(editing?url()+'/'+editing.id:url(),{method:editing?'PUT':'POST',body:JSON.stringify(input)});editing=null;await load();notice('Concepto guardado.');}
    catch(error){notice(error.message,true);}finally{busy=false;if(button.isConnected)button.disabled=false;}
  }
  nav.addEventListener('click',()=>{if(!state.erpSession?.api||!hasPermission('MAESTROS.CONCEPTO_VENTA.ADMINISTRAR'))return;company=state.erpSession.company.id;editing=null;dialog.innerHTML='<p data-message>Cargando…</p>';dialog.showModal();void load();});
})();
