/* Resumen de la empresa activa. Cada bloque conserva su estado si una fuente falla. */
(() => {
  const root = document.querySelector('#homeDashboardModule');
  if (!root) return;
  const money = value => new Intl.NumberFormat('es-CO', { style:'currency', currency:'COP', maximumFractionDigits:0 }).format(Number(value) || 0);
  const integer = value => new Intl.NumberFormat('es-CO').format(Number(value) || 0);
  const safe = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const colors = ['#247f6b','#e2ad48','#e28847','#c56b68','#8e5f82'];
  const labels = ['Por vencer','1–30 días','31–60 días','61–90 días','Más de 90 días'];
  let version = 0, cached = null, selected = 'receivables';
  const status = root.querySelector('#homeStatus');
  const kpis = root.querySelector('#homeKpis');
  const chart = root.querySelector('#homeChart');
  const focus = root.querySelector('#homeFocus');
  const shortcuts = root.querySelector('#homeShortcuts');
  const link = (label, target, icon) => `<button type="button" class="home-shortcut" data-target="${safe(target)}"><span class="home-shortcut-icon" aria-hidden="true">${icon}</span><strong>${label}</strong><span aria-hidden="true">→</span></button>`;
  const open = target => {
    if (target === 'stock') showInventoryView('stock');
    else if (target === 'payables') showAccountsPayable();
    else document.querySelector(target)?.click();
  };
  root.addEventListener('click', event => {
    const target = event.target.closest('[data-target]');
    if (target) open(target.dataset.target);
    const switcher = event.target.closest('[data-chart]');
    if (switcher && cached) { selected = switcher.dataset.chart; renderChart(); }
  });
  root.querySelector('#homeOpenReceivables').addEventListener('click', () => open('#salesReceivablesNav'));
  root.querySelector('#homeRefresh').addEventListener('click', () => void load(true));
  function renderShortcuts() {
    const choices = [
      ['Factura de venta','#salesInvoicesNav','▣','VENTAS.FACTURA.CONTABILIZAR'],
      ['Recibo de caja','#cashReceiptsNav','↙','TESORERIA.RECIBO.CONTABILIZAR'],
      ['Entrada de mercancía','[data-registration-mode="xml"]','⬡','COMPRAS.DOCUMENTO.CREAR'],
      ['Cuentas por pagar','payables','↗','COMPRAS.DOCUMENTO.CREAR'],
      ['Existencias','stock','◫',null],
      ['Informes contables','#accountingReportsNav','▥','CONTABILIDAD.INFORMES.CONSULTAR']
    ];
    shortcuts.innerHTML = choices.filter(([,target,,permission]) => (!permission || hasPermission(permission)) && (target !== 'stock' || canUseInventoryReports())).map(([label,target,icon]) => link(label,target,icon)).join('') || '<p class="home-muted">No hay accesos operativos asignados.</p>';
  }
  function card(label, value, note, tone, target) {
    return `<button type="button" class="home-kpi ${tone}" ${target ? `data-target="${target}"` : 'disabled'}><span>${label}</span><strong>${safe(value)}</strong><small>${safe(note)}</small>${target ? '<em aria-hidden="true">↗</em>' : ''}</button>`;
  }
  function renderChart() {
    root.querySelector('#homeChartScope').textContent = selected === 'receivables' ? 'CARTERA DE CLIENTES' : 'CARTERA DE PROVEEDORES';
    root.querySelector('#homeChartNote').textContent = selected === 'receivables' ? 'Saldo pendiente de las cuotas abiertas en Nexo.' : 'Facturas abiertas en COP registradas en Nexo.';
    const receivables = cached?.receivables?.status === 'fulfilled' ? cached.receivables.value : null;
    const payables = cached?.payables?.status === 'fulfilled' ? cached.payables.value : null;
    const available = selected === 'receivables' ? receivables : payables;
    const buttons = `<div class="home-chart-switch" role="group" aria-label="Cartera mostrada"><button type="button" data-chart="receivables" aria-pressed="${selected === 'receivables'}" ${receivables ? '' : 'disabled'}>Clientes</button><button type="button" data-chart="payables" aria-pressed="${selected === 'payables'}" ${payables ? '' : 'disabled'}>Proveedores</button></div>`;
    if (!available) { chart.innerHTML = buttons + '<p class="home-muted">No hay datos de cartera disponibles para esta vista.</p>'; return; }
    let values;
    if (selected === 'receivables') values = labels.map((_,index) => Number(available.bandas?.find(x => Number(x.indice) === index)?.saldo || 0));
    else {
      const rows = (available.documentos || []).filter(x => Number(x.saldoPendiente) > 0 && x.estado !== 'ANULADA' && String(x.moneda || '').trim() === 'COP');
      values = [0,0,0,0,0];
      rows.forEach(x => { const days = Number(x.diasVencida) || 0; values[days <= 0 ? 0 : days <= 30 ? 1 : days <= 60 ? 2 : days <= 90 ? 3 : 4] += Number(x.saldoPendiente) || 0; });
    }
    const max = Math.max(...values, 1);
    chart.innerHTML = buttons + `<div class="home-bars">${values.map((value,index) => `<div class="home-bar-row"><span>${labels[index]}</span><div class="home-bar-track"><i style="width:${value ? Math.max(value/max*100,1) : 0}%;background:${colors[index]}"></i></div><strong>${safe(money(value))}</strong></div>`).join('')}</div>`;
    root.querySelector('#homeOpenReceivables').hidden = selected !== 'receivables';
  }
  function render() {
    const receivables = cached.receivables.status === 'fulfilled' ? cached.receivables.value : null;
    const payables = cached.payables.status === 'fulfilled' ? cached.payables.value : null;
    const stock = cached.stock.status === 'fulfilled' ? cached.stock.value : null;
    const summary = receivables?.resumen;
    const payableRows = (payables?.documentos || []).filter(x => Number(x.saldoPendiente) > 0 && x.estado !== 'ANULADA' && String(x.moneda || '').trim() === 'COP');
    const payableTotal = payableRows.reduce((sum,x) => sum + Number(x.saldoPendiente || 0), 0);
    const payableOverdue = payableRows.filter(x => Number(x.diasVencida) > 0);
    const inventoryValue = stock?.reduce((sum,x) => sum + Number(x.valorTotal || 0), 0) || 0;
    kpis.innerHTML = [
      card('Por cobrar', summary ? money(summary.saldo) : '—', summary ? `${integer(summary.clientes)} clientes con saldo` : 'Sin datos disponibles', 'primary', summary ? '#salesReceivablesNav' : null),
      card('Cartera vencida', summary ? money(summary.vencido) : '—', summary ? `${integer(summary.cuotasVencidas)} cuotas vencidas` : 'Sin datos disponibles', 'alert', summary ? '#salesReceivablesNav' : null),
      card('Por pagar', payables ? money(payableTotal) : '—', payables ? `${integer(payableRows.length)} facturas abiertas en COP` : 'Sin datos disponibles', '', payables ? 'payables' : null),
      card('Inventario', stock ? money(inventoryValue) : '—', stock ? `${integer(stock.reduce((sum,x) => sum + Number(x.existencia || 0), 0))} unidades` : 'Sin datos disponibles', '', stock ? 'stock' : null)
    ].join('');
    focus.innerHTML = [
      summary ? `<button type="button" class="home-focus-item" data-target="#salesReceivablesNav"><span class="home-focus-mark alert">!</span><span><strong>${integer(summary.cuotasVencidas)} cuotas de clientes vencidas</strong><small>${money(summary.vencido)} pendientes</small></span><b>→</b></button>` : '',
      payables ? `<button type="button" class="home-focus-item" data-target="payables"><span class="home-focus-mark">↗</span><span><strong>${integer(payableOverdue.length)} facturas de proveedores vencidas</strong><small>${money(payableOverdue.reduce((sum,x) => sum + Number(x.saldoPendiente || 0), 0))} pendientes en COP</small></span><b>→</b></button>` : '',
      stock ? `<button type="button" class="home-focus-item" data-target="stock"><span class="home-focus-mark">◫</span><span><strong>${integer(new Set(stock.map(x => x.codigo)).size)} referencias en inventario</strong><small>Consultar existencias por bodega</small></span><b>→</b></button>` : ''
    ].filter(Boolean).join('') || '<p class="home-muted">Los indicadores aparecerán cuando la empresa tenga datos y permisos de consulta.</p>';
    if (selected === 'receivables' && !receivables && payables) selected = 'payables';
    renderChart();
    const failed = [cached.receivables,cached.payables,cached.stock].filter(x => x.status === 'rejected').length;
    status.textContent = failed ? `${failed} sección${failed === 1 ? '' : 'es'} sin datos. Revisa los permisos o actualiza de nuevo.` : 'Datos actualizados de la empresa activa.';
  }
  async function load(force = false) {
    const token = ++version, company = state.erpSession?.company?.id;
    if (!company) return;
    root.querySelector('#homeCompanyName').textContent = state.erpSession.company.name;
    root.querySelector('#homeUserName').textContent = String(state.erpSession.name || 'equipo').split(' ')[0];
    renderShortcuts();
    if (state.runtimeMode !== 'api' || !state.erpSession.api || !state.apiContext) {
      status.textContent = 'Preparando datos de la empresa…';
      if (!state.erpSession.api) { kpis.innerHTML = ''; chart.textContent = 'Conecta la API ERP para consultar indicadores.'; }
      return;
    }
    if (cached?.company === company && !force) { render(); return; }
    status.textContent = 'Actualizando indicadores…';
    root.querySelector('#homeRefresh').disabled = true;
    const base = `/api/v1/companies/${company}`;
    const denied = () => Promise.resolve(null);
    const [receivables,payables,stock] = await Promise.allSettled([
      hasPermission('VENTAS.FACTURA.CONTABILIZAR') ? apiRequest(`${base}/sales-receivables?estado=ABIERTA&pagina=1`) : denied(),
      canUseAccountsPayable() ? apiRequest(`${base}/accounts-payable`) : denied(),
      canUseInventoryReports() ? apiRequest(`${base}/inventory/stock`) : denied()
    ]);
    if (token !== version || String(company) !== String(state.erpSession?.company?.id)) return;
    cached = { company, receivables, payables, stock };
    root.querySelector('#homeRefresh').disabled = false;
    render();
  }
  window.loadHomeDashboard = load;
  window.resetHomeDashboard = () => { version++; cached = null; selected = 'receivables'; };
  const workspaceSections = [...document.querySelectorAll('#moduleStart > section')].filter(x => x !== root);
  new MutationObserver(() => {
    if (!root.hidden && workspaceSections.some(x => !x.hidden)) {
      root.hidden = true;
      document.querySelector('#homeNav')?.classList.remove('active');
    }
  }).observe(document.querySelector('#moduleStart'), { subtree:true, attributes:true, attributeFilter:['hidden'] });
})();
