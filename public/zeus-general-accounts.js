function zeusGeneralSupplierSection(settings){
  const rules=settings.cuentas.filter(r=>r.concepto==='PROVEEDOR');
  const general=rules.find(r=>r.proveedorId==null&&r.articuloId==null&&r.tarifa==null);
  const legacy=rules.some(r=>r.proveedorId!=null||r.articuloId!=null||r.tarifa!=null)||rules.length>1;
  return `<section class="zeus-card"><h2>2. Cuentas generales de la empresa</h2><div class="zeus-grid"><label>Cuenta por pagar a proveedores<input name="cuentaProveedorGeneral" maxlength="16" list="zeusSupplierChart" autocomplete="off" placeholder="Seleccionar código del plan de Zeus" value="${zeusEscape(general?.cuenta||'')}"></label><div><p id="zeusSupplierChartStatus" role="status">${zeusUI.version?'Cargando cuentas de proveedores…':'Primero guarda el destino con las aprobaciones desactivadas. Las cuentas se cargarán automáticamente.'}</p></div></div><datalist id="zeusSupplierChart"></datalist>${legacy?`<p class="zeus-notice">Existen reglas específicas de proveedores: ${rules.map(r=>zeusEscape(r.cuenta)).join(', ')}. Al guardar serán reemplazadas por la cuenta general que selecciones. No se modifican comprobantes ni proveedores ya creados en Zeus.</p><label><input type="checkbox" name="confirmarCuentaGeneral" required> Confirmo reemplazar las reglas de proveedores por una cuenta general.</label>`:''}</section>`;
}
function zeusReadGeneralSupplier(form,settings){
  const code=form.elements.cuentaProveedorGeneral.value.trim();
  const previous=settings.cuentas.filter(r=>r.concepto==='PROVEEDOR');
  if(form.elements.confirmarCuentaGeneral&&!form.elements.confirmarCuentaGeneral.checked)throw new Error('Confirma el reemplazo de las reglas de proveedores.');
  if(!code){
    if(form.elements.habilitado.checked||previous.length)throw new Error('Selecciona la cuenta general por pagar a proveedores.');
    return [];
  }
  const general=previous.find(r=>r.proveedorId==null&&r.articuloId==null&&r.tarifa==null);
  // Conserva dimensiones de la regla general existente, no las de excepciones particulares.
  return [{...(general||{}),concepto:'PROVEEDOR',cuenta:code,articuloId:null,proveedorId:null,tarifa:null}];
}
async function zeusLoadSupplierChart(scope){
  const form=$('#zeusSettingsForm');
  if(form.elements.servidorEsperado.value.trim()!==zeusUI.settings.servidorEsperado||form.elements.baseEsperada.value.trim()!==zeusUI.settings.baseEsperada)
    throw new Error('Guarda primero el cambio de destino. El listado debe corresponder a la empresa configurada.');
  const result=await apiRequest(`${scope.base}/supplier-accounts`);
  if(!zeusCurrent(scope))return;
  if(result.version!==zeusUI.version)throw new Error('La configuración cambió. Actualiza antes de consultar las cuentas.');
  $('#zeusSupplierChart').innerHTML=result.cuentas.map(a=>`<option value="${zeusEscape(a.codigo)}">${zeusEscape(a.codigo)} · ${zeusEscape(a.nombre)}</option>`).join('');
  $('#zeusSupplierChartStatus').textContent=result.cuentas.length?'':'No hay cuentas de proveedores disponibles. Revisa el plan y los permisos en Zeus.';
}
async function zeusAutoLoadSupplierChart(scope){
  if(!zeusUI.version)return;
  try{await zeusLoadSupplierChart(scope);}
  catch(error){if(zeusCurrent(scope)&&$('#zeusSupplierChartStatus'))$('#zeusSupplierChartStatus').textContent=`No se pudieron cargar las cuentas de proveedores: ${error.message} Usa Actualizar para reintentar.`;}
}

let zeusRetentionChartAccounts=null;
const zeusRetentionConcepts={RETEFUENTE:'Retención en la fuente',RETEIVA:'Retención de IVA',RETEICA:'Retención de ICA'};
function zeusRetentionRow(rule={},index=-1){
  return `<div class="zeus-retention zeus-grid" data-original-index="${index}"><label>Tipo<select name="retentionConcept" required>${Object.entries(zeusRetentionConcepts).map(([code,name])=>`<option value="${code}" ${rule.concepto===code?'selected':''}>${name}</option>`).join('')}</select></label><label>Porcentaje en Zeus<input name="retentionRate" readonly placeholder="Consultar cuenta en Zeus" value=""></label><label>Cuenta en Zeus<input name="retentionAccount" maxlength="16" list="zeusRetentionChart" required autocomplete="off" value="${zeusEscape(rule.cuenta||'')}" placeholder="Buscar código o nombre"></label><button type="button" class="button secondary" data-retention-action="remove">Quitar</button>${rule.articuloId!=null||rule.proveedorId!=null?'<small>Regla histórica específica: conserva su artículo/proveedor y dimensiones.</small>':''}</div>`;
}
function zeusRetentionSection(settings){
  zeusRetentionChartAccounts=null;
  return `<section class="zeus-card"><h2>3. Retenciones</h2><div id="zeusRetentionRules">${settings.cuentas.map((r,i)=>zeusRetentionConcepts[r.concepto]?zeusRetentionRow(r,i):'').join('')}</div><button type="button" class="button secondary" data-retention-action="add">＋ Agregar retención</button><datalist id="zeusRetentionChart"></datalist><p id="zeusRetentionChartStatus" role="status">${zeusUI.version?'Cargando plan de cuentas de Zeus…':'Guarda primero el destino de Zeus para consultar sus cuentas.'}</p></section>`;
}
function zeusReadRetentions(settings){
  const container=$('#zeusRetentionRules');
  if(!container)return settings.cuentas.filter(r=>zeusRetentionConcepts[r.concepto]).map(r=>({...r}));
  const keys=new Set();
  return [...container.querySelectorAll('.zeus-retention')].map(row=>{
    const old=settings.cuentas[Number(row.dataset.originalIndex)]||{};
    const concept=row.querySelector('[name="retentionConcept"]').value;
    const account=row.querySelector('[name="retentionAccount"]').value.trim();
    const tariff=zeusRetentionChartAccounts?.get(account)?.tarifa;
    if(!zeusRetentionConcepts[concept]||!account||tariff==null)throw new Error('Selecciona una cuenta con porcentaje válido consultado en Zeus. Si no aparece, revisa PORCEIMPUESTO y el indicador de valor retenido en su plan.');
    const key=JSON.stringify([concept,tariff,old.articuloId??null,old.proveedorId??null]);if(keys.has(key))throw new Error('Hay retenciones duplicadas para el mismo tipo y tarifa.');keys.add(key);
    return {...old,concepto:concept,cuenta:account,tarifa:tariff};
  });
}
async function zeusAutoLoadRetentionChart(scope){
  if(!zeusUI.version||!$('#zeusRetentionChart'))return;
  try{
    const result=await apiRequest(`${scope.base}/retention-accounts`);
    if(!zeusCurrent(scope))return;
    if(result.version!==zeusUI.version)throw new Error('La configuración cambió. Actualiza para consultar el plan correcto.');
    const eligible=result.cuentas.filter(a=>a.baseEsValorRetenido===false&&typeof a.tarifa==='number'&&a.tarifa>0&&a.tarifa<=100&&Math.abs(a.tarifa*10000-Math.round(a.tarifa*10000))<0.000001);
    zeusRetentionChartAccounts=new Map(eligible.map(a=>[a.codigo,a]));
    $('#zeusRetentionChart').innerHTML=eligible.map(a=>`<option value="${zeusEscape(a.codigo)}">${zeusEscape(a.codigo)} · ${zeusEscape(a.nombre)} · ${zeusEscape(a.tarifa)} %</option>`).join('');
    document.querySelectorAll('#zeusRetentionRules .zeus-retention').forEach(zeusUpdateRetentionRate);
    $('#zeusRetentionChartStatus').textContent=eligible.length?'':'No hay cuentas de retención con porcentaje válido disponibles en Zeus.';
  }catch(error){if(zeusCurrent(scope)&&$('#zeusRetentionChartStatus'))$('#zeusRetentionChartStatus').textContent=`No se pudo cargar el plan: ${error.message}`;}
}
function zeusRetentionClick(button){
  if(!button.dataset.retentionAction)return false;
  if(button.dataset.retentionAction==='add')$('#zeusRetentionRules').insertAdjacentHTML('beforeend',zeusRetentionRow());
  else button.closest('.zeus-retention').remove();
  zeusUI.dirty=true;return true;
}


function zeusUpdateRetentionRate(row){
  const code=row.querySelector('[name="retentionAccount"]').value.trim();
  const rate=zeusRetentionChartAccounts?.get(code)?.tarifa;
  row.querySelector('[name="retentionRate"]').value=rate==null?'':String(rate)+' %';
}
function zeusRetentionInput(event){
  if(event.target.name==='retentionAccount'){
    const row=event.target.closest('.zeus-retention');if(row)zeusUpdateRetentionRate(row);
  }
}
