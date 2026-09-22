/* Fuentes por sucursal y movimiento, sin asignaciones de usuarios. */
let zeusSourceBranches=null;
const zeusSourceMovements={ENTRADA_MERCANCIA:'Entrada de mercancía',FACTURACION:'Facturación (preparación)',RECIBO_CAJA:'Recibo de caja (preparación)',EGRESO:'Comprobante de egreso (preparación)'};
function zeusBranchOptions(id,name=''){
  const active=(zeusSourceBranches||[]).filter(b=>b.activa);
  const selected=active.find(b=>id?b.id===Number(id):b.nombre.trim().toLocaleLowerCase()===name.trim().toLocaleLowerCase());
  return '<option value="">'+(zeusSourceBranches===null?'Cargando sucursales…':active.length?'Selecciona sucursal…':'Crea una sucursal en Datos maestros → Sucursales')+'</option>'+active.map(b=>'<option value="'+b.id+'" '+(b===selected?'selected':'')+'>'+zeusEscape(b.codigo)+' · '+zeusEscape(b.nombre)+'</option>').join('')+(!selected&&(id||name)?'<option value="" selected disabled>'+zeusEscape(name||'Sucursal guardada')+' · pendiente de validar</option>':'');
}
function zeusSourceRow(rule={}){
  return '<div class="zeus-source-rule zeus-grid"><label>Sucursal / punto<select name="sourceBranch" required data-branch-id="'+zeusEscape(rule.sucursalId||'')+'" data-branch-name="'+zeusEscape(rule.sucursal||'')+'">'+zeusBranchOptions(rule.sucursalId,rule.sucursal||'')+'</select></label><label>Movimiento<select name="sourceMovement">'+Object.entries(zeusSourceMovements).map(([id,label])=>'<option value="'+id+'" '+(rule.movimiento===id?'selected':'')+'>'+label+'</option>').join('')+'</select></label><label>Fuente<input name="sourceCode" maxlength="2" minlength="2" required value="'+zeusEscape(rule.fuente||'')+'"></label><label>Serie<input name="sourceSeries" maxlength="2" pattern="[0-9]{2}" required value="'+zeusEscape(rule.serie||'00')+'"></label><button type="button" class="button secondary" data-source-action="remove">Quitar</button></div>';
}
function zeusSourcesSection(settings){
  zeusSourceBranches=null;
  const unique=(settings.fuentesAutomaticas||[]).filter((r,i,all)=>all.findIndex(x=>(x.sucursalId||x.sucursal)===(r.sucursalId||r.sucursal)&&x.movimiento===r.movimiento&&x.fuente===r.fuente&&x.serie===r.serie)===i);
  return '<section class="zeus-card"><h2>4. Fuentes automáticas</h2><div id="zeusSourceRules">'+unique.map(zeusSourceRow).join('')+'</div><button type="button" class="button secondary" data-source-action="add">+ Agregar fuente</button><p id="zeusSourceStatus" role="status"></p></section>';
}
async function zeusLoadSourceBranches(scope){
  try{
    const branches=await apiRequest(scope.base.replace(/\/zeus$/,'')+'/master-data/branches');if(!zeusCurrent(scope)||!$('#zeusSourceRules'))return;
    zeusSourceBranches=branches;
    document.querySelectorAll('#zeusSourceRules [name=sourceBranch]').forEach(select=>{select.innerHTML=zeusBranchOptions(select.value||select.dataset.branchId,select.dataset.branchName||'');});
  }catch(error){if(zeusCurrent(scope)&&$('#zeusSourceStatus'))$('#zeusSourceStatus').textContent='No se pudieron consultar sucursales: '+error.message;}
}
function zeusReadSources(settings){
  if(!$('#zeusSourceRules'))return settings.fuentesAutomaticas??null;
  const assignments=new Set();
  return [...document.querySelectorAll('.zeus-source-rule')].map(row=>{
    const value=name=>row.querySelector('[name='+name+']').value.trim();
    const branch=(zeusSourceBranches||[]).find(b=>b.id===Number(value('sourceBranch'))&&b.activa);
    if(!branch)throw new Error('Selecciona una sucursal activa del catálogo de esta empresa.');
    const movimiento=value('sourceMovement'),key=branch.id+':'+movimiento;
    if(assignments.has(key))throw new Error('Solo puede haber una fuente por sucursal y movimiento.');assignments.add(key);
    return {sucursalId:branch.id,sucursal:branch.nombre,movimiento,fuente:value('sourceCode'),serie:value('sourceSeries'),usuarios:[]};
  });
}
function zeusSourceClick(button){
  if(!button.dataset.sourceAction)return false;
  if(button.dataset.sourceAction==='add')$('#zeusSourceRules').insertAdjacentHTML('beforeend',zeusSourceRow());else button.closest('.zeus-source-rule').remove();
  zeusUI.dirty=true;return true;
}
