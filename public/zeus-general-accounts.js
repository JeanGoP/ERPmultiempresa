function zeusGeneralSupplierSection(settings){
  const rules=settings.cuentas.filter(r=>r.concepto==='PROVEEDOR');
  const general=rules.find(r=>r.proveedorId==null&&r.articuloId==null&&r.tarifa==null);
  const legacy=rules.some(r=>r.proveedorId!=null||r.articuloId!=null||r.tarifa!=null)||rules.length>1;
  return `<section class="zeus-card"><h2>2. Cuentas generales de la empresa</h2><p>La cuenta por pagar y la cartera de proveedores se manejan aquí como una sola cuenta, común a todas las bodegas. Los anticipos y retenciones son conceptos independientes.</p><div class="zeus-grid"><label>Cuenta por pagar a proveedores<input name="cuentaProveedorGeneral" maxlength="16" list="zeusSupplierChart" autocomplete="off" placeholder="Seleccionar código del plan de Zeus" value="${zeusEscape(general?.cuenta||'')}"><small>Busca por código o nombre. La cuenta se valida en Zeus al guardar.</small></label><div><button type="button" data-zeus="supplier-chart" class="button secondary" ${zeusUI.version?'':'disabled'}>Consultar plan de proveedores</button><p id="zeusSupplierChartStatus" role="status">${zeusUI.version?'Consulta las cuentas de la empresa antes de seleccionar.':'Primero guarda el destino con las aprobaciones desactivadas; luego consulta el plan.'}</p></div></div><datalist id="zeusSupplierChart"></datalist>${legacy?`<p class="zeus-notice">Existen reglas específicas de proveedores: ${rules.map(r=>zeusEscape(r.cuenta)).join(', ')}. Al guardar serán reemplazadas por la cuenta general que selecciones. No se modifican comprobantes ni proveedores ya creados en Zeus.</p><label><input type="checkbox" name="confirmarCuentaGeneral" required> Confirmo reemplazar las reglas de proveedores por una cuenta general.</label>`:''}<p>Aplica al crédito de las nuevas entradas y a la creación de nuevos proveedores en Zeus. No actualiza retroactivamente los maestros de Zeus.</p></section>`;
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
  $('#zeusSupplierChartStatus').textContent=`${result.baseDatos} · ${result.cuentas.length} cuentas habilitadas de proveedores.${result.cuentas.length?'':' Revisa el plan y los permisos en Zeus.'}`;
}
