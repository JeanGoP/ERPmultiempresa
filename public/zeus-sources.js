/* La seleccion operativa se resuelve en el servidor, nunca en el formulario de compra. */
let zeusSourceUsers=null;
let zeusSourceBranches=null;
function zeusBranchOptions(id,name=''){
  const active=(zeusSourceBranches||[]).filter(b=>b.activa);
  const selected=active.find(b=>id?b.id===Number(id):b.nombre.trim().toLocaleLowerCase()===name.trim().toLocaleLowerCase());
  return `<option value="">${zeusSourceBranches===null?'Cargando sucursales…':active.length?'Selecciona sucursal…':'Crea una sucursal en Datos maestros → Sucursales'}</option>`+active.map(b=>`<option value="${b.id}" ${b===selected?'selected':''}>${zeusEscape(b.codigo)} · ${zeusEscape(b.nombre)}</option>`).join('')+(!selected&&(id||name)?`<option value="" selected disabled>${zeusEscape(name||'Sucursal guardada')} · pendiente de validar</option>`:'');
}
const zeusSourceMovements={ENTRADA_MERCANCIA:'Entrada de mercancía',FACTURACION:'Facturación (preparación)',RECIBO_CAJA:'Recibo de caja (preparación)',EGRESO:'Comprobante de egreso (preparación)'};
function zeusSourceRow(rule={}){
  const users=rule.usuarios||[];
  return `<div class="zeus-source-rule zeus-grid"><label>Sucursal / punto<select name="sourceBranch" required data-branch-id="${zeusEscape(rule.sucursalId||'')}" data-branch-name="${zeusEscape(rule.sucursal||'')}">${zeusBranchOptions(rule.sucursalId,rule.sucursal||'')}</select></label><label>Movimiento<select name="sourceMovement">${Object.entries(zeusSourceMovements).map(([id,label])=>`<option value="${id}" ${rule.movimiento===id?'selected':''}>${label}</option>`).join('')}</select></label><label>Fuente<input name="sourceCode" maxlength="2" minlength="2" required value="${zeusEscape(rule.fuente||'')}"></label><label>Serie<input name="sourceSeries" maxlength="2" pattern="[0-9]{2}" required value="${zeusEscape(rule.serie||'00')}"></label><label>Asignación<select name="sourceScope"><option value="users">Usuarios específicos</option><option value="default" ${rule.usuarios&&users.length===0?'selected':''}>Predeterminada del movimiento</option></select></label><label>Usuarios<select name="sourceUsers" multiple size="3" aria-label="Usuarios asignados a esta fuente">${(zeusSourceUsers||users.map(id=>({usuarioId:id,nombre:`Usuario ${id}`}))).map(u=>`<option value="${u.usuarioId}" ${users.includes(u.usuarioId)?'selected':''}>${zeusEscape(u.nombre)}</option>`).join('')}</select></label><button type="button" class="button secondary" data-source-action="remove">Quitar</button></div>`;
}
function zeusSourcesSection(settings){
  zeusSourceUsers=null;
  zeusSourceBranches=null;
  return `<section class="zeus-card"><h2>4. Fuentes automáticas</h2><p>La fuente se asigna sin preguntar al contabilizar. Una asignación por usuario y movimiento; opcionalmente una predeterminada. Sin reglas de entradas se mantiene la fuente general actual.</p><div id="zeusSourceRules">${(settings.fuentesAutomaticas||[]).map(zeusSourceRow).join('')}</div><button type="button" class="button secondary" data-source-action="add">+ Agregar fuente</button><p id="zeusSourceStatus" role="status"></p></section>`;
}
async function zeusLoadSourceUsers(scope){
  try{
    const [users,branches]=await Promise.all([apiRequest(`${scope.base}/routing-users`),apiRequest(`${scope.base.replace(/\/zeus$/,'')}/master-data/branches`)]);if(!zeusCurrent(scope)||!$('#zeusSourceRules'))return;
    zeusSourceBranches=branches;
    document.querySelectorAll('#zeusSourceRules [name=sourceBranch]').forEach(select=>{select.innerHTML=zeusBranchOptions(select.value||select.dataset.branchId,select.dataset.branchName||'');});
    zeusSourceUsers=users;
    document.querySelectorAll('#zeusSourceRules [name=sourceUsers]').forEach(select=>{
      const selected=[...select.selectedOptions].map(o=>Number(o.value));
      const options=[...users,...selected.filter(id=>!users.some(u=>u.usuarioId===id)).map(id=>({usuarioId:id,nombre:`Usuario ${id} · revisar acceso`}))];
      select.innerHTML=options.map(u=>`<option value="${u.usuarioId}" ${selected.includes(u.usuarioId)?'selected':''}>${zeusEscape(u.nombre)}</option>`).join('');
    });
  }catch(error){if(zeusCurrent(scope)&&$('#zeusSourceStatus'))$('#zeusSourceStatus').textContent=`No se pudieron consultar sucursales y usuarios: ${error.message}`;}
}
function zeusReadSources(settings){
  if(!$('#zeusSourceRules'))return settings.fuentesAutomaticas??null;
  const assignments=new Set(),defaults=new Set();
  return [...document.querySelectorAll('.zeus-source-rule')].map(row=>{
    const value=name=>row.querySelector(`[name=${name}]`).value.trim();
    const usuarios=value('sourceScope')==='default'?[]:[...row.querySelector('[name=sourceUsers]').selectedOptions].map(o=>Number(o.value));
    if(value('sourceScope')!=='default'&&!usuarios.length)throw new Error('Selecciona los usuarios de cada fuente o márcala como predeterminada.');
    const movimiento=value('sourceMovement');
    if(!usuarios.length){if(defaults.has(movimiento))throw new Error('Solo puede haber una fuente predeterminada por movimiento.');defaults.add(movimiento);}
    for(const user of usuarios){const key=`${movimiento}:${user}`;if(assignments.has(key))throw new Error('Un usuario no puede tener dos fuentes para el mismo movimiento.');assignments.add(key);}
    const branch=(zeusSourceBranches||[]).find(b=>b.id===Number(value('sourceBranch'))&&b.activa);
    if(!branch)throw new Error('Selecciona una sucursal activa del catálogo de esta empresa.');
    return {sucursalId:branch.id,sucursal:branch.nombre,movimiento,fuente:value('sourceCode'),serie:value('sourceSeries'),usuarios};
  });
}
function zeusSourceClick(button){
  if(!button.dataset.sourceAction)return false;
  if(button.dataset.sourceAction==='add')$('#zeusSourceRules').insertAdjacentHTML('beforeend',zeusSourceRow());else button.closest('.zeus-source-rule').remove();
  zeusUI.dirty=true;return true;
}
