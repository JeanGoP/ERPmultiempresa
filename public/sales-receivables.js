/* Consulta de cartera de clientes: saldos del ERP por vencimiento, sin acciones contables. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(value||0);
  const label=value=>({MOTO:'Motos',OTROS:'Otros artículos',MIXTA:'Mixta',SIN_CLASIFICAR:'Sin clasificar'})[value]||'Sin clasificar';
  const dialog=document.createElement('dialog');dialog.className='erp-dialog egreso-dialog sales-receivables-dialog';document.body.append(dialog);
  let company=0,generation=0,page=1,query='',category='';
  const $=selector=>dialog.querySelector(selector);
  const current=token=>token===generation&&dialog.open&&String(company)===String(state.erpSession?.company?.id);
  function close(){generation++;if(dialog.open)dialog.close();company=0;}
  window.resetSalesReceivables=close;
  dialog.addEventListener('cancel',event=>{event.preventDefault();close();});
  function shell(){
    dialog.innerHTML=`<div class="dialog-heading"><div><span class="dialog-kicker">VENTAS · ${esc(state.erpSession?.company?.name||'Empresa')}</span><h2>Cuentas por cobrar</h2><p class="egreso-help">Saldos y vencimientos registrados en el ERP. Las cuotas futuras no se pueden recaudar.</p></div><button type="button" class="dialog-close" data-close aria-label="Cerrar">×</button></div>
      <form data-filters class="sales-receivables-filters"><label>Buscar cliente o factura<input name="q" type="search" maxlength="100" placeholder="Nombre, identificación o factura" value="${esc(query)}"></label><label>Tipo de cartera<select name="clase"><option value="">Todas</option><option value="MOTO" ${category==='MOTO'?'selected':''}>Motos</option><option value="OTROS" ${category==='OTROS'?'selected':''}>Otros artículos</option><option value="MIXTA" ${category==='MIXTA'?'selected':''}>Mixta</option><option value="SIN_CLASIFICAR" ${category==='SIN_CLASIFICAR'?'selected':''}>Sin clasificar</option></select></label><button class="button primary" type="submit">Consultar</button></form>
      <p data-status role="status" aria-live="polite"></p><div data-results></div>`;
    $('[data-close]').onclick=close;
    $('[data-filters]').onsubmit=event=>{event.preventDefault();query=event.target.elements.q.value.trim();category=event.target.elements.clase.value;page=1;void load();};
  }
  async function load(){
    const token=++generation;shell();$('[data-status]').textContent='Consultando cartera…';
    try{
      const params=new URLSearchParams({q:query,clase:category,pagina:String(page)});
      const result=await apiRequest(`/api/v1/companies/${company}/sales-receivables?${params}`);
      if(!current(token))return;
      const today=new Date().toLocaleDateString('sv-SE',{timeZone:'America/Bogota'});
      $('[data-results]').innerHTML=`<div class="sales-receivables-total"><strong>Saldo pendiente: ${money(result.totalSaldo)}</strong><span>${result.totalRegistros} cuota(s) · Página ${result.pagina} de ${Math.max(1,result.paginas)}</span></div>
        <div class="table-wrap"><table><thead><tr><th>Factura / cuota</th><th>Cliente</th><th>Cartera</th><th>Vencimiento</th><th>Valor original</th><th>Saldo</th><th>Zeus</th></tr></thead><tbody>${result.items.map(x=>`<tr><td><button type="button" class="customer-document-link" data-invoice="${x.id}" aria-label="Ver factura ${esc(x.numero)}">${esc(x.numero)}</button>${x.numeroCuota?`<small>Cuota ${x.numeroCuota}</small>`:''}</td><td>${esc(x.cliente)}<small>${esc(x.identificacion)}</small></td><td>${esc(label(x.claseCartera))}</td><td>${esc(x.vence)}<small>${x.vence<today?'Vencida':'Por vencer'}</small></td><td>${money(x.original)}</td><td><strong>${money(x.saldo)}</strong></td><td>${esc(x.zeusEstado)}</td></tr>`).join('')||'<tr><td colspan="7">No hay saldos pendientes con estos filtros.</td></tr>'}</tbody></table></div>
        <div class="sales-receivables-pages"><button type="button" class="button secondary" data-prev ${page>1?'':'disabled'}>Anterior</button><span>Página ${page}</span><button type="button" class="button secondary" data-next ${page<result.paginas?'':'disabled'}>Siguiente</button></div>`;
      $('[data-prev]').onclick=()=>{page--;void load();};$('[data-next]').onclick=()=>{page++;void load();};
      $('[data-results]').querySelectorAll('[data-invoice]').forEach(button=>button.onclick=()=>{const id=Number(button.dataset.invoice);close();void window.openSavedSalesInvoice(id);});
      $('[data-status]').textContent='';
    }catch(error){if(current(token))$('[data-status]').textContent=error.message;}
  }
  document.querySelector('#salesReceivablesNav').addEventListener('click',()=>{
    if(!state.erpSession?.api||!hasPermission('VENTAS.FACTURA.CONTABILIZAR')){showError('Requiere acceso a ventas y conexión al ERP.');return;}
    if(dialog.open)return;company=state.erpSession.company.id;page=1;query='';category='';dialog.showModal();void load();
  });
})();
