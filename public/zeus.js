/* Integración por empresa. Ninguna configuración ni comprobante se guarda en localStorage. */
const zeusConcepts={INVENTARIO:'Inventario',PROVEEDOR:'Cuenta por pagar · proveedor',IVA:'IVA',OTRO_IMPUESTO:'Otro impuesto',RETEFUENTE:'Retención en la fuente',RETEIVA:'Retención de IVA',RETEICA:'Retención de ICA',CUENTA_POR_COBRAR:'Cuenta por cobrar (futuro)',GASTO:'Gasto (futuro)',FLETE:'Flete (futuro)',ANTICIPO:'Anticipo (futuro)',DESCUENTO:'Descuento (futuro)',REDONDEO:'Redondeo (futuro)'};
const zeusStates={SIN_PREPARAR:'Sin preparar',REQUIERE_REVISION:'Por revisar',PENDIENTE:'En cola',ENVIANDO:'Enviando',CONTABILIZADO:'Contabilizado',RECHAZADO:'Rechazado',INCIERTO:'Por conciliar'};
const zeusUI={epoch:0,company:null,tab:'jobs',version:0,settings:null,jobs:[],receipts:[],offset:0,receipt:null,preview:null,dirty:false,busy:false,status:null};
const zeusPanel=document.createElement('section');zeusPanel.id='zeusModule';zeusPanel.className='zeus-workspace';zeusPanel.hidden=true;elements.purchaseModule.before(zeusPanel);
function zeusEscape(value){return String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function zeusNormalize(row){return Object.fromEntries(Object.entries(row).map(([key,value])=>[key[0].toLowerCase()+key.slice(1),value]));}
function zeusMoney(value){return new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',maximumFractionDigits:2}).format(Number(value)||0);}
function zeusAdmin(){return hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR');}
function zeusPosting(){return hasPermission('COMPRAS.RECEPCION.CONTABILIZAR');}
function zeusScope(){return {epoch:zeusUI.epoch,company:String(state.erpSession?.company?.id),base:`/api/v1/companies/${state.erpSession?.company?.id}/zeus`};}
function zeusCurrent(s){return s.epoch===zeusUI.epoch&&s.company===String(state.erpSession?.company?.id);}
function closeZeus(){zeusPanel.hidden=true;$('#zeusNav').classList.remove('active');}
function resetZeus(){closeZeus();zeusUI.epoch++;Object.assign(zeusUI,{company:null,settings:null,version:0,jobs:[],receipts:[],receipt:null,preview:null,dirty:false,busy:false,status:null,offset:0});zeusPanel.inert=false;zeusPanel.removeAttribute('aria-busy');zeusPanel.replaceChildren();}
function zeusNotice(message,error=false){const box=$('#zeusNotice');if(box){box.textContent=message;box.hidden=!message;box.classList.toggle('error',error);}}
async function zeusRun(action){
  if(zeusUI.busy)return;const scope=zeusScope();zeusUI.busy=true;zeusPanel.setAttribute('aria-busy','true');
  zeusPanel.inert=true;
  try {await action(scope);}catch(error){if(zeusCurrent(scope))zeusNotice(error.message,true);}
  finally{if(zeusCurrent(scope)){zeusUI.busy=false;zeusPanel.inert=false;zeusPanel.removeAttribute('aria-busy');}}
}
function zeusBadge(status){return `<span class="zeus-badge ${['CONTABILIZADO'].includes(status)?'good':['INCIERTO','RECHAZADO'].includes(status)?'warning':''}">${zeusEscape(zeusStates[status]||status)}</span>`;}
function zeusShell(){
  const name=state.erpSession.company.name;
  zeusPanel.innerHTML=`<header class="zeus-heading"><div><p class="eyebrow">CONTABILIDAD · INTEGRACIÓN</p><h1>Zeus</h1><p>Configura, revisa y sigue cada comprobante de <strong>${zeusEscape(name)}</strong>.</p></div><button class="button secondary" data-zeus="refresh" type="button">Actualizar</button></header>
    <div id="zeusMode" class="zeus-mode" role="status">Consultando estado de la integración…</div>
    <nav class="zeus-tabs" aria-label="Integración Zeus">${zeusPosting()?'<button type="button" data-zeus-tab="jobs">Seguimiento</button><button type="button" data-zeus-tab="prepare">Preparar comprobante</button>':''}${zeusAdmin()?'<button type="button" data-zeus-tab="settings">Configuración de empresa</button>':''}</nav>
    <p id="zeusNotice" class="zeus-notice" role="status" hidden></p><div id="zeusContent"></div>`;
}
function zeusMode(){
  const s=zeusUI.status;if(!s)return;
  $('#zeusMode').textContent=!s.configurado?'Sin configurar · Completa las cuentas y la conexión de esta empresa.':!s.habilitado?'Envíos desactivados para esta empresa · Puedes revisar su configuración.':!s.despachadorActivo?'Despachador del servidor apagado · Las aprobaciones quedarán en cola, sin enviarse.':'Envíos habilitados · Solo se procesan los comprobantes aprobados.';
}
async function showZeus(){
  if(!zeusAdmin()&&!zeusPosting())return;
  if(zeusUI.busy)return;
  if(zeusUI.company!==String(state.erpSession.company.id))resetZeus();
  zeusUI.company=String(state.erpSession.company.id);zeusUI.tab=zeusPosting()?'jobs':'settings';
  hideWorkspaces();zeusPanel.hidden=false;document.querySelectorAll('.erp-nav button.active').forEach(b=>b.classList.remove('active'));$('#zeusNav').classList.add('active');
  document.querySelector('.breadcrumb span').textContent='Contabilidad';elements.breadcrumbCurrent.textContent='Integración Zeus';zeusShell();
  await zeusRun(async scope=>{await zeusLoadStatus(scope);if(zeusCurrent(scope))await zeusLoadTab(scope);});
}
async function zeusLoadStatus(scope){const result=await apiRequest(`${scope.base}/status`);if(zeusCurrent(scope)){zeusUI.status=result;zeusMode();}}
async function zeusLoadTab(scope){
  if(!zeusCurrent(scope))return;
  zeusNotice('');
  document.querySelectorAll('[data-zeus-tab]').forEach(b=>{b.classList.toggle('active',b.dataset.zeusTab===zeusUI.tab);b.setAttribute('aria-current',b.dataset.zeusTab===zeusUI.tab?'page':'false');});
  $('#zeusContent').innerHTML='<p class="zeus-empty">Cargando información de la empresa…</p>';
  if(zeusUI.tab==='settings'){
    if(!state.apiContext)await loadApiCompanyContext();
    if(!zeusCurrent(scope))return;
    if(!state.apiContext)throw new Error('No se pudieron cargar los maestros de la empresa. Actualiza antes de configurar Zeus.');
    let saved;try{saved=await apiRequest(`${scope.base}/configuration`);}catch(error){if(error.status!==404)throw error;}
    if(!zeusCurrent(scope))return;
    zeusUI.version=saved?.version||0;zeusUI.settings=saved?.configuracion||{habilitado:false,servidorEsperado:'',baseEsperada:'',fuente:'',serie:'',unidadNegocio:'',usuarioZeus:'',tipoFactura:'',cuentas:[],proveedores:[]};zeusUI.dirty=false;zeusRenderSettings();
  }else if(zeusUI.tab==='prepare'){
    zeusUI.preview=null;zeusUI.receipt=null;
    $('#zeusContent').innerHTML='<div class="zeus-card"><h2>Entradas contabilizadas en el ERP</h2><p>Primero selecciona una factura. La fecha contable se toma de la entrada.</p><form id="zeusSearchForm" class="zeus-toolbar"><label>Factura o proveedor<input name="q" maxlength="100" placeholder="Buscar por número o nombre"></label><button type="submit" class="button secondary">Buscar</button></form><div id="zeusReceipts" class="zeus-scroll"></div></div><div id="zeusPreparation"></div>';
    await zeusFindReceipts(scope,'');
  }else{
    $('#zeusContent').innerHTML=`<div class="zeus-kpis" id="zeusKpis"></div><section class="zeus-card"><div class="zeus-toolbar"><label>Estado<select id="zeusState"><option value="">Todos los estados</option>${Object.entries(zeusStates).filter(([k])=>k!=='SIN_PREPARAR').map(([k,v])=>`<option value="${k}">${v}</option>`).join('')}</select></label><p>Consulta hasta 100 envíos por página. Los resultados inciertos no se reenvían.</p></div><div id="zeusJobs" class="zeus-scroll"></div><div class="zeus-pagination"><button type="button" class="button secondary" data-zeus="previous">Anterior</button><span id="zeusPage"></span><button type="button" class="button secondary" data-zeus="next">Siguiente</button></div></section>`;
    zeusUI.offset=0;await zeusLoadJobs(scope);
  }
}
async function zeusLoadJobs(scope){
  const filter=$('#zeusState').value;const rows=await apiRequest(`${scope.base}/jobs?offset=${zeusUI.offset}&estado=${encodeURIComponent(filter)}`);
  if(!zeusCurrent(scope))return;zeusUI.jobs=rows.map(zeusNormalize);
  $('#zeusKpis').innerHTML=[['Por revisar',['REQUIERE_REVISION','RECHAZADO']],['En proceso',['PENDIENTE','ENVIANDO']],['Contabilizados',['CONTABILIZADO']],['Por conciliar',['INCIERTO']]].map(([title,statuses])=>`<article><span>${title}</span><strong>${zeusUI.jobs.filter(j=>statuses.includes(j.estado)).length}</strong><small>En esta página</small></article>`).join('');
  $('#zeusJobs').innerHTML=zeusUI.jobs.length?`<table><thead><tr><th>Factura / proveedor</th><th>Fecha contable</th><th>Valor</th><th>Estado</th><th>Comprobante Zeus</th><th>Detalle / acción</th></tr></thead><tbody>${zeusUI.jobs.map(j=>`<tr><td><strong>${zeusEscape(j.factura||'Entrada '+j.recepcionMercanciaId)}</strong><small>${zeusEscape(j.proveedor)}</small></td><td>${zeusEscape(String(j.fechaContable||'').slice(0,10))}</td><td class="zeus-money">${zeusMoney(j.total)}</td><td>${zeusBadge(j.estado)}<small>${j.intentos} intento(s)</small></td><td>${zeusEscape([j.fuente,j.documento].filter(Boolean).join(' · ')||'—')}</td><td><span class="zeus-error-detail">${zeusEscape(j.error||'')}</span>${j.estado==='INCIERTO'&&zeusAdmin()?`<button type="button" class="button secondary" data-zeus-reconcile="${j.zeusEnvioId}">Conciliar sin reenviar</button>`:''}${['REQUIERE_REVISION','RECHAZADO'].includes(j.estado)?'<button type="button" class="button secondary" data-zeus-tab="prepare">Preparar comprobante</button>':''}</td></tr>`).join('')}</tbody></table>`:'<div class="zeus-empty"><h3>No hay envíos con este filtro</h3><p>Las nuevas entradas de una empresa configurada aparecen aquí para revisión. También puedes preparar una entrada anterior.</p></div>';
  $('#zeusPage').textContent=`Página ${Math.floor(zeusUI.offset/100)+1} · ${rows.length} envíos`;
  $('[data-zeus="previous"]').disabled=zeusUI.offset===0;$('[data-zeus="next"]').disabled=rows.length<100;
}
function zeusField(label,name,value='',type='text',max=20){return `<label>${label}<input name="${name}" type="${type}" value="${zeusEscape(value)}" ${type==='text'?`maxlength="${max}"`:''} required></label>`;}
function zeusOptions(rows,value,label,selected,empty='Predeterminado'){return `<option value="">${empty}</option>`+rows.map(row=>`<option value="${zeusEscape(row[value])}" ${String(row[value])===String(selected)?'selected':''}>${zeusEscape(label(row))}</option>`).join('');}
function zeusRule(rule={}){
  const masters=state.apiContext?.masterData||{suppliers:[],articles:[]};
  return `<fieldset class="zeus-rule"><legend>Regla contable</legend><div class="zeus-grid"><label>Concepto<select name="concepto" required>${Object.entries(zeusConcepts).map(([key,label])=>`<option value="${key}" ${rule.concepto===key?'selected':''}>${label}</option>`).join('')}</select></label>${zeusField('Cuenta en Zeus','cuenta',rule.cuenta)}<label>Tarifa % (solo impuestos)<input name="tarifa" type="number" min="0" max="100" step="0.0001" value="${zeusEscape(rule.tarifa??'')}"></label><label>Artículo específico<select name="articuloId">${zeusOptions(masters.articles,'id',a=>`${a.code} · ${a.description}`,rule.articuloId,'Todos los artículos')}</select></label><label>Proveedor específico<select name="proveedorId">${zeusOptions(masters.suppliers,'id',p=>p.name,rule.proveedorId,'Todos los proveedores')}</select></label></div><details><summary>Centro de costo, auxiliar y presupuesto</summary><div class="zeus-grid">${[['centroCosto','Centro de costo'],['auxiliar','Auxiliar'],['item','Ítem contable'],['presupuesto','Presupuesto'],['reserva','Reserva']].map(([key,label])=>`<label>${label}<input name="${key}" maxlength="20" value="${zeusEscape(rule[key])}"></label>`).join('')}</div></details><button type="button" class="zeus-remove" data-zeus-remove="rule">Quitar regla</button></fieldset>`;
}
function zeusSupplierRow(p={}){return `<div class="zeus-supplier zeus-grid"><label>Proveedor del ERP<select name="proveedorId" required>${zeusOptions(state.apiContext?.masterData.suppliers||[],'id',r=>`${r.identification} · ${r.name}`,p.proveedorId,'Seleccionar proveedor…')}</select></label>${zeusField('Código proveedor en Zeus','codigoProveedor',p.codigoProveedor)}${zeusField('Código tercero en Zeus','codigoTercero',p.codigoTercero)}<button type="button" class="zeus-remove" data-zeus-remove="supplier">Quitar vínculo</button></div>`;}
function zeusRenderSettings(){
  const s=zeusUI.settings;
  $('#zeusContent').innerHTML=`<form id="zeusSettingsForm"><section class="zeus-card"><h2>1. Destino y comprobante</h2><p>Esta configuración pertenece únicamente a <strong>${zeusEscape(state.erpSession.company.name)}</strong>. Las contraseñas se guardan en el servidor, nunca aquí.</p><div class="zeus-grid">${zeusField('Servidor SQL esperado','servidorEsperado',s.servidorEsperado,'text',150)}${zeusField('Base contable de Zeus','baseEsperada',s.baseEsperada,'text',128)}${zeusField('Fuente (2 caracteres)','fuente',s.fuente,'text',2)}${zeusField('Serie (2 dígitos)','serie',s.serie,'text',2)}${zeusField('Unidad de negocio','unidadNegocio',s.unidadNegocio)}${zeusField('Usuario de Zeus','usuarioZeus',s.usuarioZeus)}${zeusField('Tipo de factura','tipoFactura',s.tipoFactura,'text',10)}</div><p class="zeus-help">Conexión privada que debe configurar soporte: <code>Zeus__Companies__${zeusEscape(state.erpSession.company.id)}__ConnectionString</code></p><button type="button" data-zeus="check" class="button secondary" ${zeusUI.version?'':'disabled'}>Comprobar conexión guardada</button></section>
    <section class="zeus-card"><h2>2. Cuentas e impuestos</h2><p>Define una cuenta por concepto y tarifa. Las reglas específicas de artículo o proveedor tienen prioridad sobre las generales. Los conceptos marcados “futuro” aún no generan comprobantes.</p><div id="zeusRules">${s.cuentas.map(zeusRule).join('')}</div><button type="button" class="button secondary" data-zeus="add-rule">＋ Agregar regla contable</button></section>
    <section class="zeus-card"><h2>3. Proveedores y terceros</h2><p>Relaciona los proveedores de esta empresa con sus códigos existentes en Zeus. Esto no crea maestros en Zeus.</p><div id="zeusSuppliers">${s.proveedores.map(zeusSupplierRow).join('')}</div><button type="button" class="button secondary" data-zeus="add-supplier">＋ Vincular proveedor</button></section>
    <section class="zeus-card zeus-save"><label class="zeus-toggle"><input name="habilitado" type="checkbox" ${s.habilitado?'checked':''}><span><strong>Permitir aprobaciones para esta empresa</strong><small>Activa solo después de validar sus cuentas y probar la conexión. El envío también requiere activar el despachador en el servidor.</small></span></label><button type="submit" class="button primary">Guardar configuración de empresa</button><small>Versión ${zeusUI.version} · No se contabiliza nada al guardar.</small></section></form>`;
}
function zeusReadSettings(){
  const form=$('#zeusSettingsForm'),s={habilitado:form.elements.habilitado.checked};
  ['servidorEsperado','baseEsperada','fuente','serie','unidadNegocio','usuarioZeus','tipoFactura'].forEach(k=>s[k]=form.elements[k].value.trim());
  s.cuentas=[...$('#zeusRules').children].map(row=>{const rule={};['concepto','cuenta','centroCosto','auxiliar','item','presupuesto','reserva'].forEach(k=>rule[k]=row.querySelector(`[name="${k}"]`).value.trim());['tarifa','articuloId','proveedorId'].forEach(k=>{const v=row.querySelector(`[name="${k}"]`).value;rule[k]=v===''?null:Number(v);});return rule;});
  s.proveedores=[...$('#zeusSuppliers').children].map(row=>({proveedorId:Number(row.querySelector('[name="proveedorId"]').value),codigoProveedor:row.querySelector('[name="codigoProveedor"]').value.trim(),codigoTercero:row.querySelector('[name="codigoTercero"]').value.trim()}));return s;
}
async function zeusFindReceipts(scope,query){const rows=await apiRequest(`${scope.base}/receipts?q=${encodeURIComponent(query)}`);if(!zeusCurrent(scope))return;zeusUI.receipts=rows.map(zeusNormalize);$('#zeusReceipts').innerHTML=rows.length?`<table><thead><tr><th>Factura / proveedor</th><th>Fecha contable</th><th>Total</th><th>En Zeus</th><th></th></tr></thead><tbody>${zeusUI.receipts.map(r=>`<tr><td><strong>${zeusEscape(r.factura)}</strong><small>${zeusEscape(r.proveedor)}</small></td><td>${zeusEscape(String(r.fechaContable).slice(0,10))}</td><td class="zeus-money">${zeusMoney(r.total)} <small>${zeusEscape(r.moneda)}</small></td><td>${zeusBadge(r.estadoZeus)}</td><td><button type="button" class="button secondary" data-zeus-receipt="${r.recepcionId}" ${['PENDIENTE','ENVIANDO','INCIERTO','CONTABILIZADO'].includes(r.estadoZeus)?'disabled':''}>Revisar</button></td></tr>`).join('')}</tbody></table>`:'<p class="zeus-empty">No hay entradas contabilizadas con esa búsqueda.</p>';}
function zeusTaxRow(retention=false){const concepts=retention?['RETEFUENTE','RETEIVA','RETEICA']:['IVA','OTRO_IMPUESTO'];return `<div class="zeus-tax zeus-grid"><label>Concepto<select name="concepto" required><option value="">Seleccionar…</option>${concepts.map(c=>`<option value="${c}">${zeusConcepts[c]}</option>`).join('')}</select></label><label>Tarifa %<input name="tarifa" required type="number" min="0.0001" max="100" step="0.0001"></label><label>Base COP<input name="base" required type="number" min="0.01" step="0.01"></label><label>Valor COP<input name="valor" required type="number" min="0.01" step="0.01"></label><button type="button" class="zeus-remove" data-zeus-remove="tax">Quitar</button></div>`;}
function zeusPrepare(id){
  const r=zeusUI.receipts.find(x=>x.recepcionId===id);if(!r)return;zeusUI.receipt=r;zeusUI.preview=null;
  $('#zeusPreparation').innerHTML=`<section class="zeus-card"><h2>Revisión · ${zeusEscape(r.factura)}</h2><p>${zeusEscape(r.proveedor)} · Fecha de factura: ${zeusEscape(String(r.fechaFactura).slice(0,10))}</p><p>Primera versión: mercancía completa en COP, sin servicios ni cargos pendientes de distribuir. No se generan ajustes para forzar el cuadre.</p><div class="zeus-kpis"><article><span>Por pagar</span><strong>${zeusMoney(r.total)}</strong></article><article><span>Impuestos guardados</span><strong>${zeusMoney(r.impuestos)}</strong></article><article><span>Retenciones guardadas</span><strong>${zeusMoney(r.retenciones)}</strong></article></div><form id="zeusPreviewForm"><h3>Desglose de impuestos</h3><p>Confirma el concepto y la tarifa; el sistema no asume que todos los impuestos son IVA.</p><div id="zeusTaxes">${r.impuestos>0?zeusTaxRow():''}</div><button type="button" class="button secondary" data-zeus="add-tax">＋ Agregar impuesto</button><h3>Desglose de retenciones aplicadas</h3><div id="zeusWithholdings">${r.retenciones>0?zeusTaxRow(true):''}</div><button type="button" class="button secondary" data-zeus="add-withholding">＋ Agregar retención</button><div class="zeus-form-end"><button type="submit" class="button primary">Generar vista previa</button><span>No envía nada a Zeus.</span></div></form><div id="zeusPreview"></div></section>`;
  $('#zeusPreparation').scrollIntoView({behavior:'smooth',block:'start'});
}
function zeusTaxesPayload(){const read=id=>[...$(id).children].map(row=>({concepto:row.querySelector('[name="concepto"]').value,tarifa:Number(row.querySelector('[name="tarifa"]').value),base:Number(row.querySelector('[name="base"]').value),valor:Number(row.querySelector('[name="valor"]').value)}));return {impuestos:read('#zeusTaxes'),retenciones:read('#zeusWithholdings')};}
function zeusInvalidatePreview(){zeusUI.preview=null;if($('#zeusPreview'))$('#zeusPreview').replaceChildren();}
function zeusRenderPreview(result,payload){
  zeusUI.preview={...result,payload,receiptId:zeusUI.receipt.recepcionId};
  $('#zeusPreview').innerHTML=`<div class="zeus-review"><h3>Comprobante propuesto</h3><p>Revisa las cuentas antes de aprobar. La validación definitiva de períodos, permisos y maestros la realiza Zeus al procesar el envío.</p><div class="zeus-scroll"><table><thead><tr><th>Concepto</th><th>Cuenta</th><th>Base</th><th>Tarifa</th><th>Débito</th><th>Crédito</th></tr></thead><tbody>${result.comprobante.movimientos.map(m=>`<tr><td>${zeusEscape(zeusConcepts[m.regla.concepto]||m.regla.concepto)}</td><td>${zeusEscape(m.regla.cuenta)}</td><td>${m.base?zeusMoney(Math.abs(m.base)):'—'}</td><td>${m.tarifa?zeusEscape(m.tarifa)+'%':'—'}</td><td class="zeus-money">${m.valor>0?zeusMoney(m.valor):'—'}</td><td class="zeus-money">${m.valor<0?zeusMoney(-m.valor):'—'}</td></tr>`).join('')}</tbody><tfoot><tr><th colspan="4">Totales</th><th class="zeus-money">${zeusMoney(result.debito)}</th><th class="zeus-money">${zeusMoney(result.credito)}</th></tr></tfoot></table></div><p>Destino: <strong>${zeusEscape(result.comprobante.configuracion.baseEsperada)}</strong> · Fuente ${zeusEscape(result.comprobante.configuracion.fuente)} · BU ${zeusEscape(result.comprobante.configuracion.unidadNegocio)} · Fecha contable ${zeusEscape(String(result.comprobante.origen.fechaContable).slice(0,10))}</p><label class="zeus-toggle"><input id="zeusReviewed" type="checkbox"><span>Revisé las cuentas, el proveedor y los importes de este comprobante.</span></label><button type="button" class="button primary" data-zeus="approve" ${!result.comprobante.configuracion.habilitado?'disabled':''}>Aprobar y poner en cola</button>${!result.comprobante.configuracion.habilitado?'<p>Activa las aprobaciones de la empresa desde Configuración antes de continuar.</p>':''}</div>`;
}
$('#zeusNav').addEventListener('click',()=>void showZeus());
document.querySelector('.erp-nav').addEventListener('click',event=>{if(event.target.closest('button')&&!event.target.closest('#zeusNav'))closeZeus();},true);
zeusPanel.addEventListener('input',event=>{if(event.target.closest('#zeusSettingsForm'))zeusUI.dirty=true;if(event.target.closest('#zeusPreviewForm'))zeusInvalidatePreview();});
zeusPanel.addEventListener('change',event=>{if(event.target.id==='zeusState'){zeusUI.offset=0;void zeusRun(zeusLoadJobs);}if(event.target.closest('#zeusSettingsForm'))zeusUI.dirty=true;if(event.target.closest('#zeusPreviewForm'))zeusInvalidatePreview();});
zeusPanel.addEventListener('submit',event=>{
  event.preventDefault();const form=event.target;if(!form.reportValidity())return;
  void zeusRun(async scope=>{
    if(form.id==='zeusSettingsForm'){const value=zeusReadSettings();await apiRequest(`${scope.base}/configuration`,{method:'PUT',body:JSON.stringify({version:zeusUI.version,configuracion:value})});if(!zeusCurrent(scope))return;zeusUI.dirty=false;await zeusLoadStatus(scope);if(!zeusCurrent(scope))return;await zeusLoadTab(scope);if(zeusCurrent(scope))zeusNotice('Configuración guardada en esta empresa. No se envió ningún comprobante.');}
    else if(form.id==='zeusSearchForm'){await zeusFindReceipts(scope,new FormData(form).get('q'));}
    else if(form.id==='zeusPreviewForm'){const payload=zeusTaxesPayload();zeusInvalidatePreview();const result=await apiRequest(`${scope.base}/receipts/${zeusUI.receipt.recepcionId}/preview`,{method:'POST',body:JSON.stringify(payload)});if(zeusCurrent(scope)){zeusRenderPreview(result,payload);zeusNotice('Comprobante generado para revisión. Aún no está enviado.');}}
  });
});
zeusPanel.addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button||button.disabled||zeusUI.busy)return;
  if(button.dataset.zeusRemove){button.closest(button.dataset.zeusRemove==='rule'?'.zeus-rule':button.dataset.zeusRemove==='supplier'?'.zeus-supplier':'.zeus-tax').remove();zeusUI.dirty=true;zeusInvalidatePreview();return;}
  if(button.dataset.zeusReceipt){zeusPrepare(Number(button.dataset.zeusReceipt));return;}
  const action=button.dataset.zeus;
  if(action==='add-rule'){ $('#zeusRules').insertAdjacentHTML('beforeend',zeusRule());zeusUI.dirty=true;return; }
  if(action==='add-supplier'){ $('#zeusSuppliers').insertAdjacentHTML('beforeend',zeusSupplierRow());zeusUI.dirty=true;return; }
  if(action==='add-tax'||action==='add-withholding'){ $(action==='add-tax'?'#zeusTaxes':'#zeusWithholdings').insertAdjacentHTML('beforeend',zeusTaxRow(action==='add-withholding'));zeusInvalidatePreview();return; }
  if((button.dataset.zeusTab||action==='refresh')&&zeusUI.dirty&&!confirm('Hay cambios de configuración sin guardar. ¿Descartarlos?'))return;
  void zeusRun(async scope=>{
    if(button.dataset.zeusTab){zeusUI.dirty=false;zeusUI.tab=button.dataset.zeusTab;await zeusLoadTab(scope);}
    else if(action==='refresh'){zeusUI.dirty=false;await zeusLoadStatus(scope);if(zeusCurrent(scope))await zeusLoadTab(scope);}
    else if(action==='check'){if(zeusUI.dirty)throw new Error('Guarda los cambios antes de comprobar la conexión.');const result=await apiRequest(`${scope.base}/connection/check`,{method:'POST'});if(zeusCurrent(scope))zeusNotice(result.contratoDisponible?`Conexión correcta a ${result.baseDatos}. Esto no es una prueba de contabilización.`:'Conecta con SQL, pero faltan objetos del contrato Zeus.',!result.contratoDisponible);}
    else if(action==='previous'||action==='next'){zeusUI.offset=Math.max(0,zeusUI.offset+(action==='next'?100:-100));await zeusLoadJobs(scope);}
    else if(button.dataset.zeusReconcile){const result=await apiRequest(`${scope.base}/jobs/${button.dataset.zeusReconcile}/reconcile`,{method:'POST'});if(!zeusCurrent(scope))return;await zeusLoadJobs(scope);if(zeusCurrent(scope))zeusNotice(result.estado==='CONTABILIZADO'?'Comprobante encontrado y conciliado. No se realizó otro envío.':result.error||'Requiere revisión en Zeus.',result.estado!=='CONTABILIZADO');}
    else if(action==='approve'){
      const preview=zeusUI.preview;if(!preview||!$('#zeusReviewed')?.checked)throw new Error('Confirma que revisaste el comprobante antes de aprobar.');
      await apiRequest(`${scope.base}/receipts/${preview.receiptId}/approve`,{method:'POST',body:JSON.stringify({...preview.payload,huella:preview.huella})});if(!zeusCurrent(scope))return;zeusInvalidatePreview();zeusUI.tab='jobs';await zeusLoadTab(scope);if(zeusCurrent(scope))zeusNotice('Aprobación registrada. Consulta el estado: poner en cola no significa que Zeus ya lo haya contabilizado.');
    }
  });
});
