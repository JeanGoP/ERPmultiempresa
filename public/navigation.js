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
  destinations.forEach(([name, selector]) => {
    const group = nav.querySelector(`[data-nav-group="${name}"]`);
    const button = masters.querySelector(selector);
    if (!group || !button) return;
    const children = group.querySelector('.nav-children');
    children.append(button);
  });
  const advances = nav.querySelector('#customerAdvancesNav');
  const treasury = nav.querySelector('[data-nav-group="treasury"] .nav-children');
  if (advances && treasury) treasury.insertBefore(advances, treasury.querySelector('#disbursementsNav'));
  masters.remove();
  nav.querySelectorAll('button:disabled, .nav-group-future').forEach(element => element.remove());
  const titles = { sales: 'Ventas', purchases: 'Compras', inventory: 'Inventario', costs: 'Control', administration: 'Configuración' };
  Object.entries(titles).forEach(([name, title]) => {
    const label = nav.querySelector(`[data-nav-group="${name}"] > summary > span:nth-child(2)`);
    if (label) label.textContent = title;
  });
  const moduleNames = ['sales', 'purchases', 'treasury', 'inventory', 'reports', 'costs', 'zeus', 'administration'];
  const taskNavigation = document.createElement('nav');
  taskNavigation.className = 'task-navigation';
  taskNavigation.setAttribute('aria-label', 'Navegación por módulos');
  taskNavigation.innerHTML = '<p class="task-nav-label">MÓDULOS</p><div class="task-modules"></div>';
  nav.before(taskNavigation);
  nav.hidden = true;
  const moduleList = taskNavigation.querySelector('.task-modules');
  const contextLinks = document.createElement('div');
  contextLinks.id = 'taskSubmenu';
  contextLinks.className = 'task-submenu';
  contextLinks.setAttribute('role', 'group');
  const moduleButtons = new Map();
  let selectedModule = 'purchases';

  function groupFor(name) { return nav.querySelector(`[data-nav-group="${name}"]`); }
  function visibleTasks(group) {
    return [...group.querySelectorAll('.nav-children > .nav-subitem:not(:disabled)')].filter(button => !button.hidden);
  }
  moduleNames.forEach(name => {
    const group = groupFor(name);
    if (!group) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'task-module';
    button.dataset.module = name;
    button.setAttribute('aria-controls', 'taskSubmenu');
    const icon = document.createElement('span');
    icon.className = 'task-module-icon';
    icon.setAttribute('aria-hidden', 'true');
    icon.textContent = group.querySelector('.nav-icon')?.textContent || '•';
    const label = document.createElement('span');
    label.textContent = group.querySelector('summary span:nth-child(2)')?.textContent || name;
    button.append(icon, label);
    button.addEventListener('click', () => selectModule(name));
    moduleList.append(button);
    moduleButtons.set(name, button);
  });
  function renderContext() {
    const group = groupFor(selectedModule);
    if (!group) return;
    contextLinks.replaceChildren();
    let visibleMasters = 0;
    visibleTasks(group).forEach(source => {
      if (source.classList.contains('master-link') && visibleMasters++ === 0) {
        const divider = document.createElement('p');
        divider.className = 'task-context-divider';
        divider.textContent = 'Maestros';
        contextLinks.append(divider);
      }
      const link = document.createElement('button');
      link.type = 'button';
      link.className = 'task-link';
      link.classList.toggle('active', source.classList.contains('active'));
      link.textContent = source.textContent.trim();
      link.addEventListener('click', () => {
        source.click();
        taskNavigation.querySelectorAll('.task-link.active').forEach(item => item.classList.remove('active'));
        link.classList.add('active');
        if (document.body.classList.contains('mobile-nav-open')) document.querySelector('#mobileNavClose')?.click();
      });
      contextLinks.append(link);
    });
  }
  function selectModule(name) {
    selectedModule = name;
    moduleButtons.forEach((button, key) => {
      button.classList.toggle('active', key === name);
      button.setAttribute('aria-expanded', String(key === name));
    });
    moduleButtons.get(name)?.after(contextLinks);
    contextLinks.setAttribute('aria-label', `Opciones de ${moduleButtons.get(name)?.textContent.trim() || name}`);
    renderContext();
  }
  function syncModules() {
    moduleButtons.forEach((button, name) => {
      const group = groupFor(name);
      button.hidden = !group || group.hidden || visibleTasks(group).length === 0;
    });
    if (moduleButtons.get(selectedModule)?.hidden) {
      const first = moduleNames.find(name => !moduleButtons.get(name)?.hidden);
      if (first) selectedModule = first;
    }
    selectModule(selectedModule);
  }
  new MutationObserver(syncModules).observe(nav, { subtree: true, attributes: true, attributeFilter: ['hidden', 'class'] });
  syncModules();

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
    if (group) selectModule(group.dataset.navGroup);
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
})();
