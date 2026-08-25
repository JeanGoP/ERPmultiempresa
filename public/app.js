const MAX_FILE_SIZE = 25 * 1024 * 1024;
const state = { document: null, containerDocument: null, invoice: null, json: null, fields: [], headers: [], details: [], fileName: '', registrationMode: 'xml', manualLineSequence: 0, erpSession: null, pendingEmail: '', pendingName: '', pendingSuperAdmin: false, runtimeMode: 'api', masterView: 'suppliers', masterEditingArticleId: null, inventoryView: 'stock', inventoryData: [], warehouseReceipts: [], warehouseReceiptDetail: null, advancedView: 'landed', advancedData: [], securityView: 'users', securityData: null, securityEditingUserId: null, securityEditingRoleId: null, securityPasswordUserId: null, apiContext: null, accessInitialized: false, purchaseWorkflow: null, manualWorkflow: null, manualDraft: null, savedPurchaseDocuments: [], savedPurchaseDetail: null };
const $ = (selector) => document.querySelector(selector);
const elements = {
  fileInput: $('#fileInput'), dropZone: $('#dropZone'), browseButton: $('#browseButton'),
  xmlInput: $('#xmlInput'), analyzeButton: $('#analyzeButton'), exampleButton: $('#exampleButton'),
  inputStatus: $('#inputStatus'), results: $('#results'), errorBox: $('#errorBox'),
  documentTitle: $('#documentTitle'),
  invoicePanel: $('#invoicePanel'), xmlWorkspace: $('#xmlWorkspace'), manualWorkspace: $('#manualWorkspace'),
  manualForm: $('#manualForm'), manualLines: $('#manualLines'), manualGrandTotal: $('#manualGrandTotal'),
  manualResult: $('#manualResult'), manualWarehouse: $('#manualWarehouse'), warehouseField: $('#warehouseField'), manualPeriod:$('#manualPeriod'), manualPeriodField:$('#manualPeriodField'),
  manualPaymentCondition:$('#manualPaymentCondition'),manualCreditDays:$('#manualCreditDays'),manualCreditDaysField:$('#manualCreditDaysField'),
  manualDraftButton:$('#manualDraftButton'),manualPostButton:$('#manualPostButton'),
  manualWorkspaceTitle: $('#manualWorkspaceTitle'), manualWorkspaceSubtitle: $('#manualWorkspaceSubtitle'),
  manualTypePill: $('#manualTypePill'), manualFormStatus: $('#manualFormStatus'),
  loginView: $('#loginView'), loginForm: $('#loginForm'), loginEmail: $('#loginEmail'), loginPassword: $('#loginPassword'), loginError: $('#loginError'),
  erpShell: $('#erpShell'), companyDialog: $('#companyDialog'), companySwitcher: $('#companySwitcher'), companyAvatar: $('#companyAvatar'), companyName: $('#companyName'), companyNit: $('#companyNit'),
  userAvatar: $('#userAvatar'), userName: $('#userName'), userEmail: $('#userEmail'), logoutButton: $('#logoutButton'),
  environmentDialog: $('#environmentDialog'), environmentForm: $('#environmentForm'), environmentMessage: $('#environmentMessage'), runtimeBadge: $('#runtimeBadge'),
  breadcrumbCurrent: $('#breadcrumbCurrent'), moduleHeadingTitle: $('#moduleHeadingTitle'), topbarDate: $('#topbarDate'),
  purchaseModule: $('#purchaseModule'), masterDataModule: $('#masterDataModule'), inventoryModule: $('#inventoryModule'), inventoryNav: $('#inventoryNav'), inventoryStats: $('#inventoryStats'), inventoryTable: $('#inventoryTable'), inventorySearch: $('#inventorySearch'), inventoryWarehouse: $('#inventoryWarehouse'), inventoryDateFrom: $('#inventoryDateFrom'), inventoryDateTo: $('#inventoryDateTo'), inventoryDateFromField: $('#inventoryDateFromField'), inventoryDateToField: $('#inventoryDateToField'), inventoryNotice: $('#inventoryNotice'), inventoryOperationPanel: $('#inventoryOperationPanel'), inventoryStatus: $('#inventoryStatus'),
  savedPurchasesModule:$('#savedPurchasesModule'),savedPurchasesNav:$('#savedPurchasesNav'),savedPurchasesStats:$('#savedPurchasesStats'),savedPurchasesStatus:$('#savedPurchasesStatus'),savedPurchasesSearch:$('#savedPurchasesSearch'),savedPurchasesState:$('#savedPurchasesState'),savedPurchasesTable:$('#savedPurchasesTable'),savedPurchasesNotice:$('#savedPurchasesNotice'),savedPurchaseDetail:$('#savedPurchaseDetail'),refreshSavedPurchases:$('#refreshSavedPurchases'),
  advancedControlsModule:$('#advancedControlsModule'),controlsNav:$('#controlsNav'),advancedStats:$('#advancedStats'),advancedTable:$('#advancedTable'),advancedAction:$('#advancedAction'),advancedNotice:$('#advancedNotice'),advancedAudit:$('#advancedAudit'),advancedStatus:$('#advancedStatus'),advancedViewKicker:$('#advancedViewKicker'),advancedViewTitle:$('#advancedViewTitle'),advancedViewSubtitle:$('#advancedViewSubtitle'),
  securityModule:$('#securityModule'),securityAdminNav:$('#securityAdminNav'),securityStats:$('#securityStats'),securityStatus:$('#securityStatus'),securityTable:$('#securityTable'),securityNotice:$('#securityNotice'),securityViewKicker:$('#securityViewKicker'),securityViewTitle:$('#securityViewTitle'),securityViewSubtitle:$('#securityViewSubtitle'),addSecurityRecord:$('#addSecurityRecord'),
  securityUserDialog:$('#securityUserDialog'),securityUserForm:$('#securityUserForm'),securityUserIdentity:$('#securityUserIdentity'),securityUserRoles:$('#securityUserRoles'),securityUserError:$('#securityUserError'),
  securityRoleDialog:$('#securityRoleDialog'),securityRoleForm:$('#securityRoleForm'),securityRolePermissions:$('#securityRolePermissions'),securityRoleError:$('#securityRoleError'),
  securityPasswordDialog:$('#securityPasswordDialog'),securityPasswordForm:$('#securityPasswordForm'),securityPasswordError:$('#securityPasswordError'),
  masterStats: $('#masterStats'), masterViewTitle: $('#masterViewTitle'), masterViewSubtitle: $('#masterViewSubtitle'),
  masterTable: $('#masterTable'), masterSearch: $('#masterSearch'), masterCount: $('#masterCount'), masterNotice: $('#masterNotice'), addMasterRecord: $('#addMasterRecord'),
  masterRecordDialog: $('#masterRecordDialog'), masterRecordForm: $('#masterRecordForm'), masterFormFields: $('#masterFormFields'), masterFormError: $('#masterFormError'), masterDialogTitle: $('#masterDialogTitle'), masterDialogSubtitle: $('#masterDialogSubtitle'),
  superAdminCompanyPanel:$('#superAdminCompanyPanel'),companyCreateForm:$('#companyCreateForm'),companyCreateError:$('#companyCreateError'),companiesAdminNav:$('#companiesAdminNav')
};

const ACCESS = {
  purchases: ['COMPRAS.DOCUMENTO.CREAR'],
  services: ['COMPRAS.SERVICIO.CAUSAR'],
  receiving: ['COMPRAS.RECEPCION.REVISAR', 'COMPRAS.RECEPCION.CONTABILIZAR'],
  inventoryOps: ['INVENTARIO.TRASLADO.DESPACHAR', 'INVENTARIO.TRASLADO.RECIBIR', 'COMPRAS.DEVOLUCION.CONTABILIZAR', 'INVENTARIO.CONTEO.INICIAR', 'INVENTARIO.CONTEO.CAPTURAR', 'INVENTARIO.CONTEO.APROBAR', 'INVENTARIO.CONTEO.APLICAR'],
  inventoryAdmin: ['INVENTARIO.PERIODO.CERRAR', 'INVENTARIO.PERIODO.REABRIR', 'INVENTARIO.NEGATIVO.AUTORIZAR', 'INVENTARIO.AJUSTE.REVERSAR'],
  costs: ['COSTOS.DISTRIBUCION.APROBAR', 'COSTOS.DISTRIBUCION.APLICAR', 'COSTOS.DETERIORO.REGISTRAR', 'INVENTARIO.PERIODO.CERRAR', 'INVENTARIO.PERIODO.REABRIR', 'INVENTARIO.NEGATIVO.AUTORIZAR', 'INVENTARIO.AJUSTE.REVERSAR'],
  masters: ['MAESTROS.PROVEEDOR.ADMINISTRAR', 'MAESTROS.ARTICULO.ADMINISTRAR', 'MAESTROS.INVENTARIO.ADMINISTRAR', 'COMPRAS.HOMOLOGACION.ADMINISTRAR'],
  security: ['SEGURIDAD.PERMISOS.ADMINISTRAR']
};

const uiStorage = { session: 'nexo.erpSession.v1', runtimeMode: 'nexo.runtimeMode', masterData: 'nexo.masterData.v1', apiToken: 'nexo.apiToken.v1' };
const demoCompanies = [
  { empresaId: 1, razonSocial: 'Comercial Andina SAS', nit: '901.234.567-8' },
  { empresaId: 2, razonSocial: 'Motores del Caribe SAS', nit: '900.765.432-1' },
  { empresaId: 3, razonSocial: 'Servicios Corporativos SAS', nit: '901.800.100-4' },
];

function readStoredJson(key) {
  try { return JSON.parse(localStorage.getItem(key) || 'null'); }
  catch { return null; }
}

function displayNameFromEmail(email) {
  return String(email || 'usuario').split('@')[0].split(/[._-]+/).filter(Boolean).map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ') || 'Usuario';
}

function initials(value) {
  return String(value || 'US').split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part.charAt(0).toUpperCase()).join('') || 'US';
}

function openErpDialog(dialog) {
  if (!dialog) return;
  if (typeof dialog.showModal === 'function') dialog.showModal();
  else dialog.setAttribute('open', '');
}

function closeErpDialog(dialog) {
  if (!dialog) return;
  if (typeof dialog.close === 'function' && dialog.open) dialog.close();
  else dialog.removeAttribute('open');
}

function apiToken() { return sessionStorage.getItem(uiStorage.apiToken) || ''; }

async function apiRequest(path, options = {}) {
  const headers = { Accept: 'application/json', ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...(options.headers || {}) };
  if (apiToken()) headers.Authorization = `Bearer ${apiToken()}`;
  const response = await fetch(`/erp-api${path}`, { ...options, headers });
  const payload = await response.json().catch(() => null);
  const validationMessage=payload?.errors?Object.values(payload.errors).flat()[0]:null;
  if (!response.ok) throw new Error(payload?.error || validationMessage || payload?.detail || payload?.title || `La API respondió ${response.status}.`);
  return payload;
}

function renderCompanyOptions(companies, apiMode = false) {
  const container = $('#companyOptions'); container.replaceChildren();
  companies.forEach((company) => {
    const id = company.empresaId; const name = company.razonSocial; const nit = company.nit; const companyInitials = initials(name);
    const button = document.createElement('button'); button.type = 'button'; button.className = 'company-option';
    Object.assign(button.dataset, { companyId: id, companyName: name, companyNit: `NIT ${nit}`, companyInitials, api: apiMode ? 'true' : 'false', currency: company.monedaFuncional || 'COP' });
    const avatar = document.createElement('span'); avatar.textContent = companyInitials;
    const description = document.createElement('strong'); description.textContent = name; const small = document.createElement('small'); small.textContent = `NIT ${nit} · ${apiMode ? 'SQL Server' : 'Empresa demo'}`; description.append(small);
    const arrow = document.createElement('i'); arrow.textContent = '→'; button.append(avatar, description, arrow); container.append(button);
  });
}

function configureSuperAdminCompanyPanel(enabled,hasCompanies=true) {
  elements.superAdminCompanyPanel.hidden=!enabled;
  elements.companyCreateError.hidden=true;
  document.querySelector('.dialog-footnote').textContent=enabled
    ? 'El superadministrador puede crear empresas y trabajar en cualquiera de ellas sin una asignación empresa-rol.'
    : 'En modo local se muestran empresas de demostración. En modo API solo aparecen las empresas autorizadas para el usuario.';
  let empty=$('#companyEmptyState');
  if(!hasCompanies&&enabled){
    if(!empty){empty=document.createElement('p');empty.id='companyEmptyState';empty.className='company-empty';elements.superAdminCompanyPanel.before(empty);}
    empty.textContent='No hay empresas creadas. Completa el formulario para registrar la primera compañía.';
  } else empty?.remove();
}

function updateRuntimeMode(mode, persist = true) {
  state.runtimeMode = mode === 'api' ? 'api' : 'local';
  if (persist) localStorage.setItem(uiStorage.runtimeMode, state.runtimeMode);
  elements.runtimeBadge.classList.toggle('api-mode', state.runtimeMode === 'api');
  elements.runtimeBadge.querySelector('span').textContent = state.runtimeMode === 'api' ? 'API ERP · preparación' : 'Procesamiento local';
  const option = elements.environmentForm.querySelector(`[name="runtimeMode"][value="${state.runtimeMode}"]`);
  if (option) option.checked = true;
  elements.environmentMessage.textContent = state.runtimeMode === 'api'
    ? 'API activa: al iniciar sesión podrás guardar, preparar y contabilizar la entrada en SQL Server.'
    : 'Modo estable: archivos XML y borradores permanecen únicamente en este equipo.';
}

function renderErpSession() {
  const session = state.erpSession;
  if (!session?.company) return;
  elements.companyAvatar.textContent = session.company.initials;
  elements.companyName.textContent = session.company.name;
  elements.companyNit.textContent = session.company.nit;
  elements.userName.textContent = session.name;
  elements.userEmail.textContent = session.email;
  elements.userAvatar.textContent = initials(session.name);
  document.querySelectorAll('.company-option').forEach((option) => option.classList.toggle('active', option.dataset.companyId === String(session.company.id)));
}

function permissionCode(permission) { return String(permission?.codigo || permission?.Codigo || permission || '').toUpperCase(); }
function permissionCodes() { return state.apiContext?.permissionCodes || new Set((state.apiContext?.permissions || []).map(permissionCode)); }
function hasPermission(code) {
  if (state.runtimeMode !== 'api' || !state.erpSession?.api) return true;
  if (state.erpSession?.superAdmin) return true;
  if (!state.apiContext) return false;
  return permissionCodes().has(String(code).toUpperCase());
}
function hasAnyPermission(codes) { return codes.some(hasPermission); }
function canPurchaseMode(mode) {
  if (mode === 'services') return hasPermission('COMPRAS.DOCUMENTO.CREAR') && hasPermission('COMPRAS.SERVICIO.CAUSAR');
  return hasPermission('COMPRAS.DOCUMENTO.CREAR');
}
function canUseReceiving() { return hasAnyPermission(ACCESS.receiving); }
function canUseInventoryReports() { return hasAnyPermission([...ACCESS.purchases, ...ACCESS.inventoryOps, ...ACCESS.inventoryAdmin, ...ACCESS.costs, ...ACCESS.masters]); }
function canUseInventoryOperations() { return hasAnyPermission(ACCESS.inventoryOps); }
function canUseSavedPurchases() { return hasPermission('COMPRAS.DOCUMENTO.CREAR'); }
function isMasterViewAllowed(view) {
  const required = { suppliers: 'MAESTROS.PROVEEDOR.ADMINISTRAR', articles: 'MAESTROS.ARTICULO.ADMINISTRAR', units: 'MAESTROS.INVENTARIO.ADMINISTRAR', warehouses: 'MAESTROS.INVENTARIO.ADMINISTRAR', mappings: 'COMPRAS.HOMOLOGACION.ADMINISTRAR' }[view];
  return Boolean(required && hasPermission(required));
}
function isInventoryViewAllowed(view) {
  if (view === 'receiving') return canUseReceiving();
  if (view === 'operations') return canUseInventoryOperations();
  return canUseInventoryReports();
}
function firstAllowedInventoryView() {
  return ['receiving', 'stock', 'kardex', 'serials', 'expiry', 'operations'].find(isInventoryViewAllowed) || null;
}
function hideWorkspaces() {
  elements.purchaseModule.hidden = true;
  elements.masterDataModule.hidden = true;
  elements.savedPurchasesModule.hidden = true;
  elements.inventoryModule.hidden = true;
  elements.advancedControlsModule.hidden = true;
  elements.securityModule.hidden = true;
}
function showNoAccess() {
  hideWorkspaces();
  document.querySelector('.breadcrumb span').textContent = 'Acceso';
  elements.breadcrumbCurrent.textContent = 'Sin módulos asignados';
  elements.purchaseModule.hidden = false;
  elements.moduleHeadingTitle.textContent = 'Sin permisos asignados';
  elements.xmlWorkspace.hidden = true;
  elements.manualWorkspace.hidden = true;
  elements.results.hidden = true;
  elements.manualResult.hidden = true;
}
function isCurrentWorkspaceAllowed() {
  if (!elements.purchaseModule.hidden) return canPurchaseMode(state.registrationMode);
  if (!elements.savedPurchasesModule.hidden) return canUseSavedPurchases();
  if (!elements.inventoryModule.hidden) return isInventoryViewAllowed(state.inventoryView);
  if (!elements.masterDataModule.hidden) return isMasterViewAllowed(state.masterView);
  if (!elements.advancedControlsModule.hidden) return hasAnyPermission(ACCESS.costs);
  if (!elements.securityModule.hidden) return hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR');
  return false;
}
function routeToDefaultWorkspace(force = false) {
  if (!force && state.accessInitialized && isCurrentWorkspaceAllowed()) return;
  if (canPurchaseMode('xml')) setRegistrationMode('xml');
  else if (canUseReceiving()) showInventoryView('receiving');
  else {
    const inventoryView = firstAllowedInventoryView();
    const masterView = Object.keys(masterViewConfig).find(isMasterViewAllowed);
    if (inventoryView) showInventoryView(inventoryView);
    else if (hasAnyPermission(ACCESS.costs) && typeof showAdvancedView === 'function') showAdvancedView(state.advancedView);
    else if (masterView) showMasterView(masterView);
    else if (hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')) showSecurityView('users');
    else showNoAccess();
  }
  state.accessInitialized = true;
}
function applyAccessControls() {
  const canPurchases = hasPermission('COMPRAS.DOCUMENTO.CREAR');
  const canServices = hasPermission('COMPRAS.SERVICIO.CAUSAR');
  const canReceiving = canUseReceiving();
  const canInventory = canReceiving || canUseInventoryReports() || canUseInventoryOperations();
  const canCosts = hasAnyPermission(ACCESS.costs);
  const canMasters = hasAnyPermission(ACCESS.masters);
  const canSecurity = hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR');
  const setVisible = (selectorOrElement, visible) => {
    const element = typeof selectorOrElement === 'string' ? document.querySelector(selectorOrElement) : selectorOrElement;
    if (element) element.hidden = !visible;
  };

  setVisible('[data-nav-group="purchases"]', canPurchases || canServices);
  setVisible('[data-nav-group="inventory"]', canInventory);
  setVisible('[data-nav-group="costs"]', canCosts);
  setVisible('[data-nav-group="masters"]', canMasters);
  setVisible('[data-nav-group="administration"]', canSecurity || Boolean(state.erpSession?.superAdmin));
  setVisible(elements.companiesAdminNav, Boolean(state.erpSession?.superAdmin));
  setVisible(elements.securityAdminNav, canSecurity);
  setVisible(elements.savedPurchasesNav, canUseSavedPurchases());
  setVisible(elements.inventoryNav, canInventory);
  if (elements.inventoryNav) elements.inventoryNav.textContent = canReceiving && !canUseInventoryReports() && !canUseInventoryOperations() ? 'Recepción física' : 'Operación diaria';

  document.querySelectorAll('[data-registration-mode]').forEach((button) => {
    button.hidden = !canPurchaseMode(button.dataset.registrationMode);
  });
  document.querySelectorAll('[data-master-view]').forEach((button) => {
    button.hidden = !isMasterViewAllowed(button.dataset.masterView);
  });
  document.querySelectorAll('[data-inventory-view]').forEach((button) => {
    button.hidden = !isInventoryViewAllowed(button.dataset.inventoryView);
  });
}

function enterErp(session) {
  state.erpSession = session;
  state.accessInitialized = false;
  localStorage.setItem(uiStorage.session, JSON.stringify(session));
  renderErpSession();
  elements.loginView.hidden = true;
  elements.erpShell.hidden = false;
  hideWorkspaces();
  applyAccessControls();
  if(session.api&&apiToken()) void loadApiCompanyContext();
  else routeToDefaultWorkspace(true);
}

function leaveErp() {
  localStorage.removeItem(uiStorage.session);
  sessionStorage.removeItem(uiStorage.apiToken);
  state.erpSession = null;
  state.apiContext = null;
  state.purchaseWorkflow = null;
  state.savedPurchaseDocuments = [];
  state.savedPurchaseDetail = null;
  state.warehouseReceipts = [];
  state.warehouseReceiptDetail = null;
  state.pendingEmail = '';
  state.pendingSuperAdmin = false;
  closeErpDialog(elements.companyDialog);
  closeErpDialog(elements.environmentDialog);
  elements.erpShell.hidden = true;
  elements.loginView.hidden = false;
  elements.loginPassword.value = '';
  elements.loginError.hidden = true;
  elements.loginEmail.focus();
}

function initializeErpUi() {
  elements.topbarDate.textContent = new Intl.DateTimeFormat('es-CO', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date()).replace(/\./g, '').toLocaleUpperCase('es-CO');
  updateRuntimeMode(localStorage.getItem(uiStorage.runtimeMode) || 'api', false);
  const savedSession = readStoredJson(uiStorage.session);
  if (savedSession?.email && savedSession?.company && (!savedSession.api || apiToken())) enterErp(savedSession);
  else { elements.loginView.hidden = false; elements.erpShell.hidden = true; }
}

function setupCollapsibleNavigation() {
  const groups=Array.from(document.querySelectorAll('.erp-nav details[data-nav-group]'));
  let changing=false;
  groups.forEach((group)=>group.addEventListener('toggle',()=>{
    if(changing||!group.open)return;
    changing=true;
    groups.forEach((other)=>{if(other!==group)other.open=false;});
    changing=false;
  }));
  document.querySelector('.erp-nav').addEventListener('click',(event)=>{
    const destination=event.target.closest('.nav-subitem:not(.muted)');
    if(!destination)return;
    const owner=destination.closest('details[data-nav-group]');
    if(owner&&!owner.open)owner.open=true;
  });
}

const masterViewConfig = {
  suppliers: ['Proveedores', 'Terceros habilitados para compras.', 'proveedores'],
  articles: ['Artículos y servicios', 'Catálogo interno y controles de inventario.', 'artículos y servicios'],
  units: ['Unidades de medida', 'Unidades base, de compra y de venta.', 'unidades'],
  warehouses: ['Bodegas', 'Depósitos y uso opcional de ubicaciones.', 'bodegas'],
  mappings: ['Homologación XML', 'Relación entre códigos del proveedor y artículos internos.', 'homologaciones'],
};

function newMasterDataSeed() {
  return {
    suppliers: [{ id: 'sup-fanalca', identificationType: 'NIT', identification: '890301886', verificationDigit: '5', name: 'Fábrica Nacional de Autopartes S.A.S.', active: true }],
    units: [{ id: 'unit-und', code: 'UND', name: 'Unidad', symbol: 'und', active: true }, { id: 'unit-kgm', code: 'KGM', name: 'Kilogramo', symbol: 'kg', active: true }],
    articles: [
      { id: 'art-repuesto', code: 'REP-MOTO', description: 'Repuesto de motocicleta', type: 'INVENTARIO', unitId: 'unit-und', inventory: true, lot: false, serial: true, expiry: false, active: true },
      { id: 'art-servicio', code: 'SER-TEC', description: 'Servicio técnico de proveedor', type: 'SERVICIO', unitId: 'unit-und', inventory: false, lot: false, serial: false, expiry: false, active: true },
      { id: 'art-flete', code: 'FLETE', description: 'Flete de adquisición', type: 'CONCEPTO', unitId: 'unit-und', inventory: false, lot: false, serial: false, expiry: false, active: true },
    ],
    warehouses: [{ id: 'wh-main', code: 'PPL', name: 'Bodega principal', locations: false, transit: false, active: true }],
    mappings: [],
  };
}

function getCompanyMasterData() {
  if(state.runtimeMode==='api'&&state.apiContext?.masterData) return { database:null,companyId:String(state.erpSession?.company?.id),data:state.apiContext.masterData,api:true };
  const companyId = String(state.erpSession?.company?.id || 'local');
  const database = readStoredJson(uiStorage.masterData) || {};
  if (!database[companyId]) { database[companyId] = newMasterDataSeed(); localStorage.setItem(uiStorage.masterData, JSON.stringify(database)); }
  return { database, companyId, data: database[companyId] };
}

function saveCompanyMasterData(context) { if(context.api) return; context.database[context.companyId] = context.data; localStorage.setItem(uiStorage.masterData, JSON.stringify(context.database)); }
function masterId(prefix) { return `${prefix}-${crypto.randomUUID ? crypto.randomUUID() : Date.now()}`; }
function activeLabel(value) { return value ? 'Activo' : 'Inactivo'; }
function findById(rows,id) { return rows.find((row) => String(row.id) === String(id)); }

async function loadApiCompanyContext() {
  if(state.runtimeMode!=='api'||!state.erpSession?.company?.id||!apiToken()) return;
  const companyId=state.erpSession.company.id; const base=`/api/v1/companies/${companyId}`;
  try {
    const [suppliers,units,articles,mappings,warehouses,periods,accountingPeriods,accounts,companies,permissions]=await Promise.all([
      apiRequest(`${base}/master-data/suppliers`),apiRequest(`${base}/master-data/units`),apiRequest(`${base}/master-data/articles`),
      apiRequest(`${base}/master-data/item-mappings`),apiRequest(`${base}/warehouses`),apiRequest(`${base}/inventory-periods`),
      apiRequest(`${base}/accounting-periods`),apiRequest(`${base}/accounting-accounts`),apiRequest('/api/v1/companies'),apiRequest(`${base}/permissions`),
    ]);
    renderCompanyOptions(companies,true);configureSuperAdminCompanyPanel(Boolean(state.erpSession?.superAdmin),companies.length>0);
    state.apiContext={ warehouses,periods,accountingPeriods,accounts,permissions,permissionCodes:new Set(permissions.map(permissionCode)),masterData:{
      suppliers:suppliers.map(x=>({id:x.terceroId,identificationType:x.tipoIdentificacion,identification:x.numeroIdentificacion,verificationDigit:x.digitoVerificacion||'',name:x.razonSocial,active:x.activo})),
      units:units.map(x=>({id:x.unidadMedidaId,code:x.codigo,name:x.nombre,symbol:x.simbolo,active:x.activa})),
      articles:articles.map(x=>({id:x.articuloId,code:x.codigo,description:x.descripcion,type:x.tipo,unitId:x.unidadBaseId,inventory:x.manejaInventario,lot:x.manejaLote,serial:x.manejaSerial,expiry:x.requiereVencimiento,active:x.activo})),
      warehouses:warehouses.map(x=>({id:x.bodegaId,code:x.codigo,name:x.nombre,locations:x.usaUbicaciones,transit:x.esTransito,active:true})),
      mappings:mappings.map(x=>({id:x.homologacionArticuloProveedorId,supplierId:x.terceroId,externalCode:x.codigoExterno,externalDescription:x.descripcionExterna||'',articleId:x.articuloId,unitId:null,factor:x.factorAUnidadBase,active:x.activa})),
    }};
    applyAccessControls();
    routeToDefaultWorkspace(false);
    renderManualReferenceOptions();
    elements.manualLines.querySelectorAll('[data-manual-line]').forEach(row=>{const classification=row.querySelector('[data-field="classification"]')?.value;const select=row.querySelector('[data-field="articleId"]');if(select)populateManualArticleOptions(select,classification,select.value);});
    if(!elements.masterDataModule.hidden) renderMasterView();
    if(!elements.inventoryModule.hidden){populateInventoryWarehouses();void refreshInventory();}
    if(state.invoice) renderInvoice();
  } catch(error) { showError(`No fue posible cargar los datos de la empresa. ${error.message}`); }
}

async function ensureApiSupplier(invoice) {
  const data=state.apiContext?.masterData; if(!data) throw new Error('Los maestros de la empresa aún no están disponibles.');
  const identification=invoice.supplier.identification; if(!identification) throw new Error('El XML no contiene la identificación del proveedor.');
  let supplier=data.suppliers.find(x=>x.identification===identification); if(supplier) return supplier;
  const saved=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/master-data/suppliers`,{method:'POST',body:JSON.stringify({tipoIdentificacion:'NIT',numeroIdentificacion:identification,digitoVerificacion:null,razonSocial:invoice.supplier.name||'Proveedor desde XML'})});
  supplier={id:saved.id,identificationType:'NIT',identification,verificationDigit:'',name:invoice.supplier.name||'Proveedor desde XML',active:true}; data.suppliers.push(supplier); return supplier;
}

function renderManualReferenceOptions() {
  if(!elements.manualWarehouse||!elements.manualPeriod) return;
  const currentWarehouse=elements.manualWarehouse.value; const currentPeriod=elements.manualPeriod.value;
  elements.manualWarehouse.replaceChildren(new Option('Seleccionar bodega',''));
  const warehouses=state.runtimeMode==='api'&&state.apiContext?state.apiContext.warehouses:getCompanyMasterData().data.warehouses.map(x=>({bodegaId:x.id,codigo:x.code,nombre:x.name}));
  warehouses.forEach(x=>elements.manualWarehouse.add(new Option(`${x.codigo} · ${x.nombre}`,x.bodegaId)));
  if([...elements.manualWarehouse.options].some(x=>x.value===currentWarehouse)) elements.manualWarehouse.value=currentWarehouse;
  elements.manualPeriod.replaceChildren(new Option('Seleccionar periodo',''));
  (state.apiContext?.periods||[]).forEach(x=>elements.manualPeriod.add(new Option(`${x.codigo} · ${x.estado}`,x.periodoInventarioId)));
  if([...elements.manualPeriod.options].some(x=>x.value===currentPeriod)) elements.manualPeriod.value=currentPeriod;
  const apiGoods=state.runtimeMode==='api'&&state.erpSession?.api&&state.registrationMode==='goods';
  elements.manualPeriodField.hidden=!apiGoods; elements.manualPeriod.required=apiGoods;
}

function renderMasterStats(data) {
  const definitions = [
    ['suppliers', data.suppliers.length, 'Proveedores'], ['articles', data.articles.length, 'Artículos'], ['units', data.units.length, 'Unidades'],
    ['warehouses', data.warehouses.length, 'Bodegas'], ['mappings', data.mappings.length, 'Homologaciones'],
  ];
  elements.masterStats.replaceChildren();
  definitions.forEach(([view,count,label]) => {
    const button=document.createElement('button'); button.type='button'; button.className=`master-stat${state.masterView===view?' active':''}`; button.dataset.masterView=view;
    const strong=document.createElement('strong'); strong.textContent=count; const span=document.createElement('span'); span.textContent=label; button.append(strong,span);
    button.addEventListener('click',()=>showMasterView(view)); elements.masterStats.append(button);
  });
}

function masterRows(view,data) {
  if(view==='suppliers') return { headers:['Identificación','Razón social','Tipo','Estado'], rows:data.suppliers.map(x=>[x.identification,x.name,x.identificationType,activeLabel(x.active)]) };
  if(view==='units') return { headers:['Código','Nombre','Símbolo','Estado'], rows:data.units.map(x=>[x.code,x.name,x.symbol,activeLabel(x.active)]) };
  if(view==='articles') return { headers:['Código','Descripción','Tipo','Unidad base','Conversión de compra','Controles','Estado'], rows:data.articles.map(x=>[x.code,x.description,x.type,findById(data.units,x.unitId)?.code||'—',x.purchaseUnitId?`1 ${findById(data.units,x.purchaseUnitId)?.code||''} = ${x.purchaseFactor||1} ${findById(data.units,x.unitId)?.code||''}`:'Unidad base',[x.inventory?'Inventario':'Sin inventario',x.serial?'Serial':'',x.lot?'Lote':'',x.expiry?'Vencimiento':''].filter(Boolean).join(' · '),activeLabel(x.active)]) };
  if(view==='warehouses') return { headers:['Código','Nombre','Ubicaciones','Tránsito','Estado'], rows:data.warehouses.map(x=>[x.code,x.name,x.locations?'Sí':'No',x.transit?'Sí':'No',activeLabel(x.active)]) };
  return { headers:['Proveedor','Código externo','Descripción externa','Artículo interno','Unidad','Factor'], rows:data.mappings.map(x=>[findById(data.suppliers,x.supplierId)?.name||'—',x.externalCode,x.externalDescription||'',`${findById(data.articles,x.articleId)?.code||'—'} · ${findById(data.articles,x.articleId)?.description||''}`,findById(data.units,x.unitId)?.code||'Base',x.factor]) };
}

function masterActionButton(label,action,id,danger=false) {
  const button=document.createElement('button'); button.type='button'; button.textContent=label; button.className=`master-row-action${danger?' danger':''}`;
  button.dataset.masterArticleAction=action; button.dataset.id=String(id); return button;
}

function renderArticleMasterTable(data,query) {
  const articles=data.articles.filter((article)=>{
    const unit=findById(data.units,article.unitId)?.code||'';
    return !query||[article.code,article.description,article.type,unit,activeLabel(article.active)].join(' ').toLocaleLowerCase('es-CO').includes(query);
  });
  const table=document.createElement('table'); const head=document.createElement('thead');
  head.innerHTML='<tr><th>Código</th><th>Descripción</th><th>Tipo</th><th>Unidad base</th><th>Controles</th><th>Estado</th><th>Acciones</th></tr>';
  const body=document.createElement('tbody');
  articles.forEach((article)=>{
    const row=document.createElement('tr');
    const values=[article.code,article.description,article.type,findById(data.units,article.unitId)?.code||'—',[article.inventory?'Inventario':'Sin inventario',article.serial?'Serial / motor / chasis':'',article.lot?'Lote':'',article.expiry?'Vencimiento':''].filter(Boolean).join(' · '),activeLabel(article.active)];
    values.forEach((value)=>{const cell=document.createElement('td');cell.textContent=value;row.append(cell);});
    const actions=document.createElement('td'); actions.className='master-row-actions'; actions.append(masterActionButton('Editar','edit',article.id),masterActionButton('Eliminar','delete',article.id,true)); row.append(actions); body.append(row);
  });
  if(!articles.length){const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=7;cell.className='empty';cell.textContent='No hay artículos que coincidan con la búsqueda.';row.append(cell);body.append(row);}
  table.append(head,body); elements.masterTable.replaceChildren(table); return articles.length;
}

function showMasterNotice(message,isError=false) {
  elements.masterNotice.textContent=message; elements.masterNotice.classList.toggle('error',isError); elements.masterNotice.hidden=!message;
}

function renderMasterView() {
  const context=getCompanyMasterData(); const data=context.data; const config=masterViewConfig[state.masterView];
  elements.masterViewTitle.textContent=config[0]; elements.masterViewSubtitle.textContent=config[1]; elements.addMasterRecord.textContent=state.masterView==='mappings'?'＋ Nueva homologación':'＋ Nuevo registro';
  renderMasterStats(data);
  const query=elements.masterSearch.value.trim().toLocaleLowerCase('es-CO');
  if(state.masterView==='articles'){const count=renderArticleMasterTable(data,query);elements.masterCount.textContent=`${count} ${config[2]}`;return;}
  const source=masterRows(state.masterView,data); const rows=query?source.rows.filter(row=>row.join(' ').toLocaleLowerCase('es-CO').includes(query)):source.rows;
  elements.masterTable.replaceChildren(buildDataTable(source.headers,rows)); elements.masterCount.textContent=`${rows.length} ${config[2]}`;
}

function showMasterView(view) {
  if (!isMasterViewAllowed(view)) { routeToDefaultWorkspace(true); return; }
  state.masterView=view; state.masterEditingArticleId=null; showMasterNotice(''); elements.purchaseModule.hidden=true; elements.masterDataModule.hidden=false;elements.savedPurchasesModule.hidden=true;elements.inventoryModule.hidden=true;elements.advancedControlsModule.hidden=true;elements.securityModule.hidden=true;elements.savedPurchasesNav.classList.remove('active');elements.inventoryNav.classList.remove('active');elements.controlsNav.classList.remove('active');elements.securityAdminNav.classList.remove('active');
  document.querySelector('.breadcrumb span').textContent='Maestros'; elements.breadcrumbCurrent.textContent=masterViewConfig[view][0];
  document.querySelectorAll('[data-registration-mode]').forEach(x=>x.classList.remove('active'));
  document.querySelectorAll('[data-master-view]').forEach(x=>x.classList.toggle('active',x.dataset.masterView===view));
  elements.masterSearch.value=''; renderMasterView(); window.scrollTo({top:0,behavior:'smooth'});
}

function securityBase(){return `/api/v1/companies/${state.erpSession.company.id}/security`;}
function securityCheckbox(value,title,subtitle,checked=false,critical=false){
  const label=document.createElement('label');label.className='security-check-option';
  const input=document.createElement('input');input.type='checkbox';input.value=String(value);input.checked=checked;
  const copy=document.createElement('span');const strong=document.createElement('strong');strong.textContent=title;if(critical)strong.classList.add('permission-critical');
  const small=document.createElement('small');small.textContent=subtitle;copy.append(strong,small);label.append(input,copy);return label;
}
async function loadSecurityData(){
  if(state.runtimeMode!=='api'||!state.erpSession?.api)throw new Error('La administración de seguridad solo está disponible con la API ERP.');
  const [users,roles,permissions]=await Promise.all([apiRequest(`${securityBase()}/users`),apiRequest(`${securityBase()}/roles`),apiRequest(`${securityBase()}/permissions`)]);
  state.securityData={users,roles,permissions};return state.securityData;
}
function securityAction(label,action,id){const button=document.createElement('button');button.type='button';button.textContent=label;button.dataset.securityAction=action;button.dataset.id=String(id);return button;}
function renderSecurityStats(){
  const data=state.securityData;const values=[['Usuarios',data.users.length],['Accesos activos',data.users.filter(x=>x.accesoActivo&&x.activoGlobal).length],['Roles disponibles',data.roles.length],['Permisos configurados',data.permissions.length]];
  elements.securityStats.replaceChildren();values.forEach(([label,value])=>{const card=document.createElement('article');const strong=document.createElement('strong');strong.textContent=value;const span=document.createElement('span');span.textContent=label;card.append(strong,span);elements.securityStats.append(card);});
}
function renderSecurityUsers(){
  const table=document.createElement('table');const head=document.createElement('thead');head.innerHTML='<tr><th>Usuario</th><th>Estado</th><th>Roles en la empresa</th><th>Acciones</th></tr>';const body=document.createElement('tbody');
  state.securityData.users.forEach(user=>{const row=document.createElement('tr');const identity=document.createElement('td');identity.className='security-user-name';const strong=document.createElement('strong');strong.textContent=user.nombreCompleto;const small=document.createElement('small');small.textContent=user.correo;identity.append(strong,small);const status=document.createElement('td');const badge=document.createElement('span');const enabled=user.activoGlobal&&user.accesoActivo;badge.className=`security-badge${enabled?'':' inactive'}`;badge.textContent=enabled?'ACTIVO':'SIN ACCESO';status.append(badge);const roles=document.createElement('td');roles.className='security-role-list';user.roles.forEach(role=>{const tag=document.createElement('span');tag.textContent=role.nombre;roles.append(tag);});if(!user.roles.length)roles.textContent='Sin roles activos';const actions=document.createElement('td');actions.className='security-actions';actions.append(securityAction('Editar acceso','edit-user',user.usuarioId),securityAction('Contraseña','password',user.usuarioId));row.append(identity,status,roles,actions);body.append(row);});
  if(!state.securityData.users.length){const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=4;cell.className='empty';cell.textContent='Aún no hay usuarios vinculados a esta empresa.';row.append(cell);body.append(row);}table.append(head,body);elements.securityTable.replaceChildren(table);
}
function renderSecurityRoles(){
  const permissionById=new Map(state.securityData.permissions.map(x=>[String(x.permisoId),x]));const table=document.createElement('table');const head=document.createElement('thead');head.innerHTML='<tr><th>Rol</th><th>Código</th><th>Permisos</th><th>Acciones</th></tr>';const body=document.createElement('tbody');
  state.securityData.roles.forEach(role=>{const row=document.createElement('tr');const name=document.createElement('td');name.textContent=role.nombre;const code=document.createElement('td');code.textContent=role.codigo;const permissions=document.createElement('td');permissions.textContent=role.permisoIds.length?`${role.permisoIds.length} · ${[...new Set(role.permisoIds.map(id=>permissionById.get(String(id))?.modulo).filter(Boolean))].join(', ')}`:'Sin permisos';const actions=document.createElement('td');actions.className='security-actions';if(state.erpSession.superAdmin)actions.append(securityAction('Editar permisos','edit-role',role.rolId));else actions.textContent='Solo superadministrador';row.append(name,code,permissions,actions);body.append(row);});table.append(head,body);elements.securityTable.replaceChildren(table);
}
function renderSecurityView(){
  if(!state.securityData)return;const users=state.securityView==='users';elements.securityViewKicker.textContent=users?'ACCESO POR EMPRESA':'AUTORIZACIÓN POR ROL';elements.securityViewTitle.textContent=users?'Usuarios autorizados':'Roles y permisos';elements.securityViewSubtitle.textContent=users?'Cada usuario debe tener al menos un rol dentro de esta empresa.':'Los roles agrupan permisos operativos y se reutilizan al asignar usuarios.';elements.addSecurityRecord.textContent=users?'＋ Nuevo usuario':'＋ Nuevo rol';elements.addSecurityRecord.hidden=!users&&!state.erpSession.superAdmin;document.querySelectorAll('[data-security-view]').forEach(x=>x.classList.toggle('active',x.dataset.securityView===state.securityView));renderSecurityStats();users?renderSecurityUsers():renderSecurityRoles();elements.securityStatus.textContent=`${state.securityData.users.length} usuarios · ${state.securityData.roles.length} roles`;
}
async function refreshSecurity(){const stateCard=elements.securityStatus.closest('.module-state');elements.securityStatus.textContent='Cargando seguridad…';elements.securityNotice.hidden=true;try{await loadSecurityData();stateCard?.classList.add('ready');renderSecurityView();}catch(error){stateCard?.classList.remove('ready');elements.securityTable.replaceChildren();elements.securityStatus.textContent='Acceso no disponible';elements.securityNotice.textContent=error.message;elements.securityNotice.hidden=false;}}
function showSecurityView(view='users'){
  if (!hasPermission('SEGURIDAD.PERMISOS.ADMINISTRAR')) { routeToDefaultWorkspace(true); return; }
  state.securityView=view;elements.purchaseModule.hidden=true;elements.masterDataModule.hidden=true;elements.savedPurchasesModule.hidden=true;elements.inventoryModule.hidden=true;elements.advancedControlsModule.hidden=true;elements.securityModule.hidden=false;elements.savedPurchasesNav.classList.remove('active');elements.inventoryNav.classList.remove('active');elements.controlsNav.classList.remove('active');elements.securityAdminNav.classList.add('active');document.querySelector('.breadcrumb span').textContent='Administración';elements.breadcrumbCurrent.textContent='Usuarios y permisos';document.querySelectorAll('[data-registration-mode],[data-master-view]').forEach(x=>x.classList.remove('active'));if(state.securityData)renderSecurityView();else void refreshSecurity();window.scrollTo({top:0,behavior:'smooth'});
}
function fillSecurityRoles(selected=[]){const chosen=new Set(selected.map(String));elements.securityUserRoles.replaceChildren();state.securityData.roles.forEach(role=>elements.securityUserRoles.append(securityCheckbox(role.rolId,role.nombre,role.codigo,chosen.has(String(role.rolId)))));}
function openSecurityUser(user=null){
  state.securityEditingUserId=user?.usuarioId||null;elements.securityUserForm.reset();elements.securityUserError.hidden=true;elements.securityUserIdentity.hidden=Boolean(user);elements.securityUserIdentity.querySelectorAll('input').forEach(input=>input.disabled=Boolean(user));$('#securityUserDialogTitle').textContent=user?'Editar acceso':'Nuevo usuario';$('#securityUserDialogSubtitle').textContent=user?`${user.nombreCompleto} · ${user.correo}`:'Crea sus credenciales y asigna los roles autorizados.';elements.securityUserForm.elements.accesoActivo.checked=user?.accesoActivo??true;fillSecurityRoles(user?.roles.map(x=>x.rolId)||[]);openErpDialog(elements.securityUserDialog);
}
function fillRolePermissions(selected=[]){
  const chosen=new Set(selected.map(String));elements.securityRolePermissions.replaceChildren();const groups=Object.groupBy?Object.groupBy(state.securityData.permissions,x=>x.modulo):state.securityData.permissions.reduce((all,x)=>{(all[x.modulo]??=[]).push(x);return all;},{});
  Object.entries(groups).forEach(([module,permissions])=>{const group=document.createElement('section');group.className='permission-group';const title=document.createElement('strong');title.textContent=module;const grid=document.createElement('div');grid.className='permission-group-grid';permissions.forEach(permission=>grid.append(securityCheckbox(permission.permisoId,permission.nombre,permission.codigo,chosen.has(String(permission.permisoId)),permission.esCritico)));group.append(title,grid);elements.securityRolePermissions.append(group);});
}
function openSecurityRole(role=null){state.securityEditingRoleId=role?.rolId||null;elements.securityRoleForm.reset();elements.securityRoleError.hidden=true;$('#securityRoleDialogTitle').textContent=role?'Editar rol':'Nuevo rol';elements.securityRoleForm.elements.codigo.value=role?.codigo||'';elements.securityRoleForm.elements.nombre.value=role?.nombre||'';fillRolePermissions(role?.permisoIds||[]);openErpDialog(elements.securityRoleDialog);}
async function saveSecurityUser(event){
  event.preventDefault();elements.securityUserError.hidden=true;const roleIds=[...elements.securityUserRoles.querySelectorAll('input:checked')].map(x=>Number(x.value));const edit=Boolean(state.securityEditingUserId);const data=new FormData(elements.securityUserForm);const payload=edit?{accesoActivo:elements.securityUserForm.elements.accesoActivo.checked,rolIds:roleIds}:{correo:String(data.get('correo')||'').trim(),nombreCompleto:String(data.get('nombreCompleto')||'').trim(),password:String(data.get('password')||''),accesoActivo:elements.securityUserForm.elements.accesoActivo.checked,rolIds:roleIds};
  try{if(!roleIds.length)throw new Error('Selecciona al menos un rol.');const result=await apiRequest(`${securityBase()}/users${edit?`/${state.securityEditingUserId}`:''}`,{method:edit?'PUT':'POST',body:JSON.stringify(payload)});closeErpDialog(elements.securityUserDialog);await refreshSecurity();if(!edit&&result.usuarioExistente){elements.securityNotice.textContent='El correo ya existía: se vinculó a esta empresa conservando su contraseña actual.';elements.securityNotice.hidden=false;}}catch(error){elements.securityUserError.textContent=error.message;elements.securityUserError.hidden=false;}
}
async function saveSecurityRole(event){event.preventDefault();elements.securityRoleError.hidden=true;const data=new FormData(elements.securityRoleForm);const permissionIds=[...elements.securityRolePermissions.querySelectorAll('input:checked')].map(x=>Number(x.value));const payload={codigo:String(data.get('codigo')||'').trim(),nombre:String(data.get('nombre')||'').trim(),permisoIds:permissionIds};try{const edit=Boolean(state.securityEditingRoleId);await apiRequest(`${securityBase()}/roles${edit?`/${state.securityEditingRoleId}`:''}`,{method:edit?'PUT':'POST',body:JSON.stringify(payload)});closeErpDialog(elements.securityRoleDialog);await refreshSecurity();}catch(error){elements.securityRoleError.textContent=error.message;elements.securityRoleError.hidden=false;}}
function openSecurityPassword(user){state.securityPasswordUserId=user.usuarioId;elements.securityPasswordForm.reset();elements.securityPasswordError.hidden=true;$('#securityPasswordDialogTitle').textContent=`Contraseña de ${user.nombreCompleto}`;openErpDialog(elements.securityPasswordDialog);}
async function saveSecurityPassword(event){event.preventDefault();elements.securityPasswordError.hidden=true;try{await apiRequest(`${securityBase()}/users/${state.securityPasswordUserId}/password`,{method:'PUT',body:JSON.stringify({password:new FormData(elements.securityPasswordForm).get('password')})});closeErpDialog(elements.securityPasswordDialog);elements.securityNotice.textContent='Contraseña actualizada. Las sesiones anteriores del usuario fueron cerradas.';elements.securityNotice.hidden=false;}catch(error){elements.securityPasswordError.textContent=error.message;elements.securityPasswordError.hidden=false;}}

function savedPurchaseEffectiveState(entry){
  if(entry.estado==='RECHAZADO')return 'ANULADA';
  if(entry.recepcionEstado==='CONTABILIZADA')return 'CONTABILIZADA';
  if(entry.recepcionMercanciaId)return 'PENDIENTE DE CONTABILIZAR';
  return entry.estado==='VALIDADO'?'PREPARADA':entry.estado;
}
function renderSavedPurchaseStats(){
  const rows=state.savedPurchaseDocuments;const values=[['Documentos',rows.length],['Borradores',rows.filter(x=>savedPurchaseEffectiveState(x)==='BORRADOR').length],['Pendientes',rows.filter(x=>savedPurchaseEffectiveState(x)==='PENDIENTE DE CONTABILIZAR').length],['Contabilizados',rows.filter(x=>savedPurchaseEffectiveState(x)==='CONTABILIZADA').length]];
  elements.savedPurchasesStats.replaceChildren();values.forEach(([label,value])=>{const card=document.createElement('article');const strong=document.createElement('strong');strong.textContent=value;const span=document.createElement('span');span.textContent=label;card.append(strong,span);elements.savedPurchasesStats.append(card);});
}
function renderSavedPurchases(){
  const table=document.createElement('table');const head=document.createElement('thead');head.innerHTML='<tr><th>Documento</th><th>Proveedor</th><th>Fecha</th><th>Pago</th><th>Total</th><th>Seriales</th><th>Estado</th><th></th></tr>';const body=document.createElement('tbody');
  state.savedPurchaseDocuments.forEach(entry=>{const row=document.createElement('tr');const identity=document.createElement('td');identity.className='saved-document-identity';const strong=document.createElement('strong');strong.textContent=entry.numeroDocumento;const small=document.createElement('small');small.textContent=`${entry.tipoDocumento} · ${entry.fuente}`;identity.append(strong,small);const supplier=document.createElement('td');supplier.textContent=`${entry.proveedor} · ${entry.proveedorIdentificacion}`;const date=document.createElement('td');date.textContent=entry.fechaDocumento;const payment=document.createElement('td');payment.textContent=entry.condicionPago==='CREDITO'?'Crédito':'Contado';const total=document.createElement('td');total.textContent=manualCurrency(entry.totalPagar);const serials=document.createElement('td');serials.textContent=entry.unidadesSerializadas;const status=document.createElement('td');const badge=document.createElement('span');const effective=savedPurchaseEffectiveState(entry);badge.className=`saved-purchase-badge state-${effective.toLowerCase().replaceAll(' ','-')}`;badge.textContent=effective;status.append(badge);const action=document.createElement('td');const open=document.createElement('button');open.type='button';open.className='button secondary';open.dataset.savedPurchaseId=entry.documentoProveedorId;open.textContent='Abrir';action.append(open);row.append(identity,supplier,date,payment,total,serials,status,action);body.append(row);});
  if(!state.savedPurchaseDocuments.length){const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=8;cell.className='empty';cell.textContent='No hay entradas guardadas con estos filtros.';row.append(cell);body.append(row);}table.append(head,body);elements.savedPurchasesTable.replaceChildren(table);renderSavedPurchaseStats();elements.savedPurchasesStatus.textContent=`${state.savedPurchaseDocuments.length} entradas consultadas`;
}
async function refreshSavedPurchases(){
  elements.savedPurchasesStatus.textContent='Consultando entradas…';elements.savedPurchasesNotice.hidden=true;
  try{if(state.runtimeMode!=='api'||!state.erpSession?.api)throw new Error('Esta bandeja requiere el modo API ERP.');const params=new URLSearchParams();if(elements.savedPurchasesSearch.value.trim())params.set('q',elements.savedPurchasesSearch.value.trim());if(elements.savedPurchasesState.value)params.set('estado',elements.savedPurchasesState.value);state.savedPurchaseDocuments=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents?${params}`);renderSavedPurchases();}
  catch(error){state.savedPurchaseDocuments=[];elements.savedPurchasesTable.replaceChildren(emptyMessage(error.message));elements.savedPurchasesStatus.textContent='No fue posible consultar';elements.savedPurchasesNotice.textContent=error.message;elements.savedPurchasesNotice.hidden=false;renderSavedPurchaseStats();}
}
function savedPurchaseSerialRows(detail){return detail.lineas.flatMap(line=>line.seriales.map(serial=>[line.numeroLinea,line.codigoArticulo||line.codigoExterno||'—',line.descripcion,serial.numeroUnidad,serial.serial||'—',serial.motor||'—',serial.chasis||'—',serial.vin||'—',serial.color||'—',serial.modelo||'—']));}
async function openSavedPurchase(documentId){
  elements.savedPurchaseDetail.hidden=false;elements.savedPurchaseDetail.replaceChildren(emptyMessage('Cargando el detalle y sus seriales…'));
  try{state.savedPurchaseDetail=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents/${documentId}/detail`);renderSavedPurchaseDetail();elements.savedPurchaseDetail.scrollIntoView({behavior:'smooth',block:'start'});}catch(error){elements.savedPurchaseDetail.replaceChildren(emptyMessage(error.message));}
}
function renderSavedPurchaseDetail(){
  const detail=state.savedPurchaseDetail;if(!detail)return;const entry=detail.documento;const inventoryLines=detail.lineas.filter(x=>x.clasificacion==='INVENTARIO');const serviceLines=detail.lineas.filter(x=>x.clasificacion==='SERVICIO_GASTO');const panel=elements.savedPurchaseDetail;panel.replaceChildren();
  const heading=document.createElement('div');heading.className='saved-detail-heading';const copy=document.createElement('div');const kicker=document.createElement('span');kicker.textContent='DETALLE DE LA ENTRADA';const title=document.createElement('h2');title.textContent=`${entry.tipoDocumento} ${entry.numeroDocumento}`;const subtitle=document.createElement('p');subtitle.textContent=`${entry.proveedor} · ${entry.proveedorIdentificacion} · ${manualCurrency(entry.totalPagar)}`;copy.append(kicker,title,subtitle);const close=document.createElement('button');close.type='button';close.className='button secondary';close.textContent='Cerrar detalle';close.addEventListener('click',()=>{panel.hidden=true;state.savedPurchaseDetail=null;});heading.append(copy,close);panel.append(heading);
  const status=document.createElement('div');status.className='workflow-status';status.innerHTML=`<span>Documento<strong>${entry.estado}</strong></span><span>Recepción<strong>${entry.recepcionEstado||'Sin preparar'}</strong></span><span>Pago<strong>${entry.condicionPago==='CREDITO'?`Crédito · ${entry.diasCredito} días`:'Contado'}</strong></span><span>Seriales<strong>${entry.unidadesSerializadas}</strong></span><span>XML<strong>${entry.xmlOriginalGuardado?'Guardado':'No aplica'}</strong></span>`;panel.append(status);
  panel.append(invoiceCard('Artículos y servicios',`${detail.lineas.length} líneas guardadas`,buildDataTable(['Línea','Artículo','Descripción','Clasificación','Cantidad','Unidad','Precio','Descuento','IVA','Retención','Total'],detail.lineas.map(x=>[x.numeroLinea,x.codigoArticulo||x.codigoExterno||'—',x.descripcion,x.clasificacion,x.cantidad,x.unidad||'—',manualCurrency(x.precioUnitario),manualCurrency(x.descuento),manualCurrency(x.impuesto),manualCurrency(x.retencion),manualCurrency(x.totalNeto)])),'saved-detail-lines'));
  const serialRows=savedPurchaseSerialRows(detail);panel.append(invoiceCard('Seriales de motos',serialRows.length?`${serialRows.length} unidades identificadas desde el borrador`:'Este documento no contiene unidades serializadas',serialRows.length?buildDataTable(['Línea','Artículo','Descripción','Moto #','Serial','Motor','Chasis','VIN','Color','Modelo'],serialRows):emptyMessage('No se guardaron seriales, motores, chasis o VIN.'),'serials-card saved-detail-serials'));
  if(entry.estado==='RECHAZADO'||entry.recepcionEstado==='CONTABILIZADA'){const complete=document.createElement('p');complete.className='saved-detail-result';complete.textContent=entry.estado==='RECHAZADO'?'Este borrador fue anulado y se conserva únicamente para auditoría.':`Entrada contabilizada${entry.recepcionNumero?` como ${entry.recepcionNumero}`:''}. Las motos ya están disponibles en Inventario → Operación diaria → Seriales.`;panel.append(complete);return;}
  const actions=document.createElement('div');actions.className='saved-detail-actions';
  if(inventoryLines.length){
    const controls=document.createElement('div');controls.className='workflow-controls';const warehouse=document.createElement('select');warehouse.append(new Option('Selecciona bodega…',''));(state.apiContext?.warehouses||[]).forEach(x=>warehouse.add(new Option(`${x.codigo} · ${x.nombre}`,x.bodegaId)));const period=document.createElement('select');period.append(new Option('Selecciona periodo…',''));(state.apiContext?.periods||[]).forEach(x=>period.add(new Option(`${x.codigo} · ${x.estado}`,x.periodoInventarioId)));const date=document.createElement('input');date.type='date';date.value=entry.fechaDocumento;const field=(text,input)=>{const label=document.createElement('label');label.className='workflow-field';const span=document.createElement('span');span.textContent=text;label.append(span,input);return label;};controls.append(field('Bodega',warehouse),field('Periodo de inventario',period),field('Fecha contable',date));controls.hidden=Boolean(entry.recepcionMercanciaId);panel.append(controls);
    let prepareOnly=null;if(!entry.recepcionMercanciaId){prepareOnly=document.createElement('button');prepareOnly.type='button';prepareOnly.className='button secondary';prepareOnly.textContent='Preparar para recepción física';prepareOnly.disabled=!warehouse.value||!period.value;prepareOnly.addEventListener('click',async()=>{try{prepareOnly.disabled=true;prepareOnly.textContent='Preparando…';const prepared=await prepareSupplierDocumentForReceipt(entry.documentoProveedorId,{hasInventory:true,hasServices:serviceLines.length>0,bodegaId:warehouse.value,periodoInventarioId:period.value,fechaContable:date.value,numeroDocumento:entry.numeroDocumento});await Promise.all([refreshSavedPurchases(),loadApiCompanyContext()]);await openSavedPurchase(entry.documentoProveedorId);showSuccess(prepared.recepcionMercanciaId?'Borrador preparado para recepción física. El auxiliar ya puede verlo.':'Documento preparado.');}catch(error){showError(`No fue posible preparar la recepción. ${error.message}`);prepareOnly.disabled=false;prepareOnly.textContent='Preparar para recepción física';}});actions.append(prepareOnly);}
    const post=document.createElement('button');post.type='button';post.className='button primary large';post.textContent=entry.recepcionMercanciaId?'Contabilizar entrada':'Preparar y contabilizar entrada';post.disabled=!entry.recepcionMercanciaId&&(!warehouse.value||!period.value);const validate=()=>{const missing=!warehouse.value||!period.value;if(!entry.recepcionMercanciaId)post.disabled=missing;if(prepareOnly)prepareOnly.disabled=missing;};warehouse.addEventListener('change',validate);period.addEventListener('change',validate);
    post.addEventListener('click',async()=>{if(!window.confirm(`Se afectarán las existencias y el Kardex con la factura ${entry.numeroDocumento}. ¿Deseas continuar?`))return;try{post.disabled=true;post.textContent='Contabilizando…';let receiptId=entry.recepcionMercanciaId;if(!receiptId){const prepared=await prepareSupplierDocumentForReceipt(entry.documentoProveedorId,{hasInventory:true,hasServices:serviceLines.length>0,bodegaId:warehouse.value,periodoInventarioId:period.value,fechaContable:date.value,numeroDocumento:entry.numeroDocumento});receiptId=prepared.recepcionMercanciaId;}await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/receipts/${receiptId}/post`,{method:'POST',body:JSON.stringify({correlationId:crypto.randomUUID?crypto.randomUUID():null})});await Promise.all([refreshSavedPurchases(),loadApiCompanyContext()]);await openSavedPurchase(entry.documentoProveedorId);showSuccess('Entrada contabilizada. Los seriales ya están disponibles en inventario.');}catch(error){showError(`No fue posible contabilizar la entrada. ${error.message}`);post.disabled=false;post.textContent=entry.recepcionMercanciaId?'Contabilizar entrada':'Preparar y contabilizar entrada';}});actions.append(post);
  }
  if(entry.estado==='BORRADOR'&&!entry.recepcionMercanciaId&&!entry.causacionServicioId){const reject=document.createElement('button');reject.type='button';reject.className='button danger';reject.textContent='Anular borrador';reject.addEventListener('click',async()=>{if(!window.confirm(`¿Anular el borrador ${entry.numeroDocumento}?`))return;try{reject.disabled=true;await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents/${entry.documentoProveedorId}/reject`,{method:'POST',body:'{}'});await refreshSavedPurchases();await openSavedPurchase(entry.documentoProveedorId);}catch(error){showError(error.message);reject.disabled=false;}});actions.append(reject);}panel.append(actions);
  if(serviceLines.length){const note=document.createElement('p');note.className='workflow-notice';note.textContent='Las líneas de servicios se conservan en su causación y deben completar la asignación contable correspondiente.';panel.append(note);}
}
function showSavedPurchases(){
  if (!canUseSavedPurchases()) { routeToDefaultWorkspace(true); return; }
  elements.purchaseModule.hidden=true;elements.masterDataModule.hidden=true;elements.savedPurchasesModule.hidden=false;elements.inventoryModule.hidden=true;elements.advancedControlsModule.hidden=true;elements.securityModule.hidden=true;elements.inventoryNav.classList.remove('active');elements.controlsNav.classList.remove('active');elements.securityAdminNav.classList.remove('active');document.querySelector('.breadcrumb span').textContent='Compras';elements.breadcrumbCurrent.textContent='Entradas guardadas';document.querySelectorAll('[data-registration-mode],[data-master-view]').forEach(x=>x.classList.remove('active'));elements.savedPurchasesNav.classList.add('active');elements.savedPurchaseDetail.hidden=true;if(!state.apiContext&&state.runtimeMode==='api'&&state.erpSession?.api)void loadApiCompanyContext();void refreshSavedPurchases();window.scrollTo({top:0,behavior:'smooth'});
}

const inventoryDemo={
  stock:[{bodega:'Bodega principal',ubicacion:'PISO-MOTOS',codigo:'357683',descripcion:'Motocicleta XR190L2.0',numeroLote:'—',fechaVencimiento:null,existencia:4,valorTotal:38779828,costoPromedio:9694957},{bodega:'Bodega principal',ubicacion:'REP-A1',codigo:'REP-MOTO',descripcion:'Repuesto de motocicleta',numeroLote:'LT-2608',fechaVencimiento:'2027-02-28',existencia:18,valorTotal:2240000,costoPromedio:124444.44}],
  kardex:[{fechaContable:'2026-08-16',tipoMovimiento:'COMPRA',numeroDocumento:'FV-98251',bodega:'Bodega principal',codigo:'357683',descripcion:'Motocicleta XR190L2.0',entrada:4,salida:0,costoUnitario:9694957,valorMovimiento:38779828,existenciaPosterior:4},{fechaContable:'2026-08-15',tipoMovimiento:'COMPRA',numeroDocumento:'FV-98170',bodega:'Bodega principal',codigo:'REP-MOTO',descripcion:'Repuesto de motocicleta',entrada:20,salida:0,costoUnitario:124444.44,valorMovimiento:2488888.8,existenciaPosterior:20}],
  serials:[{codigo:'357683',descripcion:'Motocicleta XR190L2.0',estado:'DISPONIBLE',bodega:'Bodega principal',serial:'XR190-000184',motor:'KD05E-9102841',chasis:'9FMKD0504TB001841',vin:'9FMKD0504TB001841',placa:'—'},{codigo:'357683',descripcion:'Motocicleta XR190L2.0',estado:'EN_TRANSITO',bodega:'Bodega tránsito',serial:'XR190-000185',motor:'KD05E-9102842',chasis:'9FMKD0506TB001842',vin:'9FMKD0506TB001842',placa:'—'}],
  expiry:[{bodega:'Bodega principal',codigo:'REP-MOTO',descripcion:'Repuesto de motocicleta',numeroLote:'LT-2608',fechaVencimiento:'2027-02-28',diasParaVencer:196,estado:'PRÓXIMO',existencia:18}],
};
function inventoryRows(view,rows){if(view==='stock')return{headers:['Bodega','Ubicación','Artículo','Descripción','Lote','Vencimiento','Existencia','Costo promedio','Valor total'],rows:rows.map(x=>[x.bodega,x.ubicacion||'—',x.codigo,x.descripcion,x.numeroLote||'—',x.fechaVencimiento||'—',x.existencia,manualCurrency(x.costoPromedio),manualCurrency(x.valorTotal)])};if(view==='kardex')return{headers:['Fecha','Movimiento','Documento','Bodega','Artículo','Descripción','Entrada','Salida','Costo','Valor','Saldo'],rows:rows.map(x=>[x.fechaContable,x.tipoMovimiento,x.numeroDocumento,x.bodega,x.codigo,x.descripcion,x.entrada,x.salida,manualCurrency(x.costoUnitario),manualCurrency(x.valorMovimiento),x.existenciaPosterior])};if(view==='serials')return{headers:['Artículo','Descripción','Estado','Bodega actual','Serial','Motor','Chasis','VIN','Placa'],rows:rows.map(x=>[x.codigo,x.descripcion,x.estado,x.bodega||'—',x.serial||'—',x.motor||'—',x.chasis||'—',x.vin||'—',x.placa||'—'])};return{headers:['Bodega','Artículo','Descripción','Lote','Fecha de vencimiento','Días','Estado','Existencia'],rows:rows.map(x=>[x.bodega,x.codigo,x.descripcion,x.numeroLote,x.fechaVencimiento,x.diasParaVencer,x.estado,x.existencia])};}
function renderInventoryStats(rows){const apiActive=state.runtimeMode==='api'&&state.erpSession?.api;const source=state.inventoryView==='stock'?rows:(!apiActive?inventoryDemo.stock:[]);const quantity=source.reduce((sum,x)=>sum+Number(x.existencia||0),0);const value=source.reduce((sum,x)=>sum+Number(x.valorTotal||0),0);const cards=[['Referencias',new Set(source.map(x=>x.codigo)).size],['Unidades disponibles',new Intl.NumberFormat('es-CO').format(quantity)],['Valor de inventario',manualCurrency(value)],['Registros en vista',rows.length]];elements.inventoryStats.replaceChildren();cards.forEach(([label,value])=>{const card=document.createElement('article');const strong=document.createElement('strong');strong.textContent=value;const span=document.createElement('span');span.textContent=label;card.append(strong,span);elements.inventoryStats.append(card);});}
function populateInventoryWarehouses(){const current=elements.inventoryWarehouse.value;elements.inventoryWarehouse.replaceChildren(new Option('Todas las bodegas',''));const warehouses=state.apiContext?.warehouses||getCompanyMasterData().data.warehouses.map(x=>({bodegaId:x.id,codigo:x.code,nombre:x.name}));warehouses.forEach(x=>elements.inventoryWarehouse.add(new Option(`${x.codigo} · ${x.nombre}`,x.bodegaId)));elements.inventoryWarehouse.value=[...elements.inventoryWarehouse.options].some(x=>x.value===current)?current:'';}
function renderWarehouseReceiptStats(rows){const totals=rows.reduce((all,x)=>({units:all.units+x.unidadesSerializadas,reviewed:all.reviewed+x.revisadas,ok:all.ok+x.recibidasConforme,issues:all.issues+x.recibidasConNovedad+x.noRecibidas}),{units:0,reviewed:0,ok:0,issues:0});const cards=[['Recepciones pendientes',rows.length],['Motos en revisión',totals.units],['Checks guardados',totals.reviewed],['Con novedad / no recibidas',totals.issues]];elements.inventoryStats.replaceChildren();cards.forEach(([label,value])=>{const card=document.createElement('article');const strong=document.createElement('strong');strong.textContent=value;const span=document.createElement('span');span.textContent=label;card.append(strong,span);elements.inventoryStats.append(card);});}
function renderWarehouseReceipts(rows){const table=document.createElement('table');const head=document.createElement('thead');head.innerHTML='<tr><th>Recepción</th><th>Documento</th><th>Proveedor</th><th>Bodega</th><th>Fecha</th><th>Motos</th><th>Revisión</th><th></th></tr>';const body=document.createElement('tbody');rows.forEach(entry=>{const row=document.createElement('tr');const receipt=document.createElement('td');receipt.className='saved-document-identity';const strong=document.createElement('strong');strong.textContent=entry.numero;const small=document.createElement('small');small.textContent=entry.estado;receipt.append(strong,small);const documentCell=document.createElement('td');documentCell.textContent=`${entry.tipoDocumento} ${entry.numeroDocumento}`;const supplier=document.createElement('td');supplier.textContent=entry.proveedor;const warehouse=document.createElement('td');warehouse.textContent=entry.bodega;const date=document.createElement('td');date.textContent=entry.fechaContable;const units=document.createElement('td');units.textContent=entry.unidadesSerializadas;const review=document.createElement('td');review.textContent=`${entry.revisadas}/${entry.unidadesSerializadas} · ${entry.recibidasConNovedad+entry.noRecibidas} novedad`;const action=document.createElement('td');const open=document.createElement('button');open.type='button';open.className='button secondary';open.dataset.warehouseReceiptId=entry.recepcionMercanciaId;open.textContent='Revisar';action.append(open);row.append(receipt,documentCell,supplier,warehouse,date,units,review,action);body.append(row);});if(!rows.length){const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=8;cell.className='empty';cell.textContent='No hay recepciones pendientes para estos filtros.';row.append(cell);body.append(row);}table.append(head,body);elements.inventoryTable.replaceChildren(table);renderWarehouseReceiptStats(rows);elements.inventoryStatus.textContent=`${rows.length} recepción(es) pendiente(s)`;}
async function refreshWarehouseReceiving(){elements.inventoryStatus.textContent='Consultando recepciones…';elements.inventoryNotice.hidden=true;try{if(!canUseReceiving())throw new Error('Tu usuario no tiene permiso para revisar recepciones físicas.');if(state.runtimeMode!=='api'||!state.erpSession?.api)throw new Error('La recepción física requiere el modo API ERP.');const params=new URLSearchParams();if(elements.inventoryWarehouse.value)params.set('bodegaId',elements.inventoryWarehouse.value);if(elements.inventorySearch.value.trim())params.set('q',elements.inventorySearch.value.trim());state.warehouseReceipts=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/warehouse-receipts?${params}`);renderWarehouseReceipts(state.warehouseReceipts);if(!state.warehouseReceiptDetail)elements.inventoryOperationPanel.replaceChildren(emptyMessage('Selecciona una recepción para revisar el historial físico de cada moto.'));}catch(error){state.warehouseReceipts=[];state.warehouseReceiptDetail=null;elements.inventoryTable.replaceChildren(emptyMessage(error.message));elements.inventoryOperationPanel.replaceChildren();elements.inventoryStatus.textContent='No fue posible consultar';renderWarehouseReceiptStats([]);}}
async function openWarehouseReceipt(receiptId){elements.inventoryOperationPanel.hidden=false;elements.inventoryOperationPanel.replaceChildren(emptyMessage('Cargando motos y revisiones…'));try{state.warehouseReceiptDetail=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/warehouse-receipts/${receiptId}`);renderWarehouseReceiptDetail();elements.inventoryOperationPanel.scrollIntoView({behavior:'smooth',block:'start'});}catch(error){elements.inventoryOperationPanel.replaceChildren(emptyMessage(error.message));}}
function warehouseReceiptCheckRows(){return [...elements.inventoryOperationPanel.querySelectorAll('[data-receipt-unit-id]')].map(row=>({recepcionMercanciaUnidadId:Number(row.dataset.receiptUnitId),estadoFisico:row.querySelector('select').value,observacion:row.querySelector('input').value.trim()||null})).filter(x=>x.estadoFisico);}
async function saveWarehouseReceiptChecks(silent=false){const detail=state.warehouseReceiptDetail;if(!detail)return null;const checks=warehouseReceiptCheckRows();if(!checks.length){if(!silent)throw new Error('Marca al menos una moto antes de guardar la revisión.');return null;}const summary=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/warehouse-receipts/${detail.recepcion.recepcionMercanciaId}/checks`,{method:'PUT',body:JSON.stringify({revisiones:checks})});state.warehouseReceiptDetail=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/warehouse-receipts/${detail.recepcion.recepcionMercanciaId}`);return summary;}
function renderWarehouseReceiptDetail(){const detail=state.warehouseReceiptDetail;if(!detail)return;const receipt=detail.recepcion;const panel=elements.inventoryOperationPanel;panel.replaceChildren();const heading=document.createElement('div');heading.className='operation-heading';heading.innerHTML=`<span>RECEPCIÓN FÍSICA</span><h2>${receipt.numero}</h2><p>${receipt.tipoDocumento} ${receipt.numeroDocumento} · ${receipt.proveedor} · ${receipt.bodega}</p>`;panel.append(heading);const status=document.createElement('div');status.className='workflow-status';status.innerHTML=`<span>Estado<strong>${receipt.estado}</strong></span><span>Motos<strong>${receipt.unidadesSerializadas}</strong></span><span>Conforme<strong>${receipt.recibidasConforme}</strong></span><span>Novedad<strong>${receipt.recibidasConNovedad}</strong></span><span>No recibida<strong>${receipt.noRecibidas}</strong></span>`;panel.append(status);const form=document.createElement('form');form.className='receiving-check-form';const table=document.createElement('table');const head=document.createElement('thead');head.innerHTML='<tr><th>Moto</th><th>Identificadores</th><th>Color / modelo</th><th>Estado físico</th><th>Observación</th></tr>';const body=document.createElement('tbody');detail.unidades.forEach(unit=>{const row=document.createElement('tr');row.dataset.receiptUnitId=unit.recepcionMercanciaUnidadId;const moto=document.createElement('td');moto.innerHTML=`<strong>${unit.codigoArticulo}</strong><small>Línea ${unit.numeroLinea} · Moto ${unit.numeroUnidad}</small>`;const ids=document.createElement('td');ids.textContent=[unit.serial&&`Serial ${unit.serial}`,unit.motor&&`Motor ${unit.motor}`,unit.chasis&&`Chasis ${unit.chasis}`,unit.vin&&`VIN ${unit.vin}`].filter(Boolean).join(' · ')||'Sin identificadores';const color=document.createElement('td');color.textContent=[unit.color,unit.modelo].filter(Boolean).join(' · ')||'—';const stateCell=document.createElement('td');const select=document.createElement('select');select.append(new Option('Sin revisar',''),new Option('Recibida conforme','RECIBIDA_CONFORME'),new Option('Recibida con novedad','RECIBIDA_NOVEDAD'),new Option('No recibida','NO_RECIBIDA'));select.value=unit.estadoFisico||'';stateCell.append(select);const note=document.createElement('td');const input=document.createElement('input');input.maxLength=500;input.placeholder='Observación opcional';input.value=unit.observacion||'';note.append(input);row.append(moto,ids,color,stateCell,note);body.append(row);});if(!detail.unidades.length){const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=5;cell.className='empty';cell.textContent='Esta recepción no tiene motos serializadas para chulear. Puedes contabilizarla igualmente.';row.append(cell);body.append(row);}table.append(head,body);form.append(table);const actions=document.createElement('div');actions.className='saved-detail-actions';if(hasPermission('COMPRAS.RECEPCION.REVISAR')){const save=document.createElement('button');save.type='button';save.className='button secondary';save.textContent='Guardar revisión física';save.addEventListener('click',async()=>{try{save.disabled=true;save.textContent='Guardando…';await saveWarehouseReceiptChecks(false);renderWarehouseReceiptDetail();await refreshWarehouseReceiving();showSuccess('Revisión física guardada.');}catch(error){showError(error.message);}finally{save.disabled=false;save.textContent='Guardar revisión física';}});actions.append(save);}if(hasPermission('COMPRAS.RECEPCION.CONTABILIZAR')){const post=document.createElement('button');post.type='button';post.className='button primary large';post.textContent='Contabilizar e ingresar a bodega';post.addEventListener('click',async()=>{if(!window.confirm(`Se contabilizará la recepción ${receipt.numero} y las motos ingresarán a ${receipt.bodega}. El check físico queda como historial, aunque existan novedades. ¿Deseas continuar?`))return;try{post.disabled=true;post.textContent='Contabilizando…';await saveWarehouseReceiptChecks(true);await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/receipts/${receipt.recepcionMercanciaId}/post`,{method:'POST',body:JSON.stringify({correlationId:crypto.randomUUID?crypto.randomUUID():null})});state.warehouseReceiptDetail=null;elements.inventoryOperationPanel.replaceChildren(emptyMessage('Recepción contabilizada. Las motos ya ingresaron a la bodega.'));await Promise.all([refreshWarehouseReceiving(),loadApiCompanyContext()]);showSuccess('Recepción contabilizada e ingresada a bodega.');}catch(error){showError(`No fue posible contabilizar. ${error.message}`);post.disabled=false;post.textContent='Contabilizar e ingresar a bodega';}});actions.append(post);}if(!actions.children.length)actions.append(emptyMessage('Tu usuario puede consultar esta recepción, pero no tiene acciones asignadas.'));form.append(actions);panel.append(form);}
async function refreshInventory(){const view=state.inventoryView;if(view==='operations'){renderInventoryOperationPanel();return;}if(view==='receiving'){await refreshWarehouseReceiving();return;}elements.inventoryStatus.textContent='Actualizando…';elements.inventoryNotice.hidden=true;try{let rows;if(state.runtimeMode==='api'&&state.erpSession?.api){const base=`/api/v1/companies/${state.erpSession.company.id}`;const params=new URLSearchParams();if(elements.inventoryWarehouse.value)params.set('bodegaId',elements.inventoryWarehouse.value);if(elements.inventorySearch.value.trim())params.set('q',elements.inventorySearch.value.trim());if(view==='kardex'){if(elements.inventoryDateFrom.value)params.set('desde',elements.inventoryDateFrom.value);if(elements.inventoryDateTo.value)params.set('hasta',elements.inventoryDateTo.value);}if(view==='expiry')params.set('dias','365');const endpoint={stock:'inventory/stock',kardex:'inventory/kardex',serials:'inventory/serialized-units',expiry:'inventory/expiry-alerts'}[view];rows=await apiRequest(`${base}/${endpoint}?${params}`);}else{const query=elements.inventorySearch.value.trim().toLocaleLowerCase('es-CO');rows=inventoryDemo[view].filter(x=>!query||Object.values(x).join(' ').toLocaleLowerCase('es-CO').includes(query));elements.inventoryNotice.textContent='Vista demostrativa local. Cambia el origen de datos a API ERP para consultar y registrar movimientos reales en SQL Server.';elements.inventoryNotice.hidden=false;}state.inventoryData=rows;const table=inventoryRows(view,rows);elements.inventoryTable.replaceChildren(buildDataTable(table.headers,table.rows));renderInventoryStats(rows);elements.inventoryStatus.textContent=`${rows.length} registros consultados`;}catch(error){elements.inventoryTable.replaceChildren(emptyMessage(error.message));elements.inventoryStatus.textContent='No fue posible consultar';}}
function showInventoryView(view='stock'){if(!isInventoryViewAllowed(view)){const fallback=firstAllowedInventoryView();if(fallback&&fallback!==view){showInventoryView(fallback);return;}routeToDefaultWorkspace(true);return;}state.inventoryView=view;elements.purchaseModule.hidden=true;elements.masterDataModule.hidden=true;elements.savedPurchasesModule.hidden=true;elements.inventoryModule.hidden=false;elements.advancedControlsModule.hidden=true;elements.securityModule.hidden=true;elements.savedPurchasesNav.classList.remove('active');elements.controlsNav.classList.remove('active');elements.securityAdminNav.classList.remove('active');document.querySelector('.breadcrumb span').textContent=view==='receiving'?'Bodega':'Inventario';elements.breadcrumbCurrent.textContent={stock:'Existencias',receiving:'Recepción física',kardex:'Kardex',serials:'Seriales',expiry:'Vencimientos',operations:'Movimientos'}[view];document.querySelectorAll('[data-registration-mode],[data-master-view]').forEach(x=>x.classList.remove('active'));elements.inventoryNav.classList.add('active');document.querySelectorAll('[data-inventory-view]').forEach(x=>x.classList.toggle('active',x.dataset.inventoryView===view));const isKardex=view==='kardex';const isOperations=view==='operations';const isReceiving=view==='receiving';elements.inventoryDateFromField.hidden=!isKardex;elements.inventoryDateToField.hidden=!isKardex;elements.inventoryTable.hidden=isOperations;elements.inventoryOperationPanel.hidden=!(isOperations||isReceiving);elements.inventorySearch.closest('label').hidden=isOperations;elements.inventoryWarehouse.closest('label').hidden=isOperations;$('#refreshInventory').hidden=isOperations;populateInventoryWarehouses();if(isReceiving)state.warehouseReceiptDetail=null;void refreshInventory();window.scrollTo({top:0,behavior:'smooth'});}
function fillOperationSelect(select,rows,valueKey,label){select.replaceChildren(new Option('Seleccionar…',''));rows.forEach(x=>select.add(new Option(label(x),x[valueKey])));}
function renderInventoryOperationPanel(){
  const panel=elements.inventoryOperationPanel;panel.replaceChildren();const heading=document.createElement('div');heading.className='operation-heading';heading.innerHTML='<span>OPERACIÓN DE INVENTARIO</span><h2>Traslados y devoluciones</h2><p>Cada documento conserva el costo y el origen; las unidades serializadas mantienen bodega, estado e historial.</p>';
  const form=document.createElement('form');form.className='inventory-operation-form';form.innerHTML='<label><span>Tipo de operación</span><select name="type"><option value="transfer">Traslado entre bodegas</option><option value="supplier">Devolución a proveedor</option><option value="sales">Devolución de cliente</option></select></label><label><span>Número</span><input name="number" required></label><label><span>Fecha contable</span><input name="date" type="date" required></label><label><span>Periodo</span><select name="period" required></select></label><label data-op-field="origin"><span>Bodega origen</span><select name="origin"></select></label><label data-op-field="destination"><span>Bodega destino</span><select name="destination"></select></label><label data-op-field="article"><span>Artículo</span><select name="article"></select></label><label data-op-field="source" hidden><span>Documento / línea original</span><select name="source"></select></label><label><span>Cantidad</span><input name="quantity" type="number" min="0.000001" step="0.000001" value="1" required></label><label><span>Seriales (IDs separados por coma)</span><input name="serials" placeholder="Opcional"></label><label class="wide"><span>Motivo</span><input name="reason" value="Movimiento operativo de inventario"></label><button class="button primary wide" type="submit">Crear y contabilizar</button><div class="operation-result wide" hidden></div>';
  panel.append(heading,form);const warehouses=state.apiContext?.warehouses||[];const articles=state.apiContext?.masterData?.articles?.filter(x=>x.inventory)||[];fillOperationSelect(form.elements.period,state.apiContext?.periods||[],'periodoInventarioId',x=>`${x.codigo} · ${x.estado}`);fillOperationSelect(form.elements.origin,warehouses,'bodegaId',x=>`${x.codigo} · ${x.nombre}`);fillOperationSelect(form.elements.destination,warehouses,'bodegaId',x=>`${x.codigo} · ${x.nombre}`);fillOperationSelect(form.elements.article,articles,'id',x=>`${x.code} · ${x.description}`);form.elements.date.value=new Date().toISOString().slice(0,10);form.elements.number.value=`MOV-${Date.now().toString().slice(-6)}`;
  async function configure(){const type=form.elements.type.value;form.querySelector('[data-op-field="origin"]').hidden=type!=='transfer';form.querySelector('[data-op-field="destination"]').hidden=type!=='transfer';form.querySelector('[data-op-field="article"]').hidden=type!=='transfer';form.querySelector('[data-op-field="source"]').hidden=type==='transfer';if(type!=='transfer'&&state.runtimeMode==='api'&&state.erpSession?.api){const base=`/api/v1/companies/${state.erpSession.company.id}`;const rows=await apiRequest(`${base}/${type==='supplier'?'supplier-returns':'sales-returns'}/sources`);form.elements.source.replaceChildren(new Option('Seleccionar documento original…',''));rows.forEach(x=>{const option=new Option(`${x.documento||x.recepcion} · ${x.codigo} · disponible ${x.cantidadDisponible}`,x.movimientoSalidaOriginalId||x.recepcionMercanciaLineaId);option.dataset.row=JSON.stringify(x);form.elements.source.add(option);});}}
  form.elements.type.addEventListener('change',()=>void configure());form.addEventListener('submit',async event=>{event.preventDefault();const output=form.querySelector('.operation-result');output.hidden=false;output.textContent='Procesando operación…';try{if(state.runtimeMode!=='api'||!state.erpSession?.api)throw new Error('Activa API ERP para registrar movimientos reales.');const base=`/api/v1/companies/${state.erpSession.company.id}`;const serials=form.elements.serials.value.split(',').map(x=>Number(x.trim())).filter(Boolean);const number=form.elements.number.value;const date=form.elements.date.value;const period=Number(form.elements.period.value);let created,posted;if(form.elements.type.value==='transfer'){created=await apiRequest(`${base}/transfers`,{method:'POST',body:JSON.stringify({numero:number,bodegaOrigenId:Number(form.elements.origin.value),bodegaTransitoId:null,bodegaDestinoId:Number(form.elements.destination.value),fechaSalida:`${date}T12:00:00`,lineas:[{articuloId:Number(form.elements.article.value),loteId:null,cantidad:Number(form.elements.quantity.value),unidadSerializadaIds:serials}]})});posted=await apiRequest(`${base}/transfers/${created.documentoId}/dispatch`,{method:'POST',body:JSON.stringify({periodoInventarioId:period,fechaContable:date,fechaRecepcion:null})});output.replaceChildren(document.createTextNode(`Traslado ${created.numero} despachado · ${posted.movimientos} movimientos. `));const receive=document.createElement('button');receive.type='button';receive.className='button secondary';receive.textContent='Recibir en destino';receive.addEventListener('click',async()=>{const result=await apiRequest(`${base}/transfers/${created.documentoId}/receive`,{method:'POST',body:JSON.stringify({periodoInventarioId:period,fechaContable:date,fechaRecepcion:`${date}T12:00:00`})});output.textContent=`Traslado recibido · ${result.movimientos} movimientos · estado ${result.estado}.`;});output.append(receive);}else{const source=JSON.parse(form.elements.source.selectedOptions[0].dataset.row);const supplier=form.elements.type.value==='supplier';const path=supplier?'supplier-returns':'sales-returns';const line=supplier?{recepcionMercanciaLineaId:source.recepcionMercanciaLineaId,articuloId:source.articuloId,cantidadBase:Number(form.elements.quantity.value),ubicacionId:null,loteId:source.loteId,unidadSerializadaIds:serials}:{movimientoSalidaOriginalId:source.movimientoSalidaOriginalId,articuloId:source.articuloId,cantidadBase:Number(form.elements.quantity.value),ubicacionId:null,loteId:source.loteId,unidadSerializadaIds:serials};created=await apiRequest(`${base}/${path}`,{method:'POST',body:JSON.stringify({numero:number,terceroId:source.terceroId,bodegaId:source.bodegaId,periodoInventarioId:period,fechaMovimiento:`${date}T12:00:00`,fechaContable:date,motivo:form.elements.reason.value,lineas:[line]})});posted=await apiRequest(`${base}/${path}/${created.documentoId}/post`,{method:'POST',body:'{}'});output.textContent=`${supplier?'Devolución a proveedor':'Devolución de cliente'} contabilizada · ${posted.movimientos} movimiento(s) · estado ${posted.estado}.`;}}catch(error){output.textContent=error.message;}});void configure();
}

function addMasterField(labelText,name,type='text',options=null,wide=false,required=true) {
  const label=document.createElement('label'); if(wide) label.className='wide'; const span=document.createElement('span'); span.textContent=labelText;
  let input;
  if(options){ input=document.createElement('select'); options.forEach(([value,text])=>{const option=document.createElement('option');option.value=value;option.textContent=text;input.append(option);}); }
  else { input=document.createElement('input'); input.type=type; }
  input.name=name; input.required=required; label.append(span,input); elements.masterFormFields.append(label); return input;
}

function addMasterCheck(labelText,name,checked=false) {
  const label=document.createElement('label'); label.className='check-field'; const input=document.createElement('input'); input.type='checkbox'; input.name=name; input.checked=checked;
  const span=document.createElement('span'); span.textContent=labelText; label.append(input,span); elements.masterFormFields.append(label); return input;
}

function openMasterForm(article=null) {
  const data=getCompanyMasterData().data; const editing=state.masterView==='articles'&&article?.id!=null?article:null; state.masterEditingArticleId=editing?.id||null;
  elements.masterFormFields.replaceChildren(); elements.masterFormError.hidden=true;
  elements.masterDialogTitle.textContent=editing?'Editar artículo':`Nuevo: ${masterViewConfig[state.masterView][0]}`;
  elements.masterDialogSubtitle.textContent=editing?'Actualiza la información permitida del artículo.':'Completa la información requerida.';
  if(state.masterView==='suppliers') { addMasterField('Tipo de identificación','identificationType','text',[['NIT','NIT'],['CC','Cédula'],['CE','Cédula de extranjería']]); addMasterField('Número de identificación *','identification'); addMasterField('Dígito de verificación','verificationDigit','text',null,false,false); addMasterField('Razón social *','name','text',null,true); }
  else if(state.masterView==='units') { addMasterField('Código *','code'); addMasterField('Símbolo *','symbol'); addMasterField('Nombre *','name','text',null,true); }
  else if(state.masterView==='articles') { addMasterField('Código interno *','code'); addMasterField('Tipo *','type','text',[['INVENTARIO','Artículo inventariable'],['SERVICIO','Servicio'],['ACTIVO_FIJO','Activo fijo'],['CONCEPTO','Concepto de costo']]); addMasterField('Descripción *','description','text',null,true); addMasterField('Unidad base *','unitId','text',data.units.map(x=>[x.id,`${x.code} · ${x.name}`])); addMasterField('Unidad de compra','purchaseUnitId','text',[['','Igual a la unidad base'],...data.units.map(x=>[x.id,`${x.code} · ${x.name}`])],false,false); const purchaseFactor=addMasterField('Factor a unidad base','purchaseFactor','number',null,false,false); purchaseFactor.min='0.0000000001'; purchaseFactor.step='0.0000000001'; purchaseFactor.value='1'; addMasterCheck('Maneja inventario','inventory',true); addMasterCheck('Maneja serial / motor / chasis','serial'); addMasterCheck('Maneja lote','lot'); addMasterCheck('Requiere vencimiento','expiry'); }
  else if(state.masterView==='warehouses') { addMasterField('Código *','code'); addMasterField('Nombre *','name'); addMasterCheck('Usa ubicaciones','locations'); addMasterCheck('Es bodega de tránsito','transit'); }
  else { addMasterField('Proveedor *','supplierId','text',data.suppliers.map(x=>[x.id,`${x.identification} · ${x.name}`]),true); addMasterField('Código externo *','externalCode'); addMasterField('Descripción externa','externalDescription','text',null,true,false); addMasterField('Artículo interno *','articleId','text',data.articles.map(x=>[x.id,`${x.code} · ${x.description}`]),true); addMasterField('Unidad','unitId','text',[['','Unidad base'],...data.units.map(x=>[x.id,`${x.code} · ${x.name}`])],false,false); const factor=addMasterField('Factor a unidad base *','factor','number'); factor.min='0.0000000001'; factor.step='0.0000000001'; factor.value='1'; }
  if(editing){
    const values={code:editing.code,type:editing.type,description:editing.description,unitId:editing.unitId,purchaseUnitId:editing.purchaseUnitId||'',purchaseFactor:editing.purchaseFactor||1};
    Object.entries(values).forEach(([name,value])=>{if(elements.masterRecordForm.elements[name])elements.masterRecordForm.elements[name].value=String(value);});
    ['inventory','serial','lot','expiry'].forEach(name=>{if(elements.masterRecordForm.elements[name])elements.masterRecordForm.elements[name].checked=Boolean(editing[name]);});
  }
  openErpDialog(elements.masterRecordDialog);
}

async function saveMasterRecord(event) {
  event.preventDefault(); const values=Object.fromEntries(new FormData(elements.masterRecordForm)); const context=getCompanyMasterData(); const data=context.data;
  const checkbox=(name)=>elements.masterRecordForm.elements[name]?.checked||false;
  try {
    if(context.api){
      const base=`/api/v1/companies/${state.erpSession.company.id}/master-data`;let path;let payload;
      if(state.masterView==='suppliers'){path='suppliers';payload={tipoIdentificacion:values.identificationType,numeroIdentificacion:values.identification.trim(),digitoVerificacion:values.verificationDigit.trim()||null,razonSocial:values.name.trim()};}
      else if(state.masterView==='units'){path='units';payload={codigo:values.code.trim().toUpperCase(),nombre:values.name.trim(),simbolo:values.symbol.trim()};}
      else if(state.masterView==='articles'){path='articles';payload={codigo:values.code.trim().toUpperCase(),descripcion:values.description.trim(),tipo:values.type,unidadBaseId:Number(values.unitId),manejaInventario:values.type==='SERVICIO'?false:checkbox('inventory'),manejaLote:checkbox('lot'),manejaSerial:checkbox('serial'),requiereVencimiento:checkbox('expiry'),pesoBaseKg:null,volumenBaseM3:null};}
      else if(state.masterView==='warehouses'){path='warehouses';payload={codigo:values.code.trim().toUpperCase(),nombre:values.name.trim(),usaUbicaciones:checkbox('locations'),esTransito:checkbox('transit')};}
      else{path='item-mappings';payload={terceroId:Number(values.supplierId),codigoExterno:values.externalCode.trim(),descripcionExterna:values.externalDescription.trim()||null,articuloId:Number(values.articleId),unidadMedidaId:values.unitId?Number(values.unitId):null,factorAUnidadBase:Number(values.factor)||1};}
      const editingArticle=state.masterView==='articles'&&state.masterEditingArticleId; const endpoint=editingArticle?`${base}/articles/${editingArticle}`:`${base}/${path}`;
      await apiRequest(endpoint,{method:editingArticle?'PUT':'POST',body:JSON.stringify(payload)}); state.masterEditingArticleId=null; await loadApiCompanyContext();closeErpDialog(elements.masterRecordDialog);renderMasterView();showMasterNotice(editingArticle?'Artículo actualizado correctamente.':'Registro guardado correctamente.');if(state.invoice)renderInvoice();return;
    }
    if(state.masterView==='suppliers') { const current=data.suppliers.find(x=>x.identification===values.identification); const record={id:current?.id||masterId('sup'),identificationType:values.identificationType,identification:values.identification.trim(),verificationDigit:values.verificationDigit.trim(),name:values.name.trim(),active:true}; current?Object.assign(current,record):data.suppliers.push(record); }
    else if(state.masterView==='units') { const current=data.units.find(x=>x.code.toUpperCase()===values.code.trim().toUpperCase()); const record={id:current?.id||masterId('unit'),code:values.code.trim().toUpperCase(),name:values.name.trim(),symbol:values.symbol.trim(),active:true}; current?Object.assign(current,record):data.units.push(record); }
    else if(state.masterView==='articles') { const editing=findById(data.articles,state.masterEditingArticleId); const normalizedCode=values.code.trim().toUpperCase(); const duplicate=data.articles.find(x=>x!==editing&&x.code.toUpperCase()===normalizedCode); if(duplicate)throw new Error('Ya existe otro artículo con ese código.'); const current=editing||data.articles.find(x=>x.code.toUpperCase()===normalizedCode); const inventory=values.type==='SERVICIO'?false:checkbox('inventory'); const record={id:current?.id||masterId('art'),code:normalizedCode,description:values.description.trim(),type:values.type,unitId:values.unitId,purchaseUnitId:values.purchaseUnitId||'',purchaseFactor:Number(values.purchaseFactor)||1,inventory,serial:checkbox('serial'),lot:checkbox('lot'),expiry:checkbox('expiry'),active:true}; current?Object.assign(current,record):data.articles.push(record); state.masterEditingArticleId=null; }
    else if(state.masterView==='warehouses') { const current=data.warehouses.find(x=>x.code.toUpperCase()===values.code.trim().toUpperCase()); const record={id:current?.id||masterId('wh'),code:values.code.trim().toUpperCase(),name:values.name.trim(),locations:checkbox('locations'),transit:checkbox('transit'),active:true}; current?Object.assign(current,record):data.warehouses.push(record); }
    else { const current=data.mappings.find(x=>x.supplierId===values.supplierId&&x.externalCode.toUpperCase()===values.externalCode.trim().toUpperCase()); const record={id:current?.id||masterId('map'),supplierId:values.supplierId,externalCode:values.externalCode.trim(),externalDescription:values.externalDescription.trim(),articleId:values.articleId,unitId:values.unitId||findById(data.articles,values.articleId)?.unitId||'',factor:Number(values.factor)||1,active:true}; current?Object.assign(current,record):data.mappings.push(record); }
    saveCompanyMasterData(context); closeErpDialog(elements.masterRecordDialog); renderMasterView(); showMasterNotice('Registro guardado correctamente.'); if(state.invoice) renderInvoice();
  } catch(error) { elements.masterFormError.textContent=error.message||'No fue posible guardar el registro.'; elements.masterFormError.hidden=false; }
}

async function deleteMasterArticle(article) {
  if(!article||!window.confirm(`¿Eliminar el artículo ${article.code} · ${article.description}?\n\nSolo podrá eliminarse si nunca ha sido utilizado.`))return;
  const context=getCompanyMasterData();
  try{
    if(context.api){await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/master-data/articles/${article.id}`,{method:'DELETE'});await loadApiCompanyContext();}
    else{if(context.data.mappings.some(x=>String(x.articleId)===String(article.id)))throw new Error('El artículo tiene homologaciones con proveedores y no puede eliminarse.');context.data.articles=context.data.articles.filter(x=>String(x.id)!==String(article.id));saveCompanyMasterData(context);}
    renderMasterView();showMasterNotice(`Artículo ${article.code} eliminado correctamente.`);if(state.invoice)renderInvoice();
  }catch(error){showMasterNotice(error.message||'No fue posible eliminar el artículo.',true);}
}

const exampleXml = `<?xml version="1.0" encoding="UTF-8"?>
<Factura moneda="COP" version="1.0">
  <Numero>FV-1042</Numero><Fecha>2026-08-14</Fecha>
  <Cliente identificacion="900123456"><Nombre>Comercial Andina SAS</Nombre><Ciudad>Bogotá</Ciudad></Cliente>
  <Lineas>
    <Linea codigo="A-01"><Descripcion>Café especial</Descripcion><Cantidad>2</Cantidad><Precio>42000</Precio></Linea>
    <Linea codigo="B-07"><Descripcion>Filtro de cerámica</Descripcion><Cantidad>1</Cantidad><Precio>65000</Precio></Linea>
  </Lineas>
  <Totales><Subtotal>149000</Subtotal><Impuesto>28310</Impuesto><Total>177310</Total></Totales>
</Factura>`;

function localName(node) { return node.localName || node.nodeName.replace(/^.*:/, ''); }
function elementChildren(node) { return Array.from(node.children || []); }
function directText(node) {
  return Array.from(node.childNodes || []).filter((child) => child.nodeType === Node.TEXT_NODE || child.nodeType === Node.CDATA_SECTION_NODE)
    .map((child) => child.nodeValue.trim()).filter(Boolean).join(' ');
}
function childrenByLocal(node, name) { return elementChildren(node).filter((child) => localName(child) === name); }
function childByLocal(node, name) { return childrenByLocal(node, name)[0] || null; }
function nodeAt(node, names) { return names.reduce((current, name) => current ? childByLocal(current, name) : null, node); }
function textAt(node, names) { const target = nodeAt(node, names); return target ? directText(target) : ''; }
function descendantsByLocal(node, name) { return Array.from(node?.getElementsByTagNameNS?.('*', name) || []); }
function firstDescendantText(node, ...names) {
  for (const name of names) {
    const target = descendantsByLocal(node, name)[0];
    if (target && directText(target)) return directText(target);
  }
  return '';
}
function numeric(value) {
  const normalized = String(value ?? '').trim().replace(',', '.');
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function datePlusDays(value, days) {
  if (!value) return '';
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return '';
  date.setUTCDate(date.getUTCDate() + Number(days || 0));
  return date.toISOString().slice(0, 10);
}

function daysBetweenDates(start, end) {
  if (!start || !end) return 0;
  const from = new Date(`${start}T00:00:00Z`); const to = new Date(`${end}T00:00:00Z`);
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) return 0;
  return Math.max(Math.round((to - from) / 86400000), 0);
}
function normalizePropertyName(value) {
  return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
}
function extractItemProperties(itemNode) {
  return descendantsByLocal(itemNode, 'AdditionalItemProperty').map((property) => ({
    name: textAt(property, ['Name']) || textAt(property, ['NameCode']) || firstDescendantText(property, 'Name', 'NameCode'),
    value: textAt(property, ['Value']) || textAt(property, ['ValueQuantity']) || textAt(property, ['ValueQualifier']) || firstDescendantText(property, 'Value', 'ValueQuantity', 'ValueQualifier'),
  })).filter((property) => property.name || property.value);
}
function propertyValue(properties, aliases) {
  const match = properties.find((property) => property.value && aliases.some((alias) => normalizePropertyName(property.name).includes(alias)));
  return match?.value || '';
}
function propertyNameMatches(property, aliases) {
  const name = normalizePropertyName(property.name);
  return aliases.some((alias) => name.includes(alias));
}
function splitIdentifierValues(value) {
  return String(value || '').split(/[|,\r\n]+/).map((part) => part.trim()).filter(Boolean);
}
function extractModelYear(value) {
  const match = String(value || '').match(/\b((?:19|20)\d{2})\b/);
  return match?.[1] || '';
}
const colorWords = new Set(['NEGRO', 'NEGRA', 'GRIS', 'AZUL', 'ROJO', 'ROJA', 'VERDE', 'DORADO', 'DORADA', 'BLANCO', 'BLANCA', 'PLATA', 'AMARILLO', 'AMARILLA', 'NARANJA', 'BEIGE', 'CAFE', 'MARRON', 'MORADO', 'MORADA', 'VIOLETA', 'ROSADO', 'ROSADA', 'BRONCE']);
const colorQualifiers = new Set(['MATE', 'NEBULOSA', 'GRAFITO', 'CARBONO', 'ACERO', 'METALIZADO', 'METALIZADA', 'PERLADO', 'PERLADA', 'ASPAS']);
function inferColorFromDescription(description) {
  const tokens = String(description || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim().split(/\s+/).filter(Boolean);
  const colors = [];
  tokens.forEach((token, index) => {
    if (!colorWords.has(token)) return;
    const qualifiers = [];
    let cursor = index + 1;
    while (cursor < tokens.length && colorQualifiers.has(tokens[cursor])) { qualifiers.push(tokens[cursor]); cursor += 1; }
    const decorative = tokens[index - 1] === 'CALCOMANIA';
    const phrase = `${decorative ? 'CALCOMANÍA ' : ''}${token}${qualifiers.length ? ` ${qualifiers.join(' ')}` : ''}`;
    if (!colors.includes(phrase)) colors.push(phrase);
  });
  return colors.join(' / ');
}
const vinYearCodes = 'ABCDEFGHJKLMNPRSTVWXY123456789';
function inferModelYearFromVin(value, invoiceYear) {
  const vin = String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const referenceYear = Number(invoiceYear);
  if (vin.length !== 17 || !Number.isInteger(referenceYear)) return '';
  const codeIndex = vinYearCodes.indexOf(vin[9]);
  if (codeIndex < 0) return '';
  const candidates = [];
  for (let year = 1980 + codeIndex; year <= referenceYear + 2; year += 30) candidates.push(year);
  const best = candidates.sort((left, right) => Math.abs(left - referenceYear) - Math.abs(right - referenceYear))[0];
  return best >= referenceYear - 1 && best <= referenceYear + 2 ? String(best) : '';
}
function extractMotoSerials(properties, itemNode) {
  const found = [];
  const add = (serial) => {
    const normalized = {
      serial: String(serial.serial || '').trim(), motor: String(serial.motor || '').trim(), chassis: String(serial.chassis || '').trim(),
      vin: String(serial.vin || '').trim(), color: String(serial.color || '').trim(), technical: String(serial.technical || '').trim(),
      model: String(serial.model || '').trim(), raw: String(serial.raw || '').trim(),
    };
    if (!normalized.serial && !normalized.motor && !normalized.chassis && !normalized.vin) return;
    const key = [normalized.serial, normalized.motor, normalized.chassis, normalized.vin].map((value) => value.toUpperCase()).join('|');
    if (!found.some((item) => item.key === key)) found.push({ key, ...normalized });
  };

  properties.filter((property) => normalizePropertyName(property.name) === 'informacionmoto' && property.value).forEach((property) => {
    const [color = '', chassis = '', motor = '', technical = '', model = ''] = property.value.split(';').map((value) => value.trim());
    add({ color, chassis, motor, technical, model, raw: property.value });
  });

  const combined = properties.filter((property) => {
    const name = normalizePropertyName(property.name);
    return property.value && (name.includes('motor') || name.includes('engine')) && (name.includes('chasis') || name.includes('chassis') || name.includes('vin') || name.includes('bastidor'));
  });
  combined.forEach((property) => {
    const parts = property.value.split(/\s*\/\s*/).map((value) => value.trim()).filter(Boolean);
    if (parts.length >= 2) add({ chassis: parts[0], motor: parts.slice(1).join('/'), raw: property.value });
  });

  const standalone = properties.filter((property) => !combined.includes(property) && normalizePropertyName(property.name) !== 'informacionmoto');
  const valuesFor = (aliases) => standalone.filter((property) => property.value && propertyNameMatches(property, aliases)).flatMap((property) => splitIdentifierValues(property.value));
  const chassisValues = valuesFor(['chasis', 'chassis', 'bastidor']);
  const vinValues = valuesFor(['vin']);
  const motorValues = valuesFor(['motor', 'engine']);
  const serialValues = valuesFor(['numeroserie', 'serialnumber', 'serial']);
  const colorValues = valuesFor(['color', 'colour']);
  const modelValues = valuesFor(['anomodelo', 'modelyear', 'yearmodel', 'modelo', 'model']);
  const count = Math.max(chassisValues.length, vinValues.length, motorValues.length, serialValues.length, colorValues.length, modelValues.length);
  for (let index = 0; index < count; index += 1) {
    const vin = vinValues[index] || '';
    add({ serial: serialValues[index], motor: motorValues[index], chassis: chassisValues[index], vin, color: colorValues[index], model: modelValues[index], raw: standalone.map((property) => `${property.name}=${property.value}`).join('; ') });
  }

  descendantsByLocal(itemNode, 'ItemInstance').forEach((instance) => {
    const serial = firstDescendantText(instance, 'SerialID', 'LotNumberID');
    if (serial) add({ serial, raw: serial });
  });
  return found.map(({ key, ...serial }, index) => ({ number: index + 1, ...serial }));
}
function joinUnique(values) { return [...new Set(values.filter(Boolean))].join(' | '); }
function identifierInDescription(description, labelPattern) {
  const match = String(description || '').match(new RegExp(`\\b(?:${labelPattern})\\s*(?:n(?:o|umero)?\\.?\\s*)?[:#-]?\\s*([A-Z0-9][A-Z0-9.-]{3,})`, 'i'));
  return match?.[1] || '';
}

const retentionTaxCodes = new Set(['05', '06', '07']);
const taxNamesByCode = { '01': 'IVA', '03': 'ICA', '04': 'INC', '05': 'ReteIVA', '06': 'Retención en la fuente', '07': 'ReteICA' };
function isRetentionTax(code, name, totalName = '') {
  return totalName === 'WithholdingTaxTotal' || retentionTaxCodes.has(String(code || '').trim()) || /rete|retenci|withhold/i.test(String(name || ''));
}
function extractTaxComponents(parent, totalName) {
  return childrenByLocal(parent, totalName).flatMap((total) => {
    const subtotals = childrenByLocal(total, 'TaxSubtotal');
    if (!subtotals.length) {
      const amount = numeric(textAt(total, ['TaxAmount']));
      return amount === null ? [] : [{ code: '', name: totalName === 'WithholdingTaxTotal' ? 'Retención' : 'Impuesto', rate: null, taxableAmount: null, amount, retention: totalName === 'WithholdingTaxTotal' }];
    }
    return subtotals.map((subtotal) => {
      const category = childByLocal(subtotal, 'TaxCategory') || subtotal;
      const scheme = childByLocal(category, 'TaxScheme') || category;
      const code = textAt(scheme, ['ID']);
      const rawName = textAt(scheme, ['Name']);
      const name = rawName || taxNamesByCode[code] || (totalName === 'WithholdingTaxTotal' ? 'Retención' : 'Impuesto');
      return {
        code, name, rate: numeric(textAt(category, ['Percent']) || firstDescendantText(subtotal, 'Percent')),
        taxableAmount: numeric(textAt(subtotal, ['TaxableAmount'])), amount: numeric(textAt(subtotal, ['TaxAmount'])),
        retention: isRetentionTax(code, name, totalName),
      };
    });
  });
}
function extractCustomRetentions(root) {
  const values = new Map();
  let generalTotal = null;
  descendantsByLocal(root, 'CustomField').forEach((field) => {
    const name = field.getAttribute?.('Name') || firstDescendantText(field, 'Name');
    const value = numeric(field.getAttribute?.('Value') || firstDescendantText(field, 'Value'));
    if (value === null || value <= 0) return;
    const normalized = normalizePropertyName(name);
    if (normalized.includes('totalretenciones')) { generalTotal = Math.max(generalTotal || 0, value); return; }
    const definition = normalized.includes('retefuente') ? ['06', 'Retención en la fuente']
      : normalized.includes('reteiva') ? ['05', 'ReteIVA']
        : normalized.includes('reteica') ? ['07', 'ReteICA'] : null;
    if (!definition) return;
    const [code, label] = definition;
    values.set(code, { code, name: label, rate: null, taxableAmount: null, amount: Math.max(values.get(code)?.amount || 0, value), retention: true });
  });
  const result = [...values.values()];
  if (!result.length && generalTotal) result.push({ code: '', name: 'Retenciones', rate: null, taxableAmount: null, amount: generalTotal, retention: true });
  return result;
}

function inferLineClassification(description) {
  const normalized = String(description || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (/flete|transporte de mercanc|acarreo|seguro de transporte|nacionalizacion|arancel/.test(normalized)) return 'acquisition-cost';
  if (/servicio|honorario|asesoria|consultoria|mantenimiento|reparacion|vigilancia|arrendamiento|comision|publicidad/.test(normalized)) return 'service';
  return 'inventory';
}

const classificationLabels = {
  inventory: 'Mercancía inventariable',
  service: 'Servicio o gasto',
  'acquisition-cost': 'Costo adicional de compra',
};

function findEmbeddedBusinessDocument(documentNode) {
  const acceptedRoots = new Set(['Invoice', 'CreditNote', 'DebitNote']);
  for (const element of Array.from(documentNode.getElementsByTagName('*'))) {
    for (const child of Array.from(element.childNodes || [])) {
      if (child.nodeType !== Node.CDATA_SECTION_NODE && child.nodeType !== Node.TEXT_NODE) continue;
      const candidate = child.nodeValue.trim().replace(/^\uFEFF/, '');
      if (!/<(?:[\w.-]+:)?(?:Invoice|CreditNote|DebitNote)\b/.test(candidate)) continue;
      try {
        const embedded = parseXml(candidate);
        if (acceptedRoots.has(localName(embedded.documentElement))) return embedded;
      } catch { /* El texto no era un XML UBL completo. */ }
    }
  }
  return null;
}

function extractParty(root, sectionName) {
  const section = childByLocal(root, sectionName);
  if (!section) return { name: '', identification: '', city: '', address: '', phone: '', email: '' };
  return {
    name: firstDescendantText(section, 'RegistrationName', 'Name'),
    identification: firstDescendantText(section, 'CompanyID'),
    city: firstDescendantText(section, 'CityName'),
    address: firstDescendantText(section, 'Line'),
    phone: firstDescendantText(section, 'Telephone'),
    email: firstDescendantText(section, 'ElectronicMail'),
  };
}

function extractInvoiceData(documentNode) {
  const root = documentNode.documentElement;
  const documentType = localName(root);
  if (!['Invoice', 'CreditNote', 'DebitNote'].includes(documentType)) return null;
  const issueDate = textAt(root, ['IssueDate']);
  const invoiceYear = Number(issueDate.slice(0, 4));
  const lineName = documentType === 'CreditNote' ? 'CreditNoteLine' : documentType === 'DebitNote' ? 'DebitNoteLine' : 'InvoiceLine';
  const quantityName = documentType === 'CreditNote' ? 'CreditedQuantity' : documentType === 'DebitNote' ? 'DebitedQuantity' : 'InvoicedQuantity';
  const monetary = childByLocal(root, 'LegalMonetaryTotal') || childByLocal(root, 'RequestedMonetaryTotal');
  const items = childrenByLocal(root, lineName).map((line) => {
    const quantityNode = childByLocal(line, quantityName);
    const itemNode = childByLocal(line, 'Item');
    const priceNode = childByLocal(line, 'Price');
    const lineAdjustments = childrenByLocal(line, 'AllowanceCharge');
    const lineDiscounts = lineAdjustments.filter((adjustment) => /^false$/i.test(textAt(adjustment, ['ChargeIndicator'])));
    const lineSurcharges = lineAdjustments.filter((adjustment) => /^true$/i.test(textAt(adjustment, ['ChargeIndicator'])));
    const description = firstDescendantText(itemNode, 'Description', 'Name');
    const code = firstDescendantText(nodeAt(itemNode, ['SellersItemIdentification']) || nodeAt(itemNode, ['StandardItemIdentification']) || itemNode, 'ID');
    const properties = extractItemProperties(itemNode);
    let serials = extractMotoSerials(properties, itemNode);
    const motor = joinUnique(serials.map((serial) => serial.motor)) || propertyValue(properties.filter((property) => normalizePropertyName(property.name) !== 'informacionmoto'), ['motor', 'engine']) || identifierInDescription(description, 'motor|engine');
    const chassis = joinUnique(serials.map((serial) => serial.chassis || serial.vin)) || propertyValue(properties.filter((property) => normalizePropertyName(property.name) !== 'informacionmoto'), ['chasis', 'chassis', 'vin', 'bastidor'])
      || firstDescendantText(nodeAt(itemNode, ['ItemInstance']), 'SerialID')
      || identifierInDescription(description, 'chasis|chassis|vin|bastidor');
    if (!serials.length && (motor || chassis)) serials = [{ number: 1, serial: '', motor, chassis, vin: '', color: '', technical: '', model: '', raw: description }];
    const inferredColor = inferColorFromDescription(description);
    const descriptionYear = extractModelYear(description);
    serials = serials.map((serial) => ({
      ...serial,
      color: serial.color || inferredColor,
      model: extractModelYear(serial.model) || descriptionYear || inferModelYearFromVin(serial.vin || serial.chassis, invoiceYear),
    }));
    const lineTaxComponents = [...extractTaxComponents(line, 'TaxTotal'), ...extractTaxComponents(line, 'WithholdingTaxTotal')];
    const quantity = numeric(quantityNode ? directText(quantityNode) : '');
    const unitPrice = numeric(textAt(priceNode, ['PriceAmount']));
    const lineTotal = numeric(textAt(line, ['LineExtensionAmount']));
    const discount = lineDiscounts.reduce((sum, adjustment) => sum + (numeric(textAt(adjustment, ['Amount'])) || 0), 0);
    const surcharge = lineSurcharges.reduce((sum, adjustment) => sum + (numeric(textAt(adjustment, ['Amount'])) || 0), 0);
    const rawDiscountRate = numeric(textAt(lineDiscounts[0], ['MultiplierFactorNumeric']));
    const discountRate = rawDiscountRate === null ? (discount ? numeric((discount / Math.max((quantity || 0) * (unitPrice || 0), 1) * 100).toFixed(4)) : 0) : (Math.abs(rawDiscountRate) <= 1 ? rawDiscountRate * 100 : rawDiscountRate);
    const grossTotal = quantity !== null && unitPrice !== null ? quantity * unitPrice : (lineTotal === null ? null : lineTotal + discount - surcharge);
    return {
      line: textAt(line, ['ID']), code, description, motor, chassis, serials, properties,
      classification: inferLineClassification(description),
      quantity,
      unit: quantityNode?.getAttribute('unitCode') || '',
      unitPrice, grossTotal, discount, discountRate, surcharge, lineTotal,
      tax: lineTaxComponents.filter((component) => !component.retention).reduce((sum, component) => sum + (component.amount || 0), 0),
      retention: lineTaxComponents.filter((component) => component.retention).reduce((sum, component) => sum + (component.amount || 0), 0),
    };
  });
  const rootTaxComponents = [...extractTaxComponents(root, 'TaxTotal'), ...extractTaxComponents(root, 'WithholdingTaxTotal')];
  const taxes = rootTaxComponents.filter((component) => !component.retention);
  const standardRetentions = rootTaxComponents.filter((component) => component.retention && (component.amount || 0) > 0);
  const retentions = standardRetentions.length ? standardRetentions : extractCustomRetentions(root);
  const retentionTotal = retentions.reduce((sum, retention) => sum + (retention.amount || 0), 0);
  const explicitLineRetention = items.reduce((sum, item) => sum + (item.retention || 0), 0);
  const pendingRetention = Math.max(retentionTotal - explicitLineRetention, 0);
  if (pendingRetention > 0 && items.length) {
    const bases = items.map((item) => Math.max(item.lineTotal || item.grossTotal || 0, 0));
    const totalBase = bases.reduce((sum, base) => sum + base, 0);
    let allocated = 0;
    items.forEach((item, index) => {
      const share = index === items.length - 1 ? pendingRetention - allocated : (totalBase > 0 ? pendingRetention * bases[index] / totalBase : pendingRetention / items.length);
      item.retention = (item.retention || 0) + share;
      allocated += share;
    });
  }
  const charges = childrenByLocal(root, 'AllowanceCharge').filter((charge) => /^true$/i.test(textAt(charge, ['ChargeIndicator']))).map((charge) => {
    const reason = textAt(charge, ['AllowanceChargeReason']) || textAt(charge, ['AllowanceChargeReasonCode']) || 'Cargo';
    return { reason, amount: numeric(textAt(charge, ['Amount'])), baseAmount: numeric(textAt(charge, ['BaseAmount'])), isFreight: /flete|freight|transporte|env[ií]o/i.test(reason) };
  });
  items.filter((item) => /flete|freight|transporte|env[ií]o/i.test(item.description)).forEach((item) => charges.push({ reason: item.description, amount: item.lineTotal, baseAmount: item.lineTotal, isFreight: true }));
  const paymentMeans = childByLocal(root, 'PaymentMeans');
  const informedDueDate = textAt(root, ['DueDate']) || firstDescendantText(paymentMeans, 'PaymentDueDate');
  const paymentMeansCode = firstDescendantText(paymentMeans, 'ID');
  const informedCreditDays = daysBetweenDates(issueDate, informedDueDate);
  const paymentCondition = paymentMeansCode === '2' || informedCreditDays > 0 ? 'CREDITO' : 'CONTADO';
  const creditDays = paymentCondition === 'CREDITO' ? (informedCreditDays || 30) : 0;
  const dueDate = paymentCondition === 'CREDITO' ? (informedCreditDays > 0 ? informedDueDate : datePlusDays(issueDate, creditDays)) : issueDate;
  const chargeTotal = numeric(textAt(monetary, ['ChargeTotalAmount']));
  const freight = charges.filter((charge) => charge.isFreight).reduce((sum, charge) => sum + (charge.amount || 0), 0);
  const otherCharges = chargeTotal === null
    ? charges.filter((charge) => !charge.isFreight).reduce((sum, charge) => sum + (charge.amount || 0), 0)
    : Math.max(chargeTotal - freight, 0);
  const netSubtotal = numeric(textAt(monetary, ['LineExtensionAmount']));
  const lineDiscountTotal = items.reduce((sum, item) => sum + (item.discount || 0), 0);
  const allowanceTotal = numeric(textAt(monetary, ['AllowanceTotalAmount'])) ?? lineDiscountTotal;
  const grossSubtotal = items.reduce((sum, item) => sum + (item.grossTotal || 0), 0) || (netSubtotal === null ? null : netSubtotal + allowanceTotal);
  return {
    documentType,
    number: textAt(root, ['ID']),
    cufeCude: textAt(root, ['UUID']),
    issueDate,
    dueDate,
    paymentCondition,
    creditDays,
    autoCreateItems: true,
    currency: textAt(root, ['DocumentCurrencyCode']) || 'COP',
    supplier: extractParty(root, 'AccountingSupplierParty'),
    customer: extractParty(root, 'AccountingCustomerParty'),
    totals: {
      cost: netSubtotal,
      grossSubtotal,
      taxExclusive: numeric(textAt(monetary, ['TaxExclusiveAmount'])),
      taxInclusive: numeric(textAt(monetary, ['TaxInclusiveAmount'])),
      allowances: allowanceTotal,
      charges: chargeTotal,
      otherCharges,
      payable: numeric(textAt(monetary, ['PayableAmount'])),
      freight,
      retentions: retentionTotal,
    },
    taxes, retentions, charges, items,
  };
}
function inferType(value) {
  if (value === '') return 'vacío';
  if (/^(true|false)$/i.test(value)) return 'booleano';
  if (/^-?\d+(?:[.,]\d+)?$/.test(value)) return 'número';
  if (/^\d{4}-\d{2}-\d{2}(?:T.*)?$/.test(value)) return 'fecha';
  return 'texto';
}

function elementToJson(element) {
  const result = {};
  for (const attribute of element.attributes) result[`@${attribute.name}`] = attribute.value;
  const children = elementChildren(element);
  const text = directText(element);
  if (!children.length) return Object.keys(result).length ? { ...result, ...(text ? { '#text': text } : {}) } : text;
  if (text) result['#text'] = text;
  for (const child of children) {
    const key = child.nodeName;
    const value = elementToJson(child);
    if (Object.prototype.hasOwnProperty.call(result, key)) result[key] = Array.isArray(result[key]) ? [...result[key], value] : [result[key], value];
    else result[key] = value;
  }
  return result;
}

function markDescendants(element, set) {
  set.add(element);
  elementChildren(element).forEach((child) => markDescendants(child, set));
}
function flattenRecord(element) {
  const record = {};
  function walk(node, prefix) {
    for (const attr of node.attributes) record[prefix ? `${prefix}.@${attr.name}` : `@${attr.name}`] = attr.value;
    const text = directText(node);
    if (text) record[prefix || '#text'] = text;
    const counts = new Map();
    elementChildren(node).forEach((child) => counts.set(child.nodeName, (counts.get(child.nodeName) || 0) + 1));
    const indexes = new Map();
    for (const child of elementChildren(node)) {
      const current = (indexes.get(child.nodeName) || 0) + 1;
      indexes.set(child.nodeName, current);
      const label = counts.get(child.nodeName) > 1 ? `${child.nodeName}[${current}]` : child.nodeName;
      walk(child, prefix ? `${prefix}.${label}` : label);
    }
  }
  walk(element, '');
  return record;
}
function findDetailGroups(root) {
  const groups = [];
  const repeatedElements = new Set();
  function visit(parent, parentPath) {
    const grouped = new Map();
    for (const child of elementChildren(parent)) {
      if (!grouped.has(child.nodeName)) grouped.set(child.nodeName, []);
      grouped.get(child.nodeName).push(child);
    }
    for (const [name, nodes] of grouped) {
      const path = `${parentPath}/${name}`;
      if (nodes.length > 1) {
        nodes.forEach((node) => markDescendants(node, repeatedElements));
        groups.push({ path, name, nodes, rows: nodes.map(flattenRecord) });
      }
      nodes.forEach((node) => visit(node, path));
    }
  }
  visit(root, `/${root.nodeName}`);
  return { groups, repeatedElements };
}
function collectFields(element, path, fields, repeatedElements) {
  for (const attribute of element.attributes) fields.push({ path: `${path}/@${attribute.name}`, value: attribute.value, type: 'atributo', repeated: repeatedElements.has(element) });
  const text = directText(element);
  if (text) fields.push({ path, value: text, type: inferType(text), repeated: repeatedElements.has(element) });
  const counts = new Map();
  elementChildren(element).forEach((child) => counts.set(child.nodeName, (counts.get(child.nodeName) || 0) + 1));
  const indexes = new Map();
  for (const child of elementChildren(element)) {
    const index = (indexes.get(child.nodeName) || 0) + 1;
    indexes.set(child.nodeName, index);
    collectFields(child, `${path}/${child.nodeName}${counts.get(child.nodeName) > 1 ? `[${index}]` : ''}`, fields, repeatedElements);
  }
}

function parseXml(source) {
  const doc = new DOMParser().parseFromString(source, 'application/xml');
  const error = doc.querySelector('parsererror');
  if (error) throw new Error(error.textContent.replace(/\s+/g, ' ').trim());
  if (!doc.documentElement) throw new Error('El documento no tiene un elemento raíz.');
  return doc;
}
function analyze() {
  hideError();
  const source = elements.xmlInput.value.trim();
  if (!source) return showError('Carga un archivo o pega contenido XML para comenzar.');
  try {
    const containerDocument = parseXml(source);
    const embeddedDocument = findEmbeddedBusinessDocument(containerDocument);
    const doc = embeddedDocument || containerDocument;
    const root = doc.documentElement;
    const { groups, repeatedElements } = findDetailGroups(root);
    const fields = [];
    collectFields(root, `/${root.nodeName}`, fields, repeatedElements);
    const primaryJson = { [root.nodeName]: elementToJson(root) };
    Object.assign(state, {
      document: doc,
      containerDocument: embeddedDocument ? containerDocument : null,
      invoice: extractInvoiceData(doc),
      json: embeddedDocument ? { documentoComercial: primaryJson, contenedor: { tipo: containerDocument.documentElement.nodeName } } : primaryJson,
      fields,
      headers: fields.filter((field) => !field.repeated),
      details: groups,
      purchaseWorkflow: null,
    });
    renderResults();
  } catch (error) { showError(`No se pudo interpretar el XML. ${error.message}`); }
}

function renderResults() {
  const root = state.document.documentElement;
  elements.documentTitle.textContent = state.fileName || localName(root);
  renderInvoice();
  document.body.classList.add('has-results');
  elements.results.hidden = false;
  elements.results.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
function formatCurrency(value, currency = 'COP') {
  if (value === null || value === undefined) return 'No informado';
  const validCurrency = /^[A-Z]{3}$/.test(currency) ? currency : 'COP';
  return new Intl.NumberFormat('es-CO', { style: 'currency', currency: validCurrency, maximumFractionDigits: 2 }).format(value);
}
function formatPercentage(value) {
  if (value === null || value === undefined) return '';
  return `${new Intl.NumberFormat('es-CO', { maximumFractionDigits: 2 }).format(value)} %`;
}
function buildDataTable(headers, rows) {
  if (!rows.length) return emptyMessage('No se encontraron registros en esta sección.');
  const table = document.createElement('table');
  const head = table.createTHead().insertRow();
  headers.forEach((header) => { const th = document.createElement('th'); th.textContent = header; head.append(th); });
  const body = table.createTBody();
  rows.forEach((values) => {
    const row = body.insertRow();
    values.forEach((value) => { const cell = row.insertCell(); cell.textContent = value ?? ''; });
  });
  return table;
}
function invoiceCard(title, subtitle, content, extraClass = '') {
  const card = document.createElement('article'); card.className = `result-card ${extraClass}`.trim();
  const heading = document.createElement('div'); heading.className = 'card-heading compact-heading';
  const text = document.createElement('div');
  const h3 = document.createElement('h3'); h3.textContent = title;
  const paragraph = document.createElement('p'); paragraph.textContent = subtitle;
  text.append(h3, paragraph); heading.append(text); card.append(heading);
  const wrap = document.createElement('div'); wrap.className = 'table-wrap'; wrap.append(content); card.append(wrap);
  return card;
}

function invoiceOperationalSummary(invoice) {
  const summary = document.createElement('section');
  summary.className = 'operational-summary';
  const heading = document.createElement('div');
  heading.className = 'operational-heading';
  const headingText = document.createElement('div');
  const title = document.createElement('h3');
  title.textContent = 'Efectos propuestos en el ERP';
  const copy = document.createElement('p');
  copy.textContent = 'La clasificación es editable y determina qué proceso se generará al confirmar.';
  headingText.append(title, copy);
  const badge = document.createElement('span');
  badge.className = 'review-badge';
  badge.textContent = 'REQUIERE REVISIÓN';
  heading.append(headingText, badge);
  const cards = document.createElement('div');
  cards.className = 'effect-grid';
  const definitions = [
    ['inventory', 'Entrada de mercancía', 'Afecta existencias y Kardex'],
    ['service', 'Causación de servicios', 'Afecta gasto y cuentas por pagar'],
    ['acquisition-cost', 'Costos adicionales', 'Se distribuirán al inventario'],
  ];
  definitions.forEach(([type, label, detail]) => {
    const matching = invoice.items.filter((item) => item.classification === type);
    const total = matching.reduce((sum, item) => sum + (item.lineTotal || 0), 0);
    const card = document.createElement('div');
    card.className = `effect-card ${type}`;
    const count = document.createElement('strong');
    count.textContent = String(matching.length);
    const text = document.createElement('div');
    const name = document.createElement('b');
    name.textContent = label;
    const small = document.createElement('small');
    small.textContent = `${detail} · ${formatCurrency(total, invoice.currency)}`;
    text.append(name, small);
    card.append(count, text);
    cards.append(card);
  });
  summary.append(heading, cards);
  return summary;
}

function ensureInvoiceSupplier(context,invoice) {
  const identification=invoice.supplier.identification||`SIN-ID-${normalizePropertyName(invoice.supplier.name).slice(0,20)}`;
  let supplier=context.data.suppliers.find(x=>x.identification===identification);
  if(!supplier){ supplier={id:masterId('sup'),identificationType:'NIT',identification,verificationDigit:'',name:invoice.supplier.name||'Proveedor desde XML',active:true}; context.data.suppliers.push(supplier); }
  return supplier;
}

function externalProductCode(item) {
  const explicit=String(item.code||'').trim();
  if(explicit) return explicit;
  const normalized=normalizePropertyName(item.description||'ARTICULO SIN DESCRIPCION');
  let hash=2166136261;
  for(let index=0;index<normalized.length;index++){ hash^=normalized.charCodeAt(index); hash=Math.imul(hash,16777619); }
  return `DESC-${(hash>>>0).toString(16).padStart(8,'0').toUpperCase()}`;
}

function mappingForLine(data,invoice,item) {
  const supplier=data.suppliers.find(x=>x.identification===invoice.supplier.identification);
  if(!supplier) return null;
  const externalCode=externalProductCode(item).toUpperCase();
  return data.mappings.find(x=>x.active&&x.supplierId===supplier.id&&x.externalCode.toUpperCase()===externalCode)||null;
}

function compatibleArticles(data,classification) {
  if(classification==='inventory') return data.articles.filter(x=>x.active&&x.inventory);
  if(classification==='service') return data.articles.filter(x=>x.active&&(x.type==='SERVICIO'||x.type==='CONCEPTO'));
  return data.articles.filter(x=>x.active&&(x.type==='CONCEPTO'||x.type==='SERVICIO'));
}

function buildHomologationPanel(invoice) {
  const context=getCompanyMasterData(); const data=context.data; const resolved=invoice.items.map(item=>mappingForLine(data,invoice,item)); const completed=resolved.filter(Boolean).length;
  const panel=document.createElement('section'); panel.className='homologation-panel';
  const heading=document.createElement('div'); heading.className='homologation-heading'; const copy=document.createElement('div'); const title=document.createElement('h3'); title.textContent='Homologación con el catálogo interno';
  const description=document.createElement('p'); description.textContent='Cada código del proveedor debe quedar relacionado antes de preparar la entrada.'; copy.append(title,description);
  const progress=document.createElement('span'); progress.className=`homologation-progress${completed===invoice.items.length?' complete':''}`; progress.textContent=`${completed} DE ${invoice.items.length} HOMOLOGADAS`; heading.append(copy,progress);
  const wrap=document.createElement('div'); wrap.className='homologation-table'; const table=document.createElement('table'); const head=table.createTHead().insertRow();
  ['Línea','Código proveedor','Descripción XML','Clasificación','Artículo interno','Estado'].forEach(text=>{const th=document.createElement('th');th.textContent=text;head.append(th);});
  const body=table.createTBody(); invoice.items.forEach((item,index)=>{
    const row=body.insertRow(); [item.line,item.code||'Sin código',item.description,classificationLabels[item.classification]].forEach(value=>{const cell=row.insertCell();cell.textContent=value||'';});
    const selectCell=row.insertCell(); const select=document.createElement('select'); const empty=document.createElement('option'); empty.value=''; empty.textContent='Seleccionar artículo interno…'; select.append(empty);
    const candidates=compatibleArticles(data,item.classification); const current=resolved[index];
    candidates.forEach(article=>{const option=document.createElement('option');option.value=article.id;option.textContent=`${article.code} · ${article.description}`;option.selected=current?.articleId===article.id;select.append(option);});
    if(current&&!candidates.some(x=>x.id===current.articleId)){const article=findById(data.articles,current.articleId);if(article){const option=document.createElement('option');option.value=article.id;option.textContent=`${article.code} · ${article.description}`;option.selected=true;select.append(option);}}
    select.addEventListener('change',async()=>{
      if(context.api){
        if(!select.value){ renderInvoice(); return; }
        try {
          const supplier=await ensureApiSupplier(invoice); const article=findById(data.articles,select.value);
          await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/master-data/item-mappings`,{method:'POST',body:JSON.stringify({terceroId:supplier.id,codigoExterno:externalProductCode(item),descripcionExterna:item.description,articuloId:article.id,unidadMedidaId:article.unitId,factorAUnidadBase:1})});
          await loadApiCompanyContext();
        } catch(error) { showError(`No fue posible guardar la homologación. ${error.message}`); renderInvoice(); }
        return;
      }
      const externalCode=externalProductCode(item); const supplier=ensureInvoiceSupplier(context,invoice); const existing=context.data.mappings.find(x=>x.supplierId===supplier.id&&x.externalCode.toUpperCase()===externalCode.toUpperCase());
      if(!select.value){ if(existing) existing.active=false; }
      else { const article=findById(context.data.articles,select.value); const record={id:existing?.id||masterId('map'),supplierId:supplier.id,externalCode,externalDescription:item.description,articleId:article.id,unitId:article.unitId,factor:1,active:true}; existing?Object.assign(existing,record):context.data.mappings.push(record); }
      saveCompanyMasterData(context); renderInvoice();
    }); selectCell.append(select);
    const statusCell=row.insertCell(); const status=document.createElement('span'); status.className=`mapping-status ${current?'':'pending'}`; status.textContent=current?'Homologada':'Pendiente'; statusCell.append(status);
  });
  wrap.append(table); panel.append(heading,wrap); return panel;
}

function buildInvoiceClassificationTable(invoice) {
  if (!invoice.items.length) return emptyMessage('No se encontraron líneas en la factura.');
  const table = document.createElement('table');
  table.className = 'classification-table';
  const headers = ['Clasificación', 'Línea', 'Código', 'Descripción', 'Cantidad', 'Unidad', 'Precio unitario', 'Subtotal bruto', 'Descuento', 'Descuento %', 'Impuesto', 'Retención', 'Total neto'];
  const head = table.createTHead().insertRow();
  headers.forEach((header) => { const th = document.createElement('th'); th.textContent = header; head.append(th); });
  const body = table.createTBody();
  invoice.items.forEach((item, index) => {
    const row = body.insertRow();
    const classificationCell = row.insertCell();
    const select = document.createElement('select');
    select.className = `classification-select ${item.classification}`;
    Object.entries(classificationLabels).forEach(([value, label]) => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = label;
      option.selected = item.classification === value;
      select.append(option);
    });
    select.addEventListener('change', () => {
      state.invoice.items[index].classification = select.value;
      select.className = `classification-select ${select.value}`;
      renderInvoice();
    });
    classificationCell.append(select);
    [item.line, item.code, item.description, item.quantity, item.unit, formatCurrency(item.unitPrice, invoice.currency), formatCurrency(item.grossTotal, invoice.currency), formatCurrency(item.discount, invoice.currency), formatPercentage(item.discountRate), formatCurrency(item.tax, invoice.currency), formatCurrency(item.retention, invoice.currency), formatCurrency(item.lineTotal, invoice.currency)]
      .forEach((value) => { const cell = row.insertCell(); cell.textContent = value ?? ''; });
  });
  return table;
}

function mappedLine(invoice,item) { return mappingForLine(getCompanyMasterData().data,invoice,item); }
function documentTypeForApi(value) { return ({Invoice:'FACTURA',CreditNote:'NOTA_CREDITO',DebitNote:'NOTA_DEBITO'})[value]||'FACTURA'; }

function buildSupplierDocumentPayload(invoice) {
  const classification={inventory:'INVENTARIO',service:'SERVICIO_GASTO','acquisition-cost':'COSTO_ADQUISICION'};
  const lineas=invoice.items.map((item,index)=>{
    const mapping=mappedLine(invoice,item); const serials=item.serials.length?item.serials:(item.motor||item.chassis?[{number:1,motor:item.motor,chassis:item.chassis,raw:item.description}]:[]);
    return {
      numeroLinea:Number(item.line)||index+1,articuloId:mapping?.articleId||null,codigoExterno:externalProductCode(item),descripcion:item.description||`Línea ${index+1}`,
      clasificacion:classification[item.classification],cantidad:item.quantity||1,unidadMedidaId:mapping?.unitId||findById(getCompanyMasterData().data.articles,mapping?.articleId)?.unitId||null,
      unidadCodigo:item.unit||'UND',manejaSerial:serials.length>0,
      factorAUnidadBase:mapping?.factor||1,precioUnitario:item.unitPrice||0,subtotalBruto:item.grossTotal??item.lineTotal??0,descuento:item.discount||0,
      impuesto:item.tax||0,cargo:item.surcharge||0,totalNeto:item.lineTotal??Math.max((item.grossTotal||0)-(item.discount||0)+(item.surcharge||0),0),
      retencion:item.retention||0,
      numeroLote:null,fechaVencimiento:null,
      seriales:serials.map((serial,serialIndex)=>({numeroUnidad:serial.number||serialIndex+1,serial:serial.serial||null,motor:serial.motor||null,chasis:serial.chassis||null,vin:serial.vin||null,color:serial.color||null,modelo:serial.model||null,informacionOriginal:serial.raw||null})),
    };
  });
  const taxTotal=invoice.taxes.reduce((sum,tax)=>sum+(tax.amount||0),0); const lineCharges=invoice.items.reduce((sum,item)=>sum+(item.surcharge||0),0);
  return { proveedorIdentificacion:invoice.supplier.identification,proveedorRazonSocial:invoice.supplier.name||'Proveedor desde XML',tipoDocumento:documentTypeForApi(invoice.documentType),numeroDocumento:invoice.number,
    fechaDocumento:invoice.issueDate,fechaVencimiento:invoice.dueDate||null,condicionPago:invoice.paymentCondition||'CONTADO',diasCredito:Number(invoice.creditDays)||0,crearArticulosFaltantes:invoice.autoCreateItems!==false,moneda:invoice.currency||'COP',cufeCude:invoice.cufeCude||null,fuente:'XML_DIAN',
    subtotalBruto:invoice.totals.grossSubtotal??invoice.totals.cost??0,descuentoTotal:invoice.totals.allowances||0,impuestoTotal:taxTotal,cargoTotal:invoice.totals.charges??lineCharges,
    totalPagar:invoice.totals.payable??0,xmlOriginal:elements.xmlInput.value.trim(),documentoGuid:null,lineas };
}

async function refreshPurchaseWorkflow(documentId,receiptId=null,saveResult=null) {
  const companyId=state.erpSession.company.id; const workflow=await apiRequest(`/api/v1/companies/${companyId}/supplier-documents/${documentId}`);
  const effectiveReceipt=receiptId||workflow.recepcionMercanciaId; let movements=[];
  if(effectiveReceipt) movements=await apiRequest(`/api/v1/companies/${companyId}/receipts/${effectiveReceipt}/movements`);
  const accrual=workflow.causacionServicioId?await apiRequest(`/api/v1/companies/${companyId}/service-accruals/${workflow.causacionServicioId}`):null;
  state.purchaseWorkflow={documentId,receiptId:effectiveReceipt,causacionId:workflow.causacionServicioId,workflow,movements,accrual,lastCreatedItems:saveResult?.articulosCreados??state.purchaseWorkflow?.lastCreatedItems??0}; renderInvoice();
}

async function prepareSupplierDocumentForReceipt(documentId,{hasInventory,hasServices,bodegaId,periodoInventarioId,fechaContable,numeroDocumento}) {
  if(!hasInventory&&!hasServices) return { recepcionMercanciaId:null, causacionServicioId:null };
  return apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents/${documentId}/prepare`,{
    method:'POST',
    body:JSON.stringify({
      bodegaId:hasInventory?Number(bodegaId):null,
      periodoInventarioId:hasInventory?Number(periodoInventarioId):null,
      fechaContable,
      numeroRecepcion:hasInventory?`ENT-${numeroDocumento}`.slice(0,50):null,
      numeroCausacion:hasServices?`CAU-${numeroDocumento}`.slice(0,50):null
    })
  });
}

function buildPurchaseWorkflowPanel(invoice) {
  const panel=document.createElement('section'); panel.className='purchase-workflow-panel';
  const heading=document.createElement('div'); heading.className='purchase-workflow-heading'; heading.innerHTML='<div><span>REGISTRO ERP</span><h3>Guardar la entrada de mercancía</h3><p>Puedes conservar un borrador o guardar y contabilizar todo en una sola acción.</p></div>';
  panel.append(heading);
  if(state.runtimeMode!=='api'||!state.erpSession?.api){ const notice=document.createElement('p'); notice.className='workflow-notice'; notice.textContent='Estás en modo local. Activa “API ERP”, cierra sesión e ingresa con un usuario de SQL Server para registrar esta factura.'; panel.append(notice); return panel; }
  if(!state.apiContext){ const notice=document.createElement('p'); notice.className='workflow-notice'; notice.textContent='Cargando bodegas, periodos y homologaciones de la empresa…'; panel.append(notice); return panel; }

  const inventoryLines=invoice.items.filter(x=>x.classification==='inventory'); const serviceLines=invoice.items.filter(x=>x.classification==='service');
  if(inventoryLines.length&&(!state.apiContext.warehouses.length||!state.apiContext.periods.length)){
    const setup=document.createElement('div');setup.className='workflow-notice';const missing=[!state.apiContext.warehouses.length?'una bodega activa':'',!state.apiContext.periods.length?'un periodo de inventario abierto':''].filter(Boolean).join(' y ');setup.append(document.createTextNode(`La empresa necesita ${missing} antes de recibir mercancía. `));
    if(state.erpSession.superAdmin){const button=document.createElement('button');button.type='button';button.className='button primary';button.textContent='Preparar empresa ahora';button.addEventListener('click',async()=>{try{button.disabled=true;button.textContent='Preparando…';await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/setup/operational-defaults`,{method:'POST',body:'{}'});await loadApiCompanyContext();renderInvoice();}catch(error){showError(`No fue posible preparar la empresa. ${error.message}`);button.disabled=false;button.textContent='Preparar empresa ahora';}});setup.append(button);}else setup.append(document.createTextNode('Solicita al superadministrador preparar los datos iniciales.'));
    panel.append(setup);return panel;
  }
  const pending=inventoryLines.filter(item=>!mappedLine(invoice,item)); const workflow=state.purchaseWorkflow?.workflow;
  const controls=document.createElement('div'); controls.className='workflow-controls';
  const warehouse=document.createElement('select'); warehouse.innerHTML='<option value="">Selecciona bodega…</option>'; state.apiContext.warehouses.forEach(x=>warehouse.add(new Option(`${x.codigo} · ${x.nombre}`,x.bodegaId)));
  const period=document.createElement('select'); period.innerHTML='<option value="">Selecciona periodo…</option>'; state.apiContext.periods.forEach(x=>period.add(new Option(`${x.codigo} · ${x.estado}`,x.periodoInventarioId)));
  if(state.apiContext.warehouses.length===1)warehouse.value=String(state.apiContext.warehouses[0].bodegaId);if(state.apiContext.periods.length===1)period.value=String(state.apiContext.periods[0].periodoInventarioId);
  const date=document.createElement('input'); date.type='date'; date.value=invoice.issueDate||new Date().toISOString().slice(0,10);
  const payment=document.createElement('select'); payment.innerHTML='<option value="CONTADO">Contado</option><option value="CREDITO">Crédito</option>'; payment.value=invoice.paymentCondition||'CONTADO';
  const creditDays=document.createElement('input'); creditDays.type='number'; creditDays.min='1'; creditDays.max='3650'; creditDays.value=String(invoice.creditDays||30); creditDays.title='Días de crédito';
  const autoCreateLabel=document.createElement('label'); autoCreateLabel.className='workflow-check'; const autoCreate=document.createElement('input'); autoCreate.type='checkbox'; autoCreate.checked=invoice.autoCreateItems!==false; const autoText=document.createElement('span'); autoText.textContent='Crear artículos faltantes'; autoCreateLabel.append(autoCreate,autoText);
  const controlField=(labelText,control)=>{const field=document.createElement('label');field.className='workflow-field';const label=document.createElement('span');label.textContent=labelText;field.append(label,control);return field;};
  const warehouseControl=controlField('Bodega',warehouse);const periodControl=controlField('Periodo de inventario',period);const dateControl=controlField('Fecha contable',date);const paymentControl=controlField('Condición de pago',payment);const creditControl=controlField('Días de crédito',creditDays);
  warehouseControl.hidden=inventoryLines.length===0; periodControl.hidden=inventoryLines.length===0;
  controls.append(warehouseControl,periodControl,dateControl,paymentControl,creditControl,autoCreateLabel); panel.append(controls);

  const actions=document.createElement('div'); actions.className='workflow-actions';
  const save=document.createElement('button'); save.type='button'; save.className='button secondary'; save.textContent=workflow?'Borrador guardado':inventoryLines.length?'Guardar borrador para recepción':'Guardar solo como borrador'; save.disabled=Boolean(workflow);
  const complete=document.createElement('button'); complete.type='button'; complete.className='button primary large'; complete.textContent=workflow?.recepcionEstado==='CONTABILIZADA'?'Entrada contabilizada':workflow?.recepcionMercanciaId?'Contabilizar entrada':inventoryLines.length?'Guardar y contabilizar entrada':'Guardar y preparar causación'; complete.disabled=workflow?.recepcionEstado==='CONTABILIZADA';
  const openTray=document.createElement('button');openTray.type='button';openTray.className='button secondary';openTray.textContent='Ver entradas guardadas';openTray.addEventListener('click',showSavedPurchases);
  actions.append(save,complete,openTray); panel.append(actions);
  const readiness=document.createElement('p'); panel.append(readiness);

  const updateCompleteState=()=>{ const missingWarehouse=inventoryLines.length>0&&!workflow?.recepcionMercanciaId&&(!warehouse.value||!period.value); complete.disabled=workflow?.recepcionEstado==='CONTABILIZADA'||(pending.length>0&&!autoCreate.checked)||missingWarehouse; save.disabled=Boolean(workflow)||(pending.length>0&&!autoCreate.checked)||missingWarehouse; };
  const updatePayment=()=>{ invoice.paymentCondition=payment.value; invoice.creditDays=payment.value==='CREDITO'?Math.max(Number(creditDays.value)||30,1):0; creditControl.hidden=payment.value!=='CREDITO'; invoice.dueDate=payment.value==='CREDITO'?datePlusDays(invoice.issueDate,invoice.creditDays):invoice.issueDate; };
  const updateAutoCreate=()=>{ invoice.autoCreateItems=autoCreate.checked; save.disabled=Boolean(workflow)||(pending.length>0&&!autoCreate.checked); readiness.className=`workflow-readiness${pending.length&&!autoCreate.checked?' pending':''}`; readiness.textContent=pending.length?(autoCreate.checked?`${pending.length} artículo(s) se crearán usando primero el código del proveedor y quedarán homologados automáticamente.`:`${pending.length} línea(s) requieren homologación manual antes de guardar.`):'Datos revisados: descuentos, impuestos, fletes y seriales se guardarán con el XML original.'; updateCompleteState(); };
  payment.addEventListener('change',updatePayment); creditDays.addEventListener('input',updatePayment); autoCreate.addEventListener('change',updateAutoCreate); updatePayment(); updateAutoCreate();
  warehouse.addEventListener('change',updateCompleteState); period.addEventListener('change',updateCompleteState);
  save.addEventListener('click',async()=>{ try { updatePayment(); save.disabled=true; save.textContent='Guardando para recepción…'; const result=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents`,{method:'POST',body:JSON.stringify(buildSupplierDocumentPayload(invoice))}); let receiptId=null;if(inventoryLines.length||serviceLines.length){const prepared=await prepareSupplierDocumentForReceipt(result.documentoProveedorId,{hasInventory:inventoryLines.length>0,hasServices:serviceLines.length>0,bodegaId:warehouse.value,periodoInventarioId:period.value,fechaContable:date.value,numeroDocumento:invoice.number});receiptId=prepared.recepcionMercanciaId;} await loadApiCompanyContext(); await refreshPurchaseWorkflow(result.documentoProveedorId,receiptId,result); showSuccess(receiptId?'Borrador preparado para recepción física. El auxiliar ya puede verlo.':'Borrador guardado. Puedes recuperarlo desde Entradas guardadas.'); } catch(error){ showError(`No fue posible guardar la entrada. ${error.message}`); save.disabled=false; save.textContent=inventoryLines.length?'Guardar borrador para recepción':'Guardar solo como borrador'; } });
  complete.addEventListener('click',async()=>{if(inventoryLines.length&&!window.confirm(`Se guardará y contabilizará la factura ${invoice.number}. Esto afectará existencias y Kardex. ¿Deseas continuar?`))return;try{updatePayment();complete.disabled=true;complete.textContent='Guardando y contabilizando…';let documentId=workflow?.documentoProveedorId;let current=workflow;let saveResult=null;if(!documentId){saveResult=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents`,{method:'POST',body:JSON.stringify(buildSupplierDocumentPayload(invoice))});documentId=saveResult.documentoProveedorId;current=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents/${documentId}`);}let receiptId=current.recepcionMercanciaId;if(!receiptId&&!current.causacionServicioId){const prepared=await prepareSupplierDocumentForReceipt(documentId,{hasInventory:inventoryLines.length>0,hasServices:serviceLines.length>0,bodegaId:warehouse.value,periodoInventarioId:period.value,fechaContable:date.value,numeroDocumento:invoice.number});receiptId=prepared.recepcionMercanciaId;}if(receiptId&&current.recepcionEstado!=='CONTABILIZADA')await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/receipts/${receiptId}/post`,{method:'POST',body:JSON.stringify({correlationId:crypto.randomUUID?crypto.randomUUID():null})});await loadApiCompanyContext();await refreshPurchaseWorkflow(documentId,receiptId,saveResult);showSuccess(receiptId?'Entrada guardada y contabilizada. Los seriales ya están disponibles en inventario.':'Documento guardado y procesos preparados.');}catch(error){showError(`No fue posible completar la entrada. El borrador queda recuperable en Entradas guardadas. ${error.message}`);complete.disabled=false;complete.textContent=inventoryLines.length?'Guardar y contabilizar entrada':'Guardar y preparar causación';}});

  if(workflow){ const status=document.createElement('div'); status.className='workflow-status'; status.innerHTML=`<span>Documento <strong>${workflow.estado}</strong></span><span>Pago <strong>${workflow.condicionPago==='CREDITO'?`Crédito · ${workflow.diasCredito} días`:'Contado'}</strong></span><span>Recepción <strong>${workflow.recepcionEstado||'No aplica'}</strong></span><span>Causación <strong>${workflow.causacionEstado||'No aplica'}</strong></span><span>Artículos nuevos <strong>${state.purchaseWorkflow?.lastCreatedItems||0}</strong></span><span>XML <strong>${workflow.xmlOriginalGuardado?'Guardado':'Sin original'}</strong></span>`; panel.append(status); }
  if(state.purchaseWorkflow?.movements?.length){ const wrap=document.createElement('div'); wrap.className='workflow-movements'; const h=document.createElement('h4'); h.textContent='Movimientos de Kardex generados'; wrap.append(h,buildDataTable(['Movimiento','Línea','Artículo','Cantidad','Costo unitario','Valor','Existencia posterior'],state.purchaseWorkflow.movements.map(x=>[x.movimientoInventarioId,x.numeroLinea,`${x.codigoArticulo} · ${x.descripcion}`,x.cantidadEntrada,formatCurrency(x.costoUnitario,invoice.currency),formatCurrency(x.valorMovimiento,invoice.currency),x.existenciaPosterior]))); panel.append(wrap); }
  if(state.purchaseWorkflow?.accrual) panel.append(buildServiceAccountingPanel(state.purchaseWorkflow.accrual,()=>refreshPurchaseWorkflow(state.purchaseWorkflow.documentId,state.purchaseWorkflow.receiptId)));
  return panel;
}

function renderInvoice() {
  elements.invoicePanel.replaceChildren();
  const invoice = state.invoice;
  if (!invoice) { elements.invoicePanel.hidden = true; return; }
  elements.invoicePanel.hidden = false;
  const hero = document.createElement('div'); hero.className = 'invoice-hero';
  const eyebrow = document.createElement('p'); eyebrow.className = 'eyebrow'; eyebrow.textContent = 'FACTURA ELECTRÓNICA DIAN';
  const title = document.createElement('h3'); title.textContent = `${invoice.documentType} ${invoice.number || 'sin número'}`;
  hero.append(eyebrow, title);

  const meta = document.createElement('div'); meta.className = 'invoice-meta';
  [
    ['Proveedor', invoice.supplier.name || 'No informado'],
    ['NIT proveedor', invoice.supplier.identification || 'No informado'],
    ['Fecha', invoice.issueDate || 'No informada'],
    ['Vencimiento', invoice.dueDate || 'No informado'],
  ].forEach(([label, value]) => {
    const box = document.createElement('div'); const span = document.createElement('span'); const strong = document.createElement('strong');
    span.textContent = label; strong.textContent = value; box.append(span, strong); meta.append(box);
  });

  const taxTotal = invoice.taxes.reduce((sum, tax) => sum + (tax.amount || 0), 0);
  const retentionTotal = invoice.retentions.reduce((sum, retention) => sum + (retention.amount || 0), 0);
  const amounts = document.createElement('div'); amounts.className = 'amount-grid';
  const amountData = [
    ['Subtotal bruto', invoice.totals.grossSubtotal], ['Descuentos', invoice.totals.allowances], ['Subtotal neto', invoice.totals.cost],
    ['Impuestos', taxTotal], ...(retentionTotal > 0 ? [['Retenciones', retentionTotal]] : []), ['Fletes detectados', invoice.totals.freight], ['Otros cargos', invoice.totals.otherCharges], ['Total a pagar', invoice.totals.payable],
  ];
  amountData.forEach(([label, value], index) => {
    const card = document.createElement('div'); card.className = `amount-card${index === amountData.length - 1 ? ' total' : ''}`;
    const span = document.createElement('span'); span.textContent = label;
    const strong = document.createElement('strong'); strong.textContent = formatCurrency(value, invoice.currency);
    card.append(span, strong); amounts.append(card);
  });

  const items = invoiceCard('Clasificación de artículos y servicios', `${invoice.items.length} líneas encontradas · revisa la propuesta antes de continuar`, buildInvoiceClassificationTable(invoice), 'invoice-table-card articles-card');
  const serialRows = invoice.items.flatMap((item) => item.serials.map((serial) => [item.line, item.code, serial.number, item.description, serial.motor, serial.chassis, serial.vin, serial.color, serial.model]));
  const serials = serialRows.length ? invoiceCard('Seriales de motos', `${serialRows.length} motos identificadas`, buildDataTable(['Línea', 'Código', 'Moto #', 'Descripción', 'Motor', 'Chasis', 'VIN', 'Color', 'Modelo (año)'], serialRows), 'invoice-table-card serials-card') : null;
  const taxes = invoiceCard('Impuestos', `${invoice.taxes.length} conceptos encontrados`, buildDataTable(['Impuesto', 'Tarifa %', 'Base', 'Valor'], invoice.taxes.map((tax) => [tax.name, tax.rate, formatCurrency(tax.taxableAmount, invoice.currency), formatCurrency(tax.amount, invoice.currency)])));
  const retentions = invoiceCard('Retenciones', invoice.retentions.length ? `${invoice.retentions.length} conceptos encontrados` : 'No se encontraron retenciones en el XML', invoice.retentions.length ? buildDataTable(['Retención', 'Tarifa %', 'Base', 'Valor'], invoice.retentions.map((retention) => [retention.name, retention.rate, formatCurrency(retention.taxableAmount, invoice.currency), formatCurrency(retention.amount, invoice.currency)])) : emptyMessage('Este XML no informa retenciones.'));
  const charges = invoiceCard('Fletes y otros cargos', `${invoice.charges.length} cargos encontrados`, buildDataTable(['Concepto', 'Base', 'Valor', 'Clasificación'], invoice.charges.map((charge) => [charge.reason, formatCurrency(charge.baseAmount, invoice.currency), formatCurrency(charge.amount, invoice.currency), charge.isFreight ? 'Flete' : 'Otro cargo'])));
  const support = document.createElement('div'); support.className = 'invoice-support-grid'; support.append(taxes, retentions, charges);
  elements.invoicePanel.append(hero, meta, amounts, invoiceOperationalSummary(invoice), buildHomologationPanel(invoice), buildPurchaseWorkflowPanel(invoice));
  if (serials) elements.invoicePanel.append(serials);
  elements.invoicePanel.append(items, support);
}
function emptyMessage(text) { const node = document.createElement('div'); node.className = 'empty'; node.textContent = text; return node; }
function showError(message) { elements.errorBox.textContent = message; elements.errorBox.hidden = false; elements.errorBox.scrollIntoView({ behavior: 'smooth' }); }
function hideError() { elements.errorBox.hidden = true; }
let successMessageTimer;
function showSuccess(message) {
  let toast = document.querySelector('#successToast');
  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'successToast';
    toast.className = 'success-toast';
    toast.setAttribute('role', 'status');
    toast.setAttribute('aria-live', 'polite');
    document.body.append(toast);
  }
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(successMessageTimer);
  successMessageTimer = setTimeout(() => toast.classList.remove('visible'), 4500);
}

function handleFile(file) {
  if (!file) return;
  document.body.classList.remove('has-results');
  elements.results.hidden = true;
  elements.xmlInput.value = '';
  hideError();
  elements.inputStatus.classList.remove('status-error');
  state.fileName = file.name;
  if (file.size === 0) {
    elements.inputStatus.textContent = `${file.name} · archivo vacío (0 bytes)`;
    elements.inputStatus.classList.add('status-error');
    return showError('El archivo seleccionado está vacío (0 bytes). Si está guardado en Google Drive, descárgalo o márcalo como disponible sin conexión y vuelve a seleccionarlo.');
  }
  if (file.size > MAX_FILE_SIZE) {
    elements.inputStatus.textContent = `${file.name} · supera 25 MB`;
    elements.inputStatus.classList.add('status-error');
    return showError('El archivo supera el límite de 25 MB.');
  }
  if (!file.name.toLowerCase().endsWith('.xml') && !/xml/.test(file.type)) {
    elements.inputStatus.textContent = `${file.name} · formato no compatible`;
    elements.inputStatus.classList.add('status-error');
    return showError('Selecciona un archivo con formato XML.');
  }
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const decoded = decodeXmlBuffer(reader.result);
      elements.xmlInput.value = decoded.text;
      state.fileName = file.name;
      elements.inputStatus.textContent = `${file.name} · ${formatBytes(file.size)} · ${decoded.encoding.toUpperCase()}`;
      analyze();
    } catch (error) { showError(error.message); }
  };
  reader.onerror = () => showError('No fue posible leer el archivo.');
  reader.readAsArrayBuffer(file);
}
function formatBytes(bytes) { return bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(1)} MB`; }
function decodeXmlBuffer(buffer) {
  const bytes = new Uint8Array(buffer);
  let encoding = 'utf-8';
  let offset = 0;
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) offset = 3;
  else if (bytes[0] === 0xff && bytes[1] === 0xfe) { encoding = 'utf-16le'; offset = 2; }
  else if (bytes[0] === 0xfe && bytes[1] === 0xff) { encoding = 'utf-16be'; offset = 2; }
  else {
    const preview = String.fromCharCode(...bytes.subarray(0, Math.min(bytes.length, 512)));
    const declaration = preview.match(/<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']/i);
    if (declaration) encoding = declaration[1].toLowerCase();
  }
  try {
    return { text: new TextDecoder(encoding).decode(bytes.subarray(offset)), encoding };
  } catch {
    throw new Error(`La codificación “${encoding}” declarada por el XML no es compatible con este navegador.`);
  }
}
function download(name, content, type) {
  const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([content], { type })); link.download = name; link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 500);
}
function csvEscape(value) { const text = String(value ?? ''); return /[",\n;]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text; }
function exportCsv() {
  const rows = [['seccion', 'grupo', 'registro', 'ruta', 'valor', 'tipo']];
  state.headers.forEach((field) => rows.push(['cabecera', '', '', field.path, field.value, field.type]));
  state.details.forEach((group) => {
    group.rows.forEach((record, index) => {
      Object.entries(record).forEach(([path, value]) => {
        rows.push(['detalle', group.path, index + 1, path, value, inferType(String(value))]);
      });
    });
  });
  download('datos-xml.csv', '\ufeff' + rows.map((row) => row.map(csvEscape).join(';')).join('\n'), 'text/csv;charset=utf-8');
}
async function exportExcel() {
  const button = $('#exportExcel');
  const originalText = button.textContent;
  button.disabled = true;
  button.textContent = 'Creando Excel…';
  hideError();
  try {
    const response = await fetch('/api/export-xlsx', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        documentTitle: state.fileName,
        headers: state.headers,
        details: state.details.map(({ path, name, rows }) => ({ path, name, rows })),
        fields: state.fields,
        invoice: state.invoice,
      }),
    });
    if (!response.ok) throw new Error((await response.json()).error || 'No fue posible crear el archivo Excel.');
    const url = URL.createObjectURL(await response.blob());
    const link = document.createElement('a');
    link.href = url;
    link.download = `${(state.fileName || 'datos-xml').replace(/\.xml$/i, '')}.xlsx`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 500);
  } catch (error) { showError(error.message); }
  finally { button.disabled = false; button.textContent = originalText; }
}

function manualCurrency(value) {
  return new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 2 }).format(value || 0);
}

function buildServiceAccountingPanel(accrual,refresh) {
  const panel=document.createElement('section'); panel.className='service-accounting-panel';
  const heading=document.createElement('div'); heading.className='service-accounting-heading';
  const copy=document.createElement('div'); const eyebrow=document.createElement('span'); eyebrow.textContent='CAUSACIÓN CONTABLE';
  const title=document.createElement('h3'); title.textContent=`Servicios ${accrual.numero}`;
  const text=document.createElement('p'); text.textContent='Asigna la cuenta de cada gasto y confirma el comprobante. Este proceso no genera movimientos de inventario.';
  copy.append(eyebrow,title,text); const noKardex=document.createElement('strong'); noKardex.className='no-kardex-badge'; noKardex.textContent='SIN KARDEX'; heading.append(copy,noKardex); panel.append(heading);

  const totals=document.createElement('div'); totals.className='service-accounting-totals';
  [['Base',accrual.base],['Impuestos',accrual.impuestos],['Retenciones',accrual.retenciones],['Cuenta por pagar',accrual.porPagar]].forEach(([label,value])=>{const box=document.createElement('div');const small=document.createElement('span');small.textContent=label;const strong=document.createElement('strong');strong.textContent=manualCurrency(value);box.append(small,strong);totals.append(box);});
  panel.append(totals);

  const accounts=state.apiContext?.accounts||[]; const periods=state.apiContext?.accountingPeriods||[]; const posted=accrual.estado==='CONTABILIZADA';
  if(!accounts.length||!periods.length){const notice=document.createElement('p');notice.className='workflow-notice';notice.textContent='La empresa necesita al menos un periodo contable abierto y cuentas de movimiento para contabilizar servicios.';panel.append(notice);return panel;}

  const dimensions=document.createElement('div'); dimensions.className='accounting-dimensions';
  const inputField=(label,value='')=>{const wrapper=document.createElement('label');const span=document.createElement('span');span.textContent=label;const input=document.createElement('input');input.value=value||'';input.disabled=posted;wrapper.append(span,input);dimensions.append(wrapper);return input;};
  const center=inputField('Centro de costo',accrual.centroCostoCodigo); const project=inputField('Proyecto',accrual.proyectoCodigo); panel.append(dimensions);

  const expenseAccounts=accounts.filter(x=>['GASTO','COSTO','ACTIVO'].includes(x.tipo));
  const lineWrap=document.createElement('div'); lineWrap.className='service-account-lines';
  accrual.lineas.forEach(line=>{const row=document.createElement('label');const info=document.createElement('span');const name=document.createElement('strong');name.textContent=`Línea ${line.numeroLinea} · ${line.descripcion}`;const values=document.createElement('small');values.textContent=`Base ${manualCurrency(line.base)} · IVA ${manualCurrency(line.impuestos)} · Retención ${manualCurrency(line.retenciones)}`;info.append(name,values);const select=document.createElement('select');select.dataset.serviceLine=String(line.numeroLinea);select.disabled=posted;select.add(new Option('Seleccionar cuenta de gasto…',''));expenseAccounts.forEach(x=>select.add(new Option(`${x.codigo} · ${x.nombre}`,x.codigo)));select.value=line.cuentaContableCodigo||'';row.append(info,select);lineWrap.append(row);});
  panel.append(lineWrap);

  const assign=document.createElement('button'); assign.type='button'; assign.className='button secondary'; assign.textContent=posted?'Cuentas validadas':'3. Validar cuentas y dimensiones'; assign.disabled=posted;
  assign.addEventListener('click',async()=>{const lineas=Array.from(lineWrap.querySelectorAll('[data-service-line]')).map(select=>({numeroLinea:Number(select.dataset.serviceLine),cuentaContableCodigo:select.value}));if(lineas.some(x=>!x.cuentaContableCodigo))return showError('Selecciona una cuenta contable para cada línea de servicio.');try{assign.disabled=true;assign.textContent='Validando…';await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/service-accruals/${accrual.causacionServicioId}/accounts`,{method:'PUT',body:JSON.stringify({centroCostoCodigo:center.value.trim()||null,proyectoCodigo:project.value.trim()||null,lineas})});await refresh();}catch(error){showError(`No fue posible validar las cuentas. ${error.message}`);assign.disabled=false;assign.textContent='3. Validar cuentas y dimensiones';}});
  panel.append(assign);

  const posting=document.createElement('div'); posting.className='service-posting-controls';
  const selectField=(label,rows,placeholder)=>{const wrapper=document.createElement('label');const span=document.createElement('span');span.textContent=label;const select=document.createElement('select');select.add(new Option(placeholder,''));rows.forEach(x=>select.add(new Option(`${x.codigo} · ${x.nombre||x.estado}`,x.periodoContableId||x.codigo)));select.disabled=posted;wrapper.append(span,select);posting.append(wrapper);return select;};
  const period=selectField('Periodo contable *',periods,'Seleccionar periodo…');
  const matchingPeriod=periods.find(x=>accrual.fechaContable>=x.fechaInicio&&accrual.fechaContable<=x.fechaFin);period.value=String(accrual.periodoContableId||matchingPeriod?.periodoContableId||'');
  const taxAccounts=accounts.filter(x=>x.tipo==='ACTIVO'); const retentionAccounts=accounts.filter(x=>x.tipo==='PASIVO'); const payableAccounts=accounts.filter(x=>x.tipo==='PASIVO');
  const tax=selectField('Cuenta de impuesto',taxAccounts,'No aplica'); const retention=selectField('Cuenta de retención',retentionAccounts,'No aplica'); const payable=selectField('Cuenta por pagar *',payableAccounts,'Seleccionar cuenta…');
  const choose=(select,matcher)=>{const match=accounts.find(matcher);if(match&&[...select.options].some(x=>x.value===match.codigo))select.value=match.codigo;};
  choose(tax,x=>x.tipo==='ACTIVO'&&(/2408/.test(x.codigo)||/iva|impuesto/i.test(x.nombre)));choose(retention,x=>x.tipo==='PASIVO'&&(/236/.test(x.codigo)||/retenci/i.test(x.nombre)));choose(payable,x=>x.tipo==='PASIVO'&&(/^22/.test(x.codigo)||/proveedor|por pagar/i.test(x.nombre)));
  panel.append(posting);

  const post=document.createElement('button');post.type='button';post.className='button confirm-entry';post.textContent=posted?'4. Servicio contabilizado':'4. Contabilizar servicio';
  const updatePost=()=>{post.disabled=posted||accrual.estado!=='VALIDADA'||!period.value||!payable.value||(accrual.impuestos>0&&!tax.value)||(accrual.retenciones>0&&!retention.value);};[period,tax,retention,payable].forEach(x=>x.addEventListener('change',updatePost));updatePost();
  post.addEventListener('click',async()=>{if(!window.confirm(`Vas a contabilizar la causación ${accrual.numero}. Se generará un comprobante contable y una cuenta por pagar, sin afectar Kardex. ¿Deseas continuar?`))return;try{post.disabled=true;post.textContent='Contabilizando…';await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/service-accruals/${accrual.causacionServicioId}/post`,{method:'POST',body:JSON.stringify({periodoContableId:Number(period.value),cuentaImpuestoCodigo:tax.value||null,cuentaRetencionCodigo:retention.value||null,cuentaPorPagarCodigo:payable.value,correlationId:crypto.randomUUID?crypto.randomUUID():null})});await refresh();}catch(error){showError(`No fue posible contabilizar el servicio. ${error.message}`);post.textContent='4. Contabilizar servicio';updatePost();}});panel.append(post);

  if(posted){const result=document.createElement('div');result.className='accounting-result';const resultTitle=document.createElement('h4');resultTitle.textContent=`Comprobante ${accrual.comprobanteContableId} balanceado`;const debit=accrual.comprobanteLineas.reduce((s,x)=>s+x.debito,0);const credit=accrual.comprobanteLineas.reduce((s,x)=>s+x.credito,0);const balance=document.createElement('p');balance.textContent=`Débitos ${manualCurrency(debit)} · Créditos ${manualCurrency(credit)} · Diferencia ${manualCurrency(debit-credit)}`;result.append(resultTitle,balance,buildDataTable(['Línea','Cuenta','Descripción','Débito','Crédito','Centro / proyecto'],accrual.comprobanteLineas.map(x=>[x.numeroLinea,`${x.cuentaCodigo} · ${x.cuentaNombre}`,x.descripcion,manualCurrency(x.debito),manualCurrency(x.credito),[x.centroCostoCodigo,x.proyectoCodigo].filter(Boolean).join(' · ')||'—'])));panel.append(result);}
  return panel;
}

function updateManualTotals() {
  let total = 0;
  let requiresWarehouse = false;
  elements.manualLines.querySelectorAll('[data-manual-line]').forEach((row) => {
    const classification = row.querySelector('[data-field="classification"]').value;
    const quantity = Math.max(Number(row.querySelector('[data-field="quantity"]').value) || 0, 0);
    const unitPrice = Math.max(Number(row.querySelector('[data-field="unitPrice"]').value) || 0, 0);
    const discount = Math.max(Number(row.querySelector('[data-field="discount"]').value) || 0, 0);
    const tax = Math.max(Number(row.querySelector('[data-field="tax"]').value) || 0, 0);
    const charge = Math.max(Number(row.querySelector('[data-field="charge"]').value) || 0, 0);
    const retention = Math.max(Number(row.querySelector('[data-field="retention"]').value) || 0, 0);
    const lineTotal = Math.max((quantity * unitPrice) - discount + charge + tax - retention, 0);
    row.querySelector('[data-field="total"]').textContent = manualCurrency(lineTotal);
    total += lineTotal;
    if (classification === 'inventory') requiresWarehouse = true;
  });
  elements.manualGrandTotal.textContent = manualCurrency(total);
  elements.warehouseField.hidden = !requiresWarehouse;
  elements.manualWarehouse.required = requiresWarehouse;
}

function manualLineField(labelText,name,type='text',className='') {
  const label=document.createElement('label'); label.className=`manual-line-field ${className}`.trim(); const span=document.createElement('span'); span.textContent=labelText;
  const input=type==='select'?document.createElement('select'):type==='textarea'?document.createElement('textarea'):document.createElement('input');
  if(type!=='select'&&type!=='textarea') input.type=type; input.dataset.field=name; label.append(span,input); return {label,input};
}

function populateManualArticleOptions(select,classification,current='') {
  const data=getCompanyMasterData().data; const candidates=state.runtimeMode==='api'&&state.erpSession?.api&&!state.apiContext?[]:compatibleArticles(data,classification);
  select.replaceChildren(new Option(classification==='inventory'?'Seleccionar artículo inventariable…':'Seleccionar concepto…',''));
  candidates.forEach(x=>select.add(new Option(`${x.code} · ${x.description}`,x.id)));
  if([...select.options].some(x=>x.value===String(current))) select.value=String(current);
}

function addManualLine(defaultClassification = state.registrationMode === 'services' ? 'service' : 'inventory') {
  state.manualLineSequence += 1;
  const row = document.createElement('article'); row.className='manual-line-card'; row.dataset.manualLine='true';
  row.dataset.lineId = String(state.manualLineSequence);
  const head=document.createElement('div'); head.className='manual-line-head'; const headText=document.createElement('div'); const strong=document.createElement('strong'); strong.textContent=`Línea ${state.manualLineSequence}`; const small=document.createElement('span'); small.textContent=defaultClassification==='service'?'Base, impuestos y retenciones del servicio':'Valores y trazabilidad de la unidad recibida'; headText.append(strong,small);
  const remove = document.createElement('button'); remove.type='button'; remove.className='remove-line'; remove.setAttribute('aria-label','Eliminar línea'); remove.textContent='×'; head.append(headText,remove);
  const grid=document.createElement('div'); grid.className='manual-line-grid';
  const classificationField=manualLineField('Clasificación *','classification','select','medium'); const classification=classificationField.input;
  Object.entries(classificationLabels).filter(([value])=>state.registrationMode!=='services'||value==='service').forEach(([value, label]) => {
    const option = document.createElement('option'); option.value = value; option.textContent = label; option.selected = value === defaultClassification; classification.append(option);
  });
  const articleField=manualLineField('Artículo o concepto interno *','articleId','select','wide'); populateManualArticleOptions(articleField.input,defaultClassification);
  const descriptionField=manualLineField('Descripción *','description','text','medium'); descriptionField.input.placeholder=defaultClassification==='service'?'Ej. Mantenimiento preventivo':'Ej. Motocicleta XR190'; descriptionField.input.required=true;
  const codeField=manualLineField('Código externo','code'); codeField.input.placeholder='Código proveedor';
  const numericDefinitions=[['Cantidad *','quantity','1','0.000001'],['Valor unitario *','unitPrice','0','0.01'],['Descuento','discount','0','0.01'],['Impuesto','tax','0','0.01'],['Retención','retention','0','0.01'],['Cargo / flete','charge','0','0.01']];
  const numericFields=numericDefinitions.map(([label,name,value,step])=>{const field=manualLineField(label,name,'number');field.input.min='0';field.input.step=step;field.input.value=value;return field;});
  const total=document.createElement('div'); total.className='manual-line-total'; const totalLabel=document.createElement('span'); totalLabel.textContent='TOTAL LÍNEA'; const totalValue=document.createElement('strong'); totalValue.dataset.field='total'; totalValue.textContent=manualCurrency(0); total.append(totalLabel,totalValue);
  const lotField=manualLineField('Número de lote','lot','text'); lotField.input.placeholder='Lote del proveedor';
  const expiryField=manualLineField('Fecha de vencimiento','expiry','date');
  const serialField=manualLineField('Unidades serializadas','serials','textarea','full'); serialField.input.placeholder='Una unidad por línea: serial; motor; chasis; VIN; color; modelo';
  const traceHint=document.createElement('span'); traceHint.className='manual-trace-hint'; traceHint.textContent='Para motos puedes dejar serial vacío: ; MOTOR; CHASIS; VIN; COLOR; MODELO'; serialField.label.append(traceHint);
  grid.append(classificationField.label,articleField.label,descriptionField.label,codeField.label,...numericFields.map(x=>x.label),total,lotField.label,expiryField.label,serialField.label); row.append(head,grid);
  const syncArticle=()=>{const article=findById(getCompanyMasterData().data.articles,articleField.input.value);const isInventory=classification.value==='inventory';const retentionField=row.querySelector('[data-field="retention"]');if(article){if(!descriptionField.input.value)descriptionField.input.value=article.description;if(!codeField.input.value)codeField.input.value=article.code;}descriptionField.input.placeholder=classification.value==='service'?'Ej. Mantenimiento preventivo':'Ej. Motocicleta XR190';lotField.label.hidden=!isInventory;expiryField.label.hidden=!isInventory;serialField.label.hidden=!isInventory;lotField.input.disabled=!isInventory||Boolean(article&&!article.lot);expiryField.input.disabled=!isInventory||Boolean(article&&!article.expiry);serialField.input.disabled=!isInventory;retentionField.disabled=classification.value!=='service';if(lotField.input.disabled)lotField.input.value='';if(expiryField.input.disabled)expiryField.input.value='';if(serialField.input.disabled)serialField.input.value='';if(retentionField.disabled)retentionField.value='0';small.textContent=classification.value==='service'?'Base, impuestos y retenciones del servicio':'Valores y trazabilidad de la unidad recibida';};
  classification.addEventListener('change',()=>{populateManualArticleOptions(articleField.input,classification.value);syncArticle();updateManualTotals();}); articleField.input.addEventListener('change',syncArticle);
  remove.addEventListener('click', () => {
    if (elements.manualLines.querySelectorAll('[data-manual-line]').length === 1) return;
    row.remove(); updateManualTotals();
  });
  row.addEventListener('input', updateManualTotals);
  row.addEventListener('change', updateManualTotals);
  elements.manualLines.append(row);
  syncArticle();
  updateManualTotals();
}

function collectManualLines() {
  return Array.from(elements.manualLines.querySelectorAll('[data-manual-line]')).map((row,index) => {
    const get = (field) => row.querySelector(`[data-field="${field}"]`).value;
    const quantity = Number(get('quantity')) || 0;
    const unitPrice = Number(get('unitPrice')) || 0;
    const discount = Number(get('discount')) || 0;
    const tax=Number(get('tax'))||0; const retention=Number(get('retention'))||0; const charge=Number(get('charge'))||0; const gross=quantity*unitPrice; const net=Math.max(gross-discount+charge,0);
    const article=findById(getCompanyMasterData().data.articles,get('articleId'));
    const serials=get('serials').split(/\r?\n/).map(x=>x.trim()).filter(Boolean).map((value,serialIndex)=>{const [serial='',motor='',chassis='',vin='',color='',model='']=value.split(';').map(x=>x.trim());return {number:serialIndex+1,serial,motor,chassis,vin,color,model,raw:value};});
    return { line:index+1,classification:get('classification'),articleId:article?.id||null,unitId:article?.unitId||null,article,description:get('description').trim(),code:get('code').trim(),quantity,unitPrice,discount,tax,retention,charge,gross,net,total:net+tax-retention,lot:get('lot').trim(),expiry:get('expiry')||null,serials };
  });
}

function appendSummaryValue(parent, label, value) {
  const box = document.createElement('div');
  const span = document.createElement('span'); span.textContent = label;
  const strong = document.createElement('strong'); strong.textContent = value;
  box.append(span, strong); parent.append(box);
}

function buildManualSupplierDocumentPayload(draft) {
  const classification={inventory:'INVENTARIO',service:'SERVICIO_GASTO','acquisition-cost':'COSTO_ADQUISICION'};
  return {
    proveedorIdentificacion:draft.nit,proveedorRazonSocial:draft.supplier,tipoDocumento:draft.documentType,numeroDocumento:draft.invoiceNumber,
    fechaDocumento:draft.issueDate,fechaVencimiento:draft.dueDate||null,condicionPago:draft.paymentCondition,diasCredito:draft.creditDays,crearArticulosFaltantes:false,moneda:'COP',cufeCude:null,fuente:'MANUAL',
    subtotalBruto:draft.lines.reduce((s,x)=>s+x.gross,0),descuentoTotal:draft.lines.reduce((s,x)=>s+x.discount,0),
    impuestoTotal:draft.lines.reduce((s,x)=>s+x.tax,0),cargoTotal:draft.lines.reduce((s,x)=>s+x.charge,0),totalPagar:draft.total,xmlOriginal:null,documentoGuid:draft.id,
    lineas:draft.lines.map(x=>({numeroLinea:x.line,articuloId:Number(x.articleId)||null,codigoExterno:x.code||null,descripcion:x.description,clasificacion:classification[x.classification],cantidad:x.quantity,
      unidadMedidaId:Number(x.unitId)||null,unidadCodigo:findById(getCompanyMasterData().data.units,x.unitId)?.code||'UND',manejaSerial:Boolean(x.article?.serial||x.serials.length),factorAUnidadBase:1,precioUnitario:x.unitPrice,subtotalBruto:x.gross,descuento:x.discount,impuesto:x.tax,cargo:x.charge,retencion:x.retention,totalNeto:x.net,
      numeroLote:x.lot||null,fechaVencimiento:x.expiry||null,seriales:x.serials.map(s=>({numeroUnidad:s.number,serial:s.serial||null,motor:s.motor||null,chasis:s.chassis||null,vin:s.vin||null,color:s.color||null,modelo:s.model||null,informacionOriginal:s.raw||null}))}))
  };
}

async function refreshManualWorkflow(documentId,receiptId=null) {
  const companyId=state.erpSession.company.id; const workflow=await apiRequest(`/api/v1/companies/${companyId}/supplier-documents/${documentId}`); const effectiveReceipt=receiptId||workflow.recepcionMercanciaId;
  const movements=effectiveReceipt?await apiRequest(`/api/v1/companies/${companyId}/receipts/${effectiveReceipt}/movements`):[];
  const accrual=workflow.causacionServicioId?await apiRequest(`/api/v1/companies/${companyId}/service-accruals/${workflow.causacionServicioId}`):null;
  state.manualWorkflow={documentId,receiptId:effectiveReceipt,workflow,movements,accrual}; renderManualDraft(state.manualDraft);
}

function buildManualWorkflowPanel(draft) {
  const panel=document.createElement('section'); panel.className='purchase-workflow-panel manual-posting-panel'; const workflow=state.manualWorkflow?.workflow;
  const inventoryLines=draft.lines.filter(x=>x.classification==='inventory'); const serviceLines=draft.lines.filter(x=>x.classification==='service');
  const heading=document.createElement('div'); heading.className='purchase-workflow-heading'; heading.innerHTML='<div><span>CONTROL ERP</span><h3>Estado de la compra</h3><p>El borrador puede completarse aquí o recuperarse en cualquier momento desde Entradas guardadas.</p></div>'; panel.append(heading);
  const actions=document.createElement('div');actions.className='workflow-actions';const process=document.createElement('button');process.type='button';process.className='button primary';process.textContent=inventoryLines.length?(workflow?.recepcionEstado==='CONTABILIZADA'?'Entrada contabilizada':workflow?.recepcionMercanciaId?'Contabilizar entrada':'Preparar y contabilizar entrada'):(workflow?.causacionServicioId?'Causación preparada':'Preparar causación');process.disabled=!workflow||workflow?.recepcionEstado==='CONTABILIZADA'||(!inventoryLines.length&&Boolean(workflow?.causacionServicioId));const tray=document.createElement('button');tray.type='button';tray.className='button secondary';tray.textContent='Ver entradas guardadas';tray.addEventListener('click',showSavedPurchases);actions.append(process,tray);panel.append(actions);
  process.addEventListener('click',async()=>{if(inventoryLines.length&&!window.confirm(`Se afectarán existencias y Kardex con ${draft.invoiceNumber}. ¿Deseas continuar?`))return;try{process.disabled=true;process.textContent='Procesando…';let receiptId=workflow.recepcionMercanciaId;if(!receiptId&&!workflow.causacionServicioId){const prepared=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents/${state.manualWorkflow.documentId}/prepare`,{method:'POST',body:JSON.stringify({bodegaId:inventoryLines.length?Number(draft.warehouse):null,periodoInventarioId:inventoryLines.length?Number(draft.period):null,fechaContable:draft.issueDate,numeroRecepcion:inventoryLines.length?`ENT-${draft.invoiceNumber}`.slice(0,50):null,numeroCausacion:serviceLines.length?`CAU-${draft.invoiceNumber}`.slice(0,50):null})});receiptId=prepared.recepcionMercanciaId;}if(receiptId&&workflow.recepcionEstado!=='CONTABILIZADA')await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/receipts/${receiptId}/post`,{method:'POST',body:JSON.stringify({correlationId:crypto.randomUUID?crypto.randomUUID():null})});await refreshManualWorkflow(state.manualWorkflow.documentId,receiptId);showSuccess(receiptId?'Entrada contabilizada con sus seriales.':'Causación preparada.');}catch(error){showError(`No fue posible completar el proceso. ${error.message}`);process.disabled=false;}});
  if(workflow){const status=document.createElement('div');status.className='workflow-status';status.innerHTML=`<span>Documento <strong>${workflow.estado}</strong></span><span>Recepción <strong>${workflow.recepcionEstado||'No aplica'}</strong></span><span>Causación <strong>${workflow.causacionEstado||'No aplica'}</strong></span><span>Seriales <strong>${workflow.unidadesSerializadas}</strong></span>`;panel.append(status);}
  if(state.manualWorkflow?.movements?.length){const wrap=document.createElement('div');wrap.className='workflow-movements';const h=document.createElement('h4');h.textContent='Movimientos de Kardex generados';wrap.append(h,buildDataTable(['Movimiento','Línea','Artículo','Cantidad','Costo unitario','Valor','Lote / vencimiento','Existencia posterior'],state.manualWorkflow.movements.map(x=>[x.movimientoInventarioId,x.numeroLinea,`${x.codigoArticulo} · ${x.descripcion}`,x.cantidadEntrada,manualCurrency(x.costoUnitario),manualCurrency(x.valorMovimiento),x.numeroLote?`${x.numeroLote}${x.fechaVencimiento?` · ${x.fechaVencimiento}`:''}`:'—',x.existenciaPosterior])));panel.append(wrap);}
  if(state.manualWorkflow?.accrual) panel.append(buildServiceAccountingPanel(state.manualWorkflow.accrual,()=>refreshManualWorkflow(state.manualWorkflow.documentId,state.manualWorkflow.receiptId)));
  return panel;
}

function renderManualDraft(draft) {
  elements.manualResult.replaceChildren();
  const heading = document.createElement('div'); heading.className = 'manual-result-heading';
  const headingText = document.createElement('div');
  const workflow=state.manualWorkflow?.workflow; const allPosted=workflow&&(workflow.recepcionMercanciaId?workflow.recepcionEstado==='CONTABILIZADA':true)&&(workflow.causacionServicioId?workflow.causacionEstado==='CONTABILIZADA':true); const eyebrow = document.createElement('p'); eyebrow.className = 'eyebrow'; eyebrow.textContent = allPosted?'DOCUMENTO CONTABILIZADO':'BORRADOR GUARDADO';
  const title = document.createElement('h2'); title.textContent = draft.invoiceNumber ? `Documento ${draft.invoiceNumber}` : 'Compra sin número de factura';
  const description = document.createElement('p'); description.textContent = allPosted?'Mercancía y servicios quedaron procesados según el efecto de cada línea.':'El borrador todavía no afecta inventario ni contabilidad.';
  headingText.append(eyebrow, title, description);
  const badge = document.createElement('span'); badge.className = 'draft-badge'; badge.textContent = workflow?workflow.estado:'BORRADOR LOCAL';
  heading.append(headingText, badge);

  const meta = document.createElement('div'); meta.className = 'draft-meta';
  appendSummaryValue(meta, 'Proveedor', draft.supplier);
  appendSummaryValue(meta, 'NIT', draft.nit || 'No informado');
  appendSummaryValue(meta, 'Fecha', draft.issueDate);
  appendSummaryValue(meta, 'Bodega', draft.warehouseName || draft.warehouse || 'No aplica');

  const effect = { inventory: 0, service: 0, 'acquisition-cost': 0 };
  draft.lines.forEach((line) => { effect[line.classification] += line.total; });
  const effects = document.createElement('div'); effects.className = 'effect-grid draft-effects';
  [
    ['inventory', 'Mercancía', 'Entrada y Kardex'],
    ['service', 'Servicios', 'Causación sin Kardex'],
    ['acquisition-cost', 'Costos adicionales', 'Pendiente de distribución'],
  ].forEach(([type, label, detail]) => {
    const card = document.createElement('div'); card.className = `effect-card ${type}`;
    const amount = document.createElement('strong'); amount.textContent = manualCurrency(effect[type]);
    const copy = document.createElement('div'); const name = document.createElement('b'); name.textContent = label;
    const small = document.createElement('small'); small.textContent = detail; copy.append(name, small); card.append(amount, copy); effects.append(card);
  });

  const table = buildDataTable(['Clasificación','Artículo','Descripción','Cantidad','Valor unitario','Descuento','Impuesto','Retención','Cargo','Lote / vencimiento','Seriales','Total'], draft.lines.map((line) => [classificationLabels[line.classification],line.article?`${line.article.code} · ${line.article.description}`:line.code,line.description,line.quantity,manualCurrency(line.unitPrice),manualCurrency(line.discount),manualCurrency(line.tax),manualCurrency(line.retention),manualCurrency(line.charge),line.lot?`${line.lot}${line.expiry?` · ${line.expiry}`:''}`:'—',line.serials.length,manualCurrency(line.total)]));
  const linesCard = invoiceCard('Detalle del borrador', `${draft.lines.length} líneas · Total ${manualCurrency(draft.total)}`, table, 'invoice-table-card manual-draft-lines');
  const serialRows=draft.lines.flatMap(line=>line.serials.map(serial=>[line.line,line.article?.code||line.code||'—',line.description,serial.number,serial.serial||'—',serial.motor||'—',serial.chassis||'—',serial.vin||'—',serial.color||'—',serial.model||'—']));
  const serialCard=serialRows.length?invoiceCard('Seriales de motos',`${serialRows.length} unidades guardadas en el borrador`,buildDataTable(['Línea','Artículo','Descripción','Moto #','Serial','Motor','Chasis','VIN','Color','Modelo'],serialRows),'serials-card manual-draft-serials'):null;
  elements.manualResult.append(heading, meta, effects, linesCard);if(serialCard)elements.manualResult.append(serialCard);
  if(state.runtimeMode==='api'&&state.erpSession?.api&&['goods','services'].includes(state.registrationMode)) elements.manualResult.append(buildManualWorkflowPanel(draft));
  elements.manualResult.hidden = false;
  document.body.classList.add('has-results');
  elements.manualResult.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function setRegistrationMode(mode) {
  if (!canPurchaseMode(mode)) { routeToDefaultWorkspace(true); return; }
  state.registrationMode = mode;
  elements.purchaseModule.hidden = false;
  elements.masterDataModule.hidden = true;
  elements.savedPurchasesModule.hidden = true;
  elements.inventoryModule.hidden = true;
  elements.advancedControlsModule.hidden = true;
  elements.securityModule.hidden = true;
  elements.inventoryNav.classList.remove('active');
  elements.controlsNav.classList.remove('active');
  elements.securityAdminNav.classList.remove('active');
  elements.savedPurchasesNav.classList.remove('active');
  document.querySelector('.breadcrumb span').textContent = 'Compras';
  document.querySelectorAll('[data-master-view]').forEach((button) => button.classList.remove('active'));
  document.querySelectorAll('[data-registration-mode]').forEach((button) => button.classList.toggle('active', button.dataset.registrationMode === mode));
  const modeCopy = {
    xml: { breadcrumb: 'Entrada automática', title: 'Entrada automática<br>de mercancía' },
    goods: { breadcrumb: 'Entrada manual', title: 'Entrada manual<br>de mercancía' },
    services: { breadcrumb: 'Causar servicios', title: 'Causación de<br>servicios' },
  }[mode];
  elements.breadcrumbCurrent.textContent = modeCopy.breadcrumb;
  elements.moduleHeadingTitle.innerHTML = modeCopy.title;
  const isXml = mode === 'xml';
  elements.xmlWorkspace.hidden = !isXml;
  elements.xmlWorkspace.classList.toggle('active', isXml);
  elements.manualWorkspace.hidden = isXml;
  elements.manualWorkspace.classList.toggle('active', !isXml);
  elements.results.hidden = true;
  elements.manualResult.hidden = true;
  document.body.classList.remove('has-results');
  if (!isXml) {
    const isService = mode === 'services';
    elements.manualWorkspaceTitle.textContent = isService ? 'Causación manual de servicios' : 'Entrada manual de mercancía';
    elements.manualWorkspaceSubtitle.textContent = isService ? 'Registra gastos de proveedores sin afectar inventario.' : 'Registra artículos recibidos con o sin factura del proveedor.';
    elements.manualTypePill.textContent = isService ? 'SERVICIOS' : 'MERCANCÍA';
    elements.manualPostButton.firstChild.textContent=isService?'Guardar y preparar causación ':'Guardar y contabilizar entrada ';
    elements.manualLines.replaceChildren();
    state.manualWorkflow=null; state.manualDraft=null;
    addManualLine(isService ? 'service' : 'inventory');
    renderManualReferenceOptions();
  }
}

function selectCompany(option) {
  const email = state.erpSession?.email || state.pendingEmail;
  const session = {
    email,
    name: state.pendingName||state.erpSession?.name || displayNameFromEmail(email), api:option.dataset.api==='true',
    superAdmin:state.pendingSuperAdmin||Boolean(state.erpSession?.superAdmin),
    company: { id: option.dataset.companyId, name: option.dataset.companyName, nit: option.dataset.companyNit, initials: option.dataset.companyInitials, currency:option.dataset.currency||'COP' },
    signedInAt: state.erpSession?.signedInAt || new Date().toISOString(),
  };
  state.apiContext=null; state.purchaseWorkflow=null; state.manualWorkflow=null; state.manualDraft=null;
  closeErpDialog(elements.companyDialog);
  enterErp(session);
}

async function createCompanyAsSuperAdmin(event) {
  event.preventDefault();
  elements.companyCreateError.hidden=true;
  if(!(state.pendingSuperAdmin||state.erpSession?.superAdmin)) return;
  const form=elements.companyCreateForm;
  const submit=form.querySelector('[type="submit"]');
  const data=new FormData(form);
  const payload={
    codigo:String(data.get('codigo')||'').trim(),nit:String(data.get('nit')||'').trim(),
    digitoVerificacion:String(data.get('digitoVerificacion')||'').trim()||null,razonSocial:String(data.get('razonSocial')||'').trim(),
    monedaFuncional:String(data.get('monedaFuncional')||'COP'),zonaHoraria:'America/Bogota',marcoContable:String(data.get('marcoContable')||'GRUPO_2')
  };
  try {
    submit.disabled=true;submit.textContent='Creando empresa…';
    const created=await apiRequest('/api/v1/companies',{method:'POST',body:JSON.stringify(payload)});
    const companies=await apiRequest('/api/v1/companies');
    renderCompanyOptions(companies,true);configureSuperAdminCompanyPanel(true,true);form.reset();
    const option=Array.from($('#companyOptions').querySelectorAll('.company-option')).find(x=>x.dataset.companyId===String(created.empresaId));
    if(option)selectCompany(option);
  } catch(error) {
    elements.companyCreateError.textContent=error.message;elements.companyCreateError.hidden=false;
  } finally {submit.disabled=false;submit.textContent='Crear empresa operativa';}
}

async function openCompanyManager() {
  if(state.runtimeMode==='api'&&apiToken()){
    try {const companies=await apiRequest('/api/v1/companies');renderCompanyOptions(companies,true);configureSuperAdminCompanyPanel(Boolean(state.erpSession?.superAdmin),companies.length>0);}
    catch(error){showError(`No fue posible cargar las empresas. ${error.message}`);return;}
  } else configureSuperAdminCompanyPanel(false,true);
  openErpDialog(elements.companyDialog);
}

async function beginLocalLogin(event) {
  event.preventDefault();
  const email = elements.loginEmail.value.trim();
  if (!email || elements.loginPassword.value.length < 4) {
    elements.loginError.textContent = 'Escribe un correo válido y una contraseña de al menos 4 caracteres.';
    elements.loginError.hidden = false;
    return;
  }
  elements.loginError.hidden = true;
  state.pendingEmail = email;
  state.pendingName='';
  state.pendingSuperAdmin=false;
  if(state.runtimeMode!=='api'){ renderCompanyOptions(demoCompanies,false); configureSuperAdminCompanyPanel(false,true); openErpDialog(elements.companyDialog); return; }
  const submit=elements.loginForm.querySelector('[type="submit"]'); submit.disabled=true; submit.firstChild.textContent='Conectando ';
  try {
    const login=await apiRequest('/api/v1/auth/login',{method:'POST',body:JSON.stringify({correo:email,password:elements.loginPassword.value})});
    sessionStorage.setItem(uiStorage.apiToken,login.token); state.pendingName=login.nombreCompleto;state.pendingSuperAdmin=Boolean(login.esSuperAdministrador);
    const companies=await apiRequest('/api/v1/companies');
    if(!companies.length&&!state.pendingSuperAdmin) throw new Error('El usuario no tiene empresas activas asignadas.');
    renderCompanyOptions(companies,true);configureSuperAdminCompanyPanel(state.pendingSuperAdmin,companies.length>0);openErpDialog(elements.companyDialog);
  } catch(error) { sessionStorage.removeItem(uiStorage.apiToken); elements.loginError.textContent=`No fue posible ingresar a la API. ${error.message}`; elements.loginError.hidden=false; }
  finally { submit.disabled=false; submit.firstChild.textContent='Continuar '; }
}

async function saveManualDraft(event) {
  event.preventDefault(); hideError();const intent=event.submitter?.value||'draft';
  const lines = collectManualLines();
  if (!lines.length || lines.some((line) => !line.description || line.quantity <= 0)) return showError('Completa la descripción y una cantidad mayor que cero en todas las líneas.');
  if(lines.some(line=>line.discount>line.gross+line.charge)) return showError('El descuento de una línea no puede superar su valor bruto más los cargos.');
  if(lines.some(line=>line.retention>line.net+line.tax)) return showError('La retención de una línea no puede superar su base más impuestos.');
  const needsWarehouse = lines.some((line) => line.classification === 'inventory');
  if (needsWarehouse && !elements.manualWarehouse.value) return showError('Selecciona la bodega para las líneas que afectan inventario.');
  const isApiManual=state.runtimeMode==='api'&&state.erpSession?.api&&['goods','services'].includes(state.registrationMode);
  if(isApiManual){
    if(!state.apiContext) return showError('Espera a que terminen de cargar los maestros de la empresa.');
    if(needsWarehouse&&!elements.manualPeriod.value) return showError('Selecciona el periodo de inventario.');
    if(state.registrationMode==='goods'&&!lines.some(line=>line.classification==='inventory')) return showError('La entrada manual de mercancía debe contener al menos una línea inventariable.');
    if(state.registrationMode==='services'&&lines.some(line=>line.classification!=='service')) return showError('La causación de servicios solo admite líneas de servicio o gasto. Para una factura mixta usa Entrada manual.');
    if(lines.some(line=>['inventory','service'].includes(line.classification)&&!line.articleId)) return showError('Selecciona el artículo o concepto interno de todas las líneas de mercancía y servicio.');
    for(const line of lines.filter(x=>x.classification==='inventory')){
      if(line.lot&&!line.article?.lot) return showError(`El artículo ${line.article?.code||line.description} no está configurado para manejar lotes.`);
      if(line.expiry&&!line.lot) return showError(`La fecha de vencimiento de ${line.article?.code||line.description} requiere un número de lote.`);
      if(line.article?.expiry&&(!line.lot||!line.expiry)) return showError(`El artículo ${line.article.code} requiere lote y fecha de vencimiento.`);
      if(line.article?.serial){
        if(!Number.isInteger(line.quantity)||line.serials.length!==line.quantity) return showError(`El artículo ${line.article.code} requiere ${line.quantity} unidad(es) serializada(s), una por cada unidad recibida.`);
        if(line.serials.some(x=>!x.serial&&!x.motor&&!x.chassis&&!x.vin)) return showError(`Completa al menos serial, motor, chasis o VIN para cada unidad de ${line.article.code}.`);
      } else if(line.serials.length) return showError(`El artículo ${line.article?.code||line.description} no está configurado para manejar seriales.`);
    }
  }
  const draft = {
    id: crypto.randomUUID ? crypto.randomUUID() : String(Date.now()),
    createdAt: new Date().toISOString(),
    supplier: $('#manualSupplier').value.trim(), nit: $('#manualNit').value.trim().replace(/[^0-9]/g,''),documentType:$('#manualDocumentType').value,invoiceNumber: $('#manualInvoiceNumber').value.trim(),
    issueDate: $('#manualIssueDate').value, dueDate: $('#manualDueDate').value, paymentCondition:elements.manualPaymentCondition.value,creditDays:elements.manualPaymentCondition.value==='CREDITO'?Number(elements.manualCreditDays.value):0,warehouse: needsWarehouse ? elements.manualWarehouse.value : '',warehouseName:needsWarehouse?elements.manualWarehouse.selectedOptions[0]?.textContent:'No aplica',period:needsWarehouse?elements.manualPeriod.value:'',
    lines, total: lines.reduce((sum, line) => sum + line.total, 0), status: 'draft', source: 'manual',
  };
  state.manualDraft=draft;
  if(isApiManual){
    const submit=event.submitter;elements.manualDraftButton.disabled=true;elements.manualPostButton.disabled=true;const originalText=submit.textContent;submit.textContent=intent==='post'?'Guardando y procesando…':'Guardando borrador…';
    try{
      const result=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents`,{method:'POST',body:JSON.stringify(buildManualSupplierDocumentPayload(draft))});
      const current=await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/supplier-documents/${result.documentoProveedorId}`);
      let receiptId=current.recepcionMercanciaId;
      if(!receiptId&&!current.causacionServicioId){
        const prepared=await prepareSupplierDocumentForReceipt(result.documentoProveedorId,{hasInventory:needsWarehouse,hasServices:lines.some(x=>x.classification==='service'),bodegaId:draft.warehouse,periodoInventarioId:draft.period,fechaContable:draft.issueDate,numeroDocumento:draft.invoiceNumber});
        receiptId=prepared.recepcionMercanciaId;
      }
      if(intent==='post'&&receiptId&&current.recepcionEstado!=='CONTABILIZADA'){
        await apiRequest(`/api/v1/companies/${state.erpSession.company.id}/receipts/${receiptId}/post`,{method:'POST',body:JSON.stringify({correlationId:crypto.randomUUID?crypto.randomUUID():null})});
      }
      elements.manualFormStatus.textContent=intent==='post'?(receiptId?'Entrada guardada y contabilizada':'Causación guardada y preparada'):(receiptId?'Borrador preparado para recepción física':'Borrador guardado en SQL Server');
      showSuccess(intent==='post'?(receiptId?'Entrada contabilizada con sus seriales.':'Causación preparada para asignación contable.'):(receiptId?'Borrador preparado para recepción física. El auxiliar ya puede verlo.':'Borrador guardado. Puedes recuperarlo en Entradas guardadas.'));
      await refreshManualWorkflow(result.documentoProveedorId,receiptId);
    }
    catch(error){showError(`No fue posible guardar la entrada manual. ${error.message}`);}
    finally{elements.manualDraftButton.disabled=false;elements.manualPostButton.disabled=false;submit.textContent=originalText;}
    return;
  }
  const drafts = JSON.parse(localStorage.getItem('nexo.purchaseDrafts') || '[]');
  drafts.push(draft); localStorage.setItem('nexo.purchaseDrafts', JSON.stringify(drafts));
  elements.manualFormStatus.textContent = `Borrador guardado · ${new Date().toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit' })}`;
  renderManualDraft(draft);
}

$('#manualIssueDate').value = new Date().toISOString().slice(0, 10);
function syncManualPaymentFields(){const credit=elements.manualPaymentCondition.value==='CREDITO';elements.manualCreditDaysField.hidden=!credit;if(credit){elements.manualCreditDays.value=String(Math.max(Number(elements.manualCreditDays.value)||30,1));$('#manualDueDate').value=datePlusDays($('#manualIssueDate').value,Number(elements.manualCreditDays.value));}else{$('#manualDueDate').value=$('#manualIssueDate').value;}}
elements.manualPaymentCondition.addEventListener('change',syncManualPaymentFields);elements.manualCreditDays.addEventListener('input',syncManualPaymentFields);$('#manualIssueDate').addEventListener('change',syncManualPaymentFields);syncManualPaymentFields();
document.querySelectorAll('[data-registration-mode]').forEach((button) => button.addEventListener('click', () => setRegistrationMode(button.dataset.registrationMode)));
elements.savedPurchasesNav.addEventListener('click',showSavedPurchases);
elements.refreshSavedPurchases.addEventListener('click',()=>void refreshSavedPurchases());
elements.savedPurchasesSearch.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();void refreshSavedPurchases();}});
elements.savedPurchasesState.addEventListener('change',()=>void refreshSavedPurchases());
elements.savedPurchasesTable.addEventListener('click',event=>{const button=event.target.closest('[data-saved-purchase-id]');if(button)void openSavedPurchase(Number(button.dataset.savedPurchaseId));});
elements.inventoryNav.addEventListener('click',()=>showInventoryView(isInventoryViewAllowed(state.inventoryView)?state.inventoryView:firstAllowedInventoryView()||'receiving'));
document.querySelectorAll('[data-inventory-view]').forEach(button=>button.addEventListener('click',()=>showInventoryView(button.dataset.inventoryView)));
$('#refreshInventory').addEventListener('click',()=>void refreshInventory());
elements.inventorySearch.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();void refreshInventory();}});
elements.inventoryWarehouse.addEventListener('change',()=>void refreshInventory());
elements.inventoryTable.addEventListener('click',event=>{const button=event.target.closest('[data-warehouse-receipt-id]');if(button)void openWarehouseReceipt(Number(button.dataset.warehouseReceiptId));});
$('#addManualLine').addEventListener('click', () => addManualLine());
elements.manualForm.addEventListener('submit', saveManualDraft);

elements.browseButton.addEventListener('click', (event) => { event.stopPropagation(); elements.fileInput.click(); });
elements.dropZone.addEventListener('click', (event) => {
  if (event.target !== elements.fileInput) elements.fileInput.click();
});
elements.dropZone.addEventListener('keydown', (event) => { if (event.key === 'Enter' || event.key === ' ') elements.fileInput.click(); });
elements.fileInput.addEventListener('click', () => { elements.fileInput.value = ''; });
elements.fileInput.addEventListener('change', () => handleFile(elements.fileInput.files[0]));
['dragenter', 'dragover'].forEach((name) => elements.dropZone.addEventListener(name, (event) => { event.preventDefault(); elements.dropZone.classList.add('dragging'); }));
['dragleave', 'drop'].forEach((name) => elements.dropZone.addEventListener(name, (event) => { event.preventDefault(); elements.dropZone.classList.remove('dragging'); }));
elements.dropZone.addEventListener('drop', (event) => handleFile(event.dataTransfer.files[0]));
elements.analyzeButton.addEventListener('click', analyze);
elements.exampleButton.addEventListener('click', () => { elements.xmlInput.value = exampleXml; state.fileName = 'factura-ejemplo.xml'; elements.inputStatus.textContent = 'Ejemplo de factura cargado'; analyze(); });
$('#exportJson').addEventListener('click', () => download('datos-xml.json', JSON.stringify(state.json, null, 2), 'application/json'));
$('#exportCsv').addEventListener('click', exportCsv);
$('#exportExcel').addEventListener('click', exportExcel);

elements.loginForm.addEventListener('submit', beginLocalLogin);
$('#togglePassword').addEventListener('click', () => {
  const show = elements.loginPassword.type === 'password';
  elements.loginPassword.type = show ? 'text' : 'password';
  $('#togglePassword').textContent = show ? 'Ocultar' : 'Ver';
  $('#togglePassword').setAttribute('aria-label', show ? 'Ocultar contraseña' : 'Mostrar contraseña');
});
$('#companyOptions').addEventListener('click',(event)=>{const option=event.target.closest('.company-option');if(option)selectCompany(option);});
elements.companyCreateForm.addEventListener('submit',createCompanyAsSuperAdmin);
document.querySelectorAll('[data-close-dialog]').forEach((button) => button.addEventListener('click', () => closeErpDialog($(`#${button.dataset.closeDialog}`))));
elements.companySwitcher.addEventListener('click', () => void openCompanyManager());
$('#companiesAdminNav').addEventListener('click',()=>void openCompanyManager());
elements.securityAdminNav.addEventListener('click',()=>showSecurityView(state.securityView));
document.querySelectorAll('[data-security-view]').forEach(button=>button.addEventListener('click',()=>showSecurityView(button.dataset.securityView)));
elements.addSecurityRecord.addEventListener('click',()=>state.securityView==='users'?openSecurityUser():openSecurityRole());
elements.securityTable.addEventListener('click',event=>{const button=event.target.closest('[data-security-action]');if(!button||!state.securityData)return;const id=Number(button.dataset.id);if(button.dataset.securityAction==='edit-user')openSecurityUser(state.securityData.users.find(x=>x.usuarioId===id));else if(button.dataset.securityAction==='password')openSecurityPassword(state.securityData.users.find(x=>x.usuarioId===id));else if(button.dataset.securityAction==='edit-role')openSecurityRole(state.securityData.roles.find(x=>x.rolId===id));});
elements.securityUserForm.addEventListener('submit',saveSecurityUser);
elements.securityRoleForm.addEventListener('submit',saveSecurityRole);
elements.securityPasswordForm.addEventListener('submit',saveSecurityPassword);
elements.runtimeBadge.addEventListener('click', () => {
  updateRuntimeMode(state.runtimeMode, false);
  openErpDialog(elements.environmentDialog);
});
elements.environmentForm.addEventListener('change', (event) => {
  if (event.target.name !== 'runtimeMode') return;
  elements.environmentMessage.textContent = event.target.value === 'api'
    ? 'Al volver a iniciar sesión, usarás empresas, maestros y registros reales de SQL Server.'
    : 'Los archivos XML y borradores permanecerán únicamente en este equipo.';
});
elements.environmentForm.addEventListener('submit', (event) => {
  event.preventDefault();
  const selected = new FormData(elements.environmentForm).get('runtimeMode');
  updateRuntimeMode(selected);
  closeErpDialog(elements.environmentDialog);
});
document.querySelectorAll('[data-master-view]').forEach((button) => button.addEventListener('click', () => showMasterView(button.dataset.masterView)));
elements.addMasterRecord.addEventListener('click',()=>openMasterForm());
elements.masterTable.addEventListener('click',(event)=>{const button=event.target.closest('[data-master-article-action]');if(!button)return;const article=findById(getCompanyMasterData().data.articles,button.dataset.id);if(button.dataset.masterArticleAction==='edit')openMasterForm(article);else if(button.dataset.masterArticleAction==='delete')void deleteMasterArticle(article);});
elements.masterRecordForm.addEventListener('submit', saveMasterRecord);
elements.masterSearch.addEventListener('input', renderMasterView);
elements.logoutButton.addEventListener('click', leaveErp);
setupCollapsibleNavigation();
initializeErpUi();
