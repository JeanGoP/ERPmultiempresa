(function setupTaskNavigation() {
  const nav = document.querySelector('.erp-nav');
  const sidebar = document.querySelector('#erpSidebar');
  const searchButton = document.querySelector('#navigationSearchButton');
  const masters = nav?.querySelector('[data-nav-group="masters"]');
  if (!nav || !sidebar || !searchButton || !masters) return;

  const destinations = [
    ['sales', '[data-master-view="clients"]'],
    ['sales', '#salesConceptsNav'],
    ['sales', '#portfolioTypesNav'],
    ['purchases', '[data-master-view="suppliers"]'],
    ['purchases', '[data-master-view="mappings"]'],
    ['inventory', '[data-master-view="articles"]'],
    ['inventory', '[data-master-view="brands"]'],
    ['inventory', '[data-master-view="units"]'],
    ['inventory', '[data-master-view="warehouses"]'],
    ['administration', '[data-master-view="branches"]'],
  ];
  const sections = new Set();
  destinations.forEach(([name, selector]) => {
    const group = nav.querySelector(`[data-nav-group="${name}"]`);
    const button = masters.querySelector(selector);
    if (!group || !button) return;
    const children = group.querySelector('.nav-children');
    if (!sections.has(name)) {
      const heading = document.createElement('p');
      heading.className = 'nav-section-heading';
      heading.textContent = 'Maestros';
      children.append(heading);
      sections.add(name);
    }
    children.append(button);
  });
  masters.remove();
  nav.querySelectorAll('button:disabled, .nav-group-future').forEach(element => element.remove());
  nav.querySelectorAll('.nav-label').forEach(label => {
    if (label.textContent.trim() === 'OPERACIÓN') label.textContent = 'MÓDULOS';
    else if (label.textContent.trim() === 'CONFIGURACIÓN') label.textContent = 'ADMINISTRACIÓN';
    else label.remove();
  });
  const titles = { sales: 'Ventas', purchases: 'Compras', inventory: 'Inventario', costs: 'Control', administration: 'Configuración' };
  Object.entries(titles).forEach(([name, title]) => {
    const label = nav.querySelector(`[data-nav-group="${name}"] > summary > span:nth-child(2)`);
    if (label) label.textContent = title;
  });
  function updateMasterHeadings() {
    nav.querySelectorAll('.nav-section-heading').forEach(heading => {
      const visible = [...heading.parentElement.children].slice([...heading.parentElement.children].indexOf(heading) + 1)
        .some(item => item.classList.contains('master-link') && !item.hidden);
      if (heading.hidden === visible) heading.hidden = !visible;
    });
  }
  new MutationObserver(updateMasterHeadings).observe(nav, { subtree: true, attributes: true, attributeFilter: ['hidden'] });
  updateMasterHeadings();

  const dialog = document.createElement('dialog');
  dialog.className = 'navigation-dialog';
  dialog.setAttribute('aria-label', 'Buscar pantalla o tarea');
  dialog.innerHTML = '<div class="navigation-dialog-head"><span aria-hidden="true">⌕</span><input type="search" aria-label="Buscar pantalla o tarea" placeholder="Buscar pantalla o tarea…" autocomplete="off"><button type="button" aria-label="Cerrar búsqueda">×</button></div><div class="navigation-results" role="listbox"></div><p class="navigation-dialog-help">Escribe para buscar · ↑ ↓ para elegir · Enter para abrir</p>';
  document.body.append(dialog);
  const input = dialog.querySelector('input');
  const results = dialog.querySelector('.navigation-results');
  const normalize = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es-CO');
  const synonyms = {
    'Facturas de venta': 'vender factura cliente',
    'Recibos de caja': 'cobrar recaudar pago cliente',
    'Comprobantes de egreso': 'pagar proveedor egreso',
    'Cuentas por pagar': 'cartera proveedor obligaciones',
    'Cartera': 'cuentas por cobrar clientes cuotas',
    'Existencias': 'stock inventario artículos',
    'Documentos de compra': 'facturas proveedor entradas guardadas',
  };
  let selection = 0;
  let matches = [];

  function availableDestinations() {
    return [...nav.querySelectorAll('.nav-subitem:not(:disabled)')].filter(button =>
      !button.hidden && !button.closest('[data-nav-group]')?.hidden
    );
  }
  function renderResults() {
    const terms = normalize(input.value).split(/\s+/).filter(Boolean);
    matches = availableDestinations().filter(button => {
      const label = button.textContent.trim();
      const group = button.closest('[data-nav-group]')?.querySelector('summary span:nth-child(2)')?.textContent || '';
      const haystack = normalize(`${label} ${group} ${synonyms[label] || ''}`);
      return terms.every(term => haystack.includes(term));
    }).slice(0, 18);
    selection = Math.min(selection, Math.max(matches.length - 1, 0));
    results.replaceChildren();
    if (!matches.length) {
      const empty = document.createElement('p');
      empty.className = 'navigation-empty';
      empty.textContent = 'No hay pantallas disponibles con ese nombre.';
      results.append(empty);
      return;
    }
    matches.forEach((button, index) => {
      const option = document.createElement('button');
      option.type = 'button';
      option.className = 'navigation-result';
      option.setAttribute('role', 'option');
      option.setAttribute('aria-selected', String(index === selection));
      const title = document.createElement('strong');
      title.textContent = button.textContent.trim();
      const group = document.createElement('small');
      group.textContent = button.closest('[data-nav-group]')?.querySelector('summary span:nth-child(2)')?.textContent || '';
      option.append(title, group);
      option.addEventListener('click', () => openDestination(button));
      results.append(option);
    });
  }
  function select(index) {
    selection = (index + matches.length) % matches.length;
    results.querySelectorAll('.navigation-result').forEach((option, position) => option.setAttribute('aria-selected', String(position === selection)));
    results.children[selection]?.scrollIntoView({ block: 'nearest' });
  }
  function openDestination(button) {
    dialog.close();
    const group = button.closest('details[data-nav-group]');
    if (group) group.open = true;
    if (document.body.classList.contains('mobile-nav-open')) document.querySelector('#mobileNavClose')?.click();
    button.click();
  }
  function openSearch() {
    if (document.querySelector('#erpShell')?.hidden) return;
    if (!dialog.open) dialog.showModal();
    input.value = '';
    selection = 0;
    renderResults();
    input.focus();
  }
  searchButton.addEventListener('click', openSearch);
  dialog.querySelector('.navigation-dialog-head button').addEventListener('click', () => dialog.close());
  input.addEventListener('input', () => { selection = 0; renderResults(); });
  input.addEventListener('keydown', event => {
    if (event.key === 'ArrowDown' && matches.length) { event.preventDefault(); select(selection + 1); }
    else if (event.key === 'ArrowUp' && matches.length) { event.preventDefault(); select(selection - 1); }
    else if (event.key === 'Enter' && matches.length) { event.preventDefault(); openDestination(matches[selection]); }
  });
  document.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k' && !event.altKey) {
      event.preventDefault();
      openSearch();
    }
  });
  dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
  nav.addEventListener('click', event => {
    const button = event.target.closest('.nav-subitem:not(:disabled)');
    if (button) button.closest('details[data-nav-group]')?.setAttribute('open', '');
  });
})();
