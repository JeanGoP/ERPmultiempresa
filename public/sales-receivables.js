/* Tablero de cartera de clientes. Los indicadores cubren toda la selección, no solo la página visible. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const typeLabel=value=>({MOTO:'Motos',OTROS:'Otros artículos',MIXTA:'Mixta',SIN_CLASIFICAR:'Sin clasificar'})[value]||'Sin clasificar';
  const stateLabel=value=>({AL_DIA:'Al día',VENCIDA:'Vencida',PAGADA:'Saldada'})[value]||value;
  const bands=[
    {name:'Por vencer',note:'Al día',color:'#208573'},
    {name:'1–30 días',note:'Vencimiento reciente',color:'#b99230'},
    {name:'31–60 días',note:'Atención',color:'#d17b3c'},
    {name:'61–90 días',note:'Prioridad alta',color:'#ba5551'},
    {name:'Más de 90 días',note:'Prioridad crítica',color:'#8a3f59'}
  ];
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog sales-receivables-dialog';document.body.append(dialog);
  let company=0,generation=0,page=1,query='',category='',status='ABIERTA',band=null,from='',to='';
  const $=selector=>dialog.querySelector(selector);
  const current=token=>token===generation&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  function close(){generation++;if(dialog.open)dialog.close();company=0;}
  window.resetSalesReceivables=close;
  dialog.addEventListener('cancel',event=>{event.preventDefault();close();});
  function shell(){
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">VENTAS / INTELIGENCIA DE CARTERA · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>Cartera de clientes</h2><p class="egreso-help">Consulta saldos, vencimientos y prioridades. Los indicadores reflejan todos los filtros activos.</p></div><button type="button" class="dialog-close" data-close aria-label="Cerrar">×</button></div>
      <div class="inventory-stats payable-kpis receivables-kpis" data-kpis></div>
      <section class="receivables-workspace"><form data-filters class="sales-receivables-filters">
        <label>Buscar<input name="q" type="search" maxlength="100" placeholder="Factura, cliente o identificación" value="${esc(query)}"></label>
        <label>Tipo de cartera<select name="clase"><option value="">Todos los tipos</option><option value="MOTO" ${category==='MOTO'?'selected':''}>Motos</option><option value="OTROS" ${category==='OTROS'?'selected':''}>Otros artículos</option><option value="MIXTA" ${category==='MIXTA'?'selected':''}>Mixta</option><option value="SIN_CLASIFICAR" ${category==='SIN_CLASIFICAR'?'selected':''}>Sin clasificar</option></select></label>
        <label>Estado<select name="estado"><option value="ABIERTA" ${status==='ABIERTA'?'selected':''}>Cartera abierta</option><option value="VENCIDA" ${status==='VENCIDA'?'selected':''}>Vencida</option><option value="AL_DIA" ${status==='AL_DIA'?'selected':''}>Al día</option><option value="PAGADA" ${status==='PAGADA'?'selected':''}>Saldada</option><option value="TODAS" ${status==='TODAS'?'selected':''}>Todos los estados</option></select></label>
        <label>Desde contabilización<input name="desde" type="date" value="${esc(from)}"></label>
        <label>Hasta contabilización<input name="hasta" type="date" value="${esc(to)}"></label>
        <button class="button primary" type="submit">Actualizar</button>
      </form><p data-status role="status" aria-live="polite"></p><div data-dashboard class="payable-dashboard"></div>
      <div class="payable-table-heading"><div><h2>Detalle de cuotas</h2><p data-scope></p></div></div>
      <div class="table-wrap receivables-table" data-table></div><div class="sales-receivables-pages" data-pages></div></section>`;
    $('[data-close]').onclick=close;
    $('[data-filters]').onsubmit=event=>{
      event.preventDefault();const fields=event.target.elements;
      if(fields.desde.value&&fields.hasta.value&&fields.desde.value>fields.hasta.value){$('[data-status]').textContent='La fecha inicial no puede ser posterior a la final.';return;}
      query=fields.q.value.trim();category=fields.clase.value;status=fields.estado.value;from=fields.desde.value;to=fields.hasta.value;band=null;page=1;void load();
    };
  }
  function render(result){
    const summary=result.resumen,open=Number(summary.saldo),overdue=Number(summary.vencido),inTime=open-overdue;
    const cards=[
      ['Saldo por cobrar',money(open),`${summary.clientes} cliente(s) con saldo`,'primary'],
      ['Cartera vencida',money(overdue),`${open?Math.round(overdue/open*100):0}% del saldo requiere atención`,'alert'],
      ['Por vencer',money(inTime),`${summary.cuotasAlDia} cuota(s) al día`,''],
      [status==='PAGADA'?'Cuotas saldadas':'Facturas abiertas',status==='PAGADA'?summary.cuotasPagadas:summary.facturas,`${summary.cuotasVencidas} cuota(s) vencida(s)`,'']
    ];
    $('[data-kpis]').innerHTML=cards.map(([title,value,note,tone])=>`<article class="${tone}"><span>${esc(title)}</span><strong>${esc(value)}</strong><small>${esc(note)}</small></article>`).join('');
    const buckets=bands.map((b,i)=>({...b,...(result.bandas.find(x=>x.indice===i)||{cuotas:0,saldo:0})}));
    const highest=Number(result.clientesPrincipales[0]?.saldo)||1;
    $('[data-dashboard]').innerHTML=`<section class="payable-aging"><header><div><span class="payable-overline">DISTRIBUCIÓN DEL SALDO</span><h2>¿Qué edad tiene la cartera?</h2><p>Días transcurridos desde el vencimiento de cada cuota abierta.</p></div><button type="button" class="button secondary" data-band="all">Ver todas</button></header>
      <div class="payable-stacked" aria-label="Distribución por edades">${buckets.filter(x=>x.saldo>0).map(x=>`<span style="width:${open?x.saldo/open*100:0}%;background:${x.color}" title="${esc(x.name+': '+money(x.saldo))}"></span>`).join('')}</div>
      <div class="payable-bands">${buckets.map((x,i)=>`<button type="button" data-band="${i}" class="${band===i?'selected':''}" style="--band-color:${x.color}" aria-pressed="${band===i}"><span>${x.name}</span><strong>${money(x.saldo)}</strong><small>${x.cuotas} cuota(s) · ${open?Math.round(x.saldo/open*100):0}%</small><em>${x.note}</em></button>`).join('')}</div></section>
      <div class="payable-insights"><section><span class="payable-overline">CONCENTRACIÓN</span><h2>Clientes con mayor saldo</h2><p>Los cinco saldos más altos de esta selección.</p>${result.clientesPrincipales.map(x=>`<button type="button" class="payable-rank" data-client="${esc(x.identificacion)}"><span>${esc(x.nombre)}</span><strong>${money(x.saldo)}</strong><i style="--rank-width:${Math.round(x.saldo/highest*100)}%"></i><small>Vencido: ${money(x.vencido)}</small></button>`).join('')||'<p class="payable-empty">No hay saldos pendientes.</p>'}</section>
      <section><span class="payable-overline">FOCO DE ATENCIÓN</span><h2>Cuotas prioritarias</h2><p>Primero las más antiguas; después las de mayor saldo.</p>${result.prioritarias.map(x=>`<button type="button" class="payable-priority" data-invoice="${x.id}"><span class="payable-days">${x.diasVencida}<small>días</small></span><span><strong>${esc(x.numero)}</strong><small>${esc(x.cliente)} · vence ${esc(x.vence)}</small></span><b>${money(x.saldo)}</b></button>`).join('')||'<div class="payable-empty">Todo al día<small>No hay cuotas vencidas en esta selección.</small></div>'}</section></div>`;
    $('[data-scope]').textContent=`${band===null?'Todas las edades':bands[band].name} · ${result.totalRegistros} cuota(s) · ${money(result.totalSaldo)}. Indicadores sujetos a todos los filtros.`;
    $('[data-table]').innerHTML=`<table><thead><tr><th>Cliente / factura</th><th>Cartera</th><th>Vencimiento</th><th>Edad</th><th>Valor original</th><th>Saldo</th><th>Estado</th><th>Detalle</th></tr></thead><tbody>${result.items.map(x=>`<tr><td><strong>${esc(x.cliente)}</strong><small>${esc(x.identificacion)} · ${esc(x.numero)}${x.numeroCuota?` · cuota ${x.numeroCuota}`:''}</small></td><td>${esc(typeLabel(x.claseCartera))}</td><td>${esc(x.vence)}</td><td>${x.diasVencida?`${x.diasVencida} días vencida`:'Al día'}</td><td>${money(x.original)}</td><td class="receivable-balance">${money(x.saldo)}</td><td><span class="receivable-state state-${x.estado.toLowerCase()}">${stateLabel(x.estado)}</span><small>Zeus: ${esc(x.zeusEstado)}</small></td><td><button type="button" class="button secondary" data-invoice="${x.id}">Abrir factura</button></td></tr>`).join('')||'<tr><td colspan="8">No hay cuotas con estos filtros.</td></tr>'}</tbody></table>`;
    $('[data-pages]').innerHTML=`<button type="button" class="button secondary" data-prev ${page>1?'':'disabled'}>Anterior</button><span>Página ${page} de ${Math.max(1,result.paginas)}</span><button type="button" class="button secondary" data-next ${page<result.paginas?'':'disabled'}>Siguiente</button>`;
    dialog.querySelectorAll('[data-band]').forEach(button=>button.onclick=()=>{band=button.dataset.band==='all'?null:Number(button.dataset.band);status='ABIERTA';page=1;void load();});
    dialog.querySelectorAll('[data-client]').forEach(button=>button.onclick=()=>{query=button.dataset.client;status='ABIERTA';band=null;page=1;void load();});
    dialog.querySelectorAll('[data-invoice]').forEach(button=>button.onclick=()=>{const id=Number(button.dataset.invoice);close();void window.openSavedSalesInvoice(id);});
    $('[data-prev]').onclick=()=>{page--;void load();};$('[data-next]').onclick=()=>{page++;void load();};
  }
  async function load(){
    const token=++generation;shell();$('[data-status]').textContent='Consultando cartera…';
    try{
      const params=new URLSearchParams({q:query,clase:category,estado:status,pagina:String(page)});
      if(band!==null)params.set('banda',String(band));if(from)params.set('desde',from);if(to)params.set('hasta',to);
      const result=await apiRequest(`/api/v1/companies/${company}/sales-receivables?${params}`);
      if(!current(token))return;render(result);$('[data-status]').textContent='';
    }catch(error){if(current(token))$('[data-status]').textContent=error.message;}
  }
  document.querySelector('#salesReceivablesNav').addEventListener('click',()=>{
    if(!state.erpSession?.api||!hasPermission('VENTAS.FACTURA.CONTABILIZAR')){showError('Requiere acceso a ventas y conexión al ERP.');return;}
    if(dialog.open)return;company=state.erpSession.company.id;page=1;query='';category='';status='ABIERTA';band=null;from='';to='';dialog.showModal();void load();
  });
})();
