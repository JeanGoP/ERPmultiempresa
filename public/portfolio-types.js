/* Clasificación configurable de la cartera por empresa. Los códigos usados en facturas no se eliminan. */
(() => {
  const nav=document.querySelector('#portfolioTypesNav');if(!nav)return;
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog';document.body.append(dialog);
  const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  let company=0,items=[],editing=null,busy=false;
  const $=selector=>dialog.querySelector(selector);
  const url=()=>`/api/v1/companies/${company}/master-data/portfolio-types`;
  const notice=(message,error=false)=>{const el=$('[data-message]');if(el){el.textContent=message;el.classList.toggle('error',error);}};
  function render(){
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">VENTAS · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>Tipos de cartera</h2></div><button type="button" class="dialog-close" data-close aria-label="Cerrar">×</button></div>
      <p class="egreso-help">Clasifica facturas y filtra cuentas por cobrar. Desactivar un tipo impide usarlo en nuevas facturas, pero conserva la clasificación histórica.</p>
      <p data-message role="status" aria-live="polite"></p>
      <form data-form><div class="egreso-grid"><label>Código<input name="codigo" maxlength="20" required placeholder="ELECTRO"></label><label class="egreso-wide">Nombre<input name="nombre" maxlength="80" required placeholder="Electrodomésticos"></label><label>Estado<select name="activo"><option value="true">Activo</option><option value="false">Inactivo</option></select></label></div>
      <div class="egreso-toolbar"><button type="submit" class="button primary">Guardar tipo</button><button type="button" class="button secondary" data-clear>Nuevo</button></div></form>
      <div class="table-wrap"><table><thead><tr><th>Código</th><th>Tipo de cartera</th><th>Estado</th><th></th></tr></thead><tbody>${items.map(x=>`<tr><td>${esc(x.codigo)}</td><td>${esc(x.nombre)}</td><td>${x.activo?'Activo':'Inactivo'}</td><td><button type="button" class="button secondary" data-edit="${x.id}">Editar</button></td></tr>`).join('')||'<tr><td colspan="4">No hay tipos de cartera.</td></tr>'}</tbody></table></div>`;
    $('[data-close]').onclick=()=>dialog.close();
    $('[data-clear]').onclick=()=>{editing=null;$('[data-form]').reset();$('[data-form]').elements.codigo.readOnly=false;$('[data-form]').elements.activo.disabled=false;notice('');};
    $('[data-form]').onsubmit=save;
    dialog.querySelectorAll('[data-edit]').forEach(button=>button.onclick=()=>{
      editing=items.find(x=>x.id===Number(button.dataset.edit));const form=$('[data-form]');
      form.elements.codigo.value=editing.codigo;form.elements.codigo.readOnly=true;
      form.elements.nombre.value=editing.nombre;form.elements.activo.value=String(editing.activo);
      form.elements.activo.disabled=editing.codigo==='SIN_CLASIFICAR';
      form.elements.codigo.focus();
    });
  }
  async function load(){
    notice('Cargando tipos…');const selectedCompany=company;
    try{const result=await apiRequest(url());if(!dialog.open||company!==selectedCompany)return;items=result;editing=null;render();notice('');}
    catch(error){if(dialog.open&&company===selectedCompany)notice(error.message,true);}
  }
  async function save(event){
    event.preventDefault();if(busy)return;const form=event.target;
    const input={codigo:form.elements.codigo.value.trim().toUpperCase(),nombre:form.elements.nombre.value.trim(),activo:form.elements.activo.value==='true',version:editing?.version||0};
    busy=true;const button=form.querySelector('[type="submit"]');button.disabled=true;
    try{await apiRequest(editing?url()+'/'+editing.id:url(),{method:editing?'PUT':'POST',body:JSON.stringify(input)});await load();notice('Tipo de cartera guardado.');}
    catch(error){notice(error.message,true);}finally{busy=false;if(button.isConnected)button.disabled=false;}
  }
  nav.addEventListener('click',()=>{
    if(!state.erpSession?.api||!hasPermission('MAESTROS.TIPO_CARTERA.ADMINISTRAR')||dialog.open)return;
    company=state.erpSession.company.id;editing=null;dialog.innerHTML='<p data-message>Cargando tipos…</p>';dialog.showModal();void load();
  });
})();
