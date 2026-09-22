/* La seleccion operativa se resuelve en el servidor, nunca en el formulario de compra. */
let zeusSourceUsers=null;
const zeusSourceMovements={ENTRADA_MERCANCIA:'Entrada de mercancía',FACTURACION:'Facturación (preparación)',RECIBO_CAJA:'Recibo de caja (preparación)',EGRESO:'Comprobante de egreso (preparación)'};
function zeusSourceRow(rule={}){
  const users=rule.usuarios||[];
  return `<div class="zeus-source-rule zeus-grid"><label>Sucursal / punto<input name="sourceBranch" maxlength="80" required value="${zeusEscape(rule.sucursal||'')}"></label><label>Movimiento<select name="sourceMovement">${Object.entries(zeusSourceMovements).map(([id,label])=>`<option value="${id}" ${rule.movimiento===id?'selected':''}>${label}</option>`).join('')}</select></label><label>Fuente<input name="sourceCode" maxlength="2" minlength="2" required value="${zeusEscape(rule.fuente||'')}"></label><label>Serie<input name="sourceSeries" maxlength="2" pattern="[0-9]{2}" required value="${zeusEscape(rule.serie||'00')}"></label><label>Asignación<select name="sourceScope"><option value="users">Usuarios específicos</option><option value="default" ${rule.usuarios&&users.length===0?'selected':''}>Predeterminada del movimiento</option></select></label><label>Usuarios<select name="sourceUsers" multiple size="3" aria-label="Usuarios asignados a esta fuente">${(zeusSourceUsers||users.map(id=>({usuarioId:id,nombre:`Usuario ${id}`}))).map(u=>`<option value="${u.usuarioId}" ${users.includes(u.usuarioId)?'selected':''}>${zeusEscape(u.nombre)}</option>`).join('')}</select></label><button type="button" class="button secondary" data-source-action="remove">Quitar</button></div>`;
}
function zeusSourcesSection(settings){
  zeusSourceUsers=null;
  return `<section class="zeus-card"><h2>4. Fuentes automáticas</h2><p>La fuente se asigna sin preguntar al contabilizar. Una asignación por usuario y movimiento; opcionalmente una predeterminada. Sin reglas de entradas se mantiene la fuente general actual.</p><div id="zeusSourceRules">${(settings.fuentesAutomaticas||[]).map(zeusSourceRow).join('')}</div><button type="button" class="button secondary" data-source-action="add">+ Agregar fuente</button><p id="zeusSourceStatus" role="status"></p></section>`;
}
async function zeusLoadSourceUsers(scope){
  try{
    const users=await apiRequest(`${scope.base}/routing-users`);if(!zeusCurrent(scope)||!$('#zeusSourceRules'))return;
    zeusSourceUsers=users;
    document.querySelectorAll('#zeusSourceRules [name=sourceUsers]').forEach(select=>{
      const selected=[...select.selectedOptions].map(o=>Number(o.value));
      const options=[...users,...selected.filter(id=>!users.some(u=>u.usuarioId===id)).map(id=>({usuarioId:id,nombre:`Usuario ${id} · revisar acceso`}))];
      select.innerHTML=options.map(u=>`<option value="${u.usuarioId}" ${selected.includes(u.usuarioId)?'selected':''}>${zeusEscape(u.nombre)}</option>`).join('');
    });
  }catch(error){if(zeusCurrent(scope)&&$('#zeusSourceStatus'))$('#zeusSourceStatus').textContent=`No se pudieron consultar los usuarios: ${error.message}`;}
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
    return {sucursal:value('sourceBranch'),movimiento,fuente:value('sourceCode'),serie:value('sourceSeries'),usuarios};
  });
}
function zeusSourceClick(button){
  if(!button.dataset.sourceAction)return false;
  if(button.dataset.sourceAction==='add')$('#zeusSourceRules').insertAdjacentHTML('beforeend',zeusSourceRow());else button.closest('.zeus-source-rule').remove();
  zeusUI.dirty=true;return true;
}
