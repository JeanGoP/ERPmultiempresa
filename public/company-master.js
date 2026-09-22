/* Maestro global, exclusivo del superadministrador. No cambia la empresa operativa. */
let companyMasterRows=[],companyMasterQuery='',companyMasterStatus='',companyMasterRequest=0;
function configureCompanyMasterWorkspace(companies){
  const panel=elements.securityModule;
  panel.querySelector('.security-heading h1').textContent=companies?'Empresas':'Usuarios y permisos';
  panel.querySelector('.security-heading .lede').textContent=companies?'Administra las empresas del sistema.':'Controla los usuarios y permisos de la empresa activa.';
  panel.querySelector('.module-state small').textContent=companies?'MAESTRO GLOBAL':'EMPRESA ACTIVA';
  panel.querySelector('.security-tabs').hidden=companies;
  elements.securityStats.hidden=companies;
}
document.querySelector('.erp-nav').addEventListener('click',event=>{if(event.target.closest('button')&&!event.target.closest('#companiesAdminNav'))elements.companiesAdminNav.classList.remove('active');},true);
function companyMasterCurrent(token){return state.erpSession?.superAdmin&&apiToken()===token&&state.securityView==='companies'&&!elements.securityModule.hidden;}
async function loadCompanyMaster(){
  if(!state.erpSession?.superAdmin)return;
  const token=apiToken(),request=++companyMasterRequest;
  elements.securityStatus.textContent='Consultando empresas…';elements.securityNotice.hidden=true;
  try{
    const rows=await apiRequest('/api/v1/admin/companies');
    if(!companyMasterCurrent(token)||request!==companyMasterRequest)return;
    companyMasterRows=rows;renderCompanyMaster();
  }catch(error){if(companyMasterCurrent(token)&&request===companyMasterRequest){companyMasterRows=[];renderCompanyMaster();elements.securityNotice.textContent=error.message;elements.securityNotice.hidden=false;}}
}
function renderCompanyMaster(){
  if(!state.erpSession?.superAdmin||state.securityView!=='companies')return;
  elements.securityViewKicker.textContent='SEGURIDAD · MAESTROS';elements.securityViewTitle.textContent='Empresas';elements.securityViewSubtitle.textContent='Compañías registradas en el ERP.';
  elements.addSecurityRecord.textContent='＋ Nueva empresa';elements.addSecurityRecord.hidden=false;
  elements.securityStats.replaceChildren();elements.securityStatus.textContent=companyMasterRows.length+' empresas';
  elements.companiesAdminNav.classList.add('active');elements.securityAdminNav.classList.remove('active');
  document.querySelectorAll('[data-security-view]').forEach(x=>x.classList.remove('active'));
  document.querySelector('.breadcrumb span').textContent='Seguridad';elements.breadcrumbCurrent.textContent='Empresas';
  const toolbar=document.createElement('div');toolbar.className='workflow-controls';
  const search=document.createElement('input');search.type='search';search.placeholder='Buscar por código, NIT o razón social';search.value=companyMasterQuery;search.setAttribute('aria-label','Buscar empresa');
  const status=document.createElement('select');status.setAttribute('aria-label','Estado de empresa');[['','Todos los estados'],['active','Activas'],['inactive','Inactivas']].forEach(([v,t])=>status.add(new Option(t,v)));status.value=companyMasterStatus;
  const result=document.createElement('div');result.className='zeus-scroll';
  const renderRows=()=>{
    const query=companyMasterQuery.trim().toLocaleLowerCase('es-CO');
    const rows=companyMasterRows.filter(x=>(!query||[x.codigo,x.nit,x.razonSocial].join(' ').toLocaleLowerCase('es-CO').includes(query))&&(!companyMasterStatus||x.activa===(companyMasterStatus==='active')));
    const table=buildDataTable(['Código','NIT','Razón social','Moneda','Marco contable','Estado','Acciones'],rows.map(x=>[x.codigo,x.nit+(x.digitoVerificacion?'-'+x.digitoVerificacion:''),x.razonSocial,x.monedaFuncional,x.marcoContable,x.activa?'Activa':'Inactiva','']));
    table.querySelectorAll('tbody tr').forEach((tr,i)=>{if(!rows[i])return;const button=document.createElement('button');button.type='button';button.className='button secondary';button.textContent='Editar';button.onclick=()=>openCompanyMasterForm(rows[i]);tr.lastElementChild.append(button);});
    result.replaceChildren(table);elements.securityStatus.textContent=rows.length+' de '+companyMasterRows.length+' empresas';
  };
  search.oninput=()=>{companyMasterQuery=search.value;renderRows();};status.onchange=()=>{companyMasterStatus=status.value;renderRows();};
  const refresh=document.createElement('button');refresh.type='button';refresh.className='button secondary';refresh.textContent='Actualizar';refresh.onclick=()=>void loadCompanyMaster();
  toolbar.append(search,status,refresh);elements.securityTable.replaceChildren(toolbar,result);renderRows();
}
function openCompanyMasterForm(record=null){
  if(!state.erpSession?.superAdmin)return;
  const token=apiToken();const dialog=document.createElement('dialog');dialog.className='erp-dialog master-dialog';dialog.setAttribute('aria-label',record?'Editar empresa':'Nueva empresa');
  const heading=document.createElement('h2');heading.textContent=record?'Editar empresa':'Nueva empresa';
  const form=document.createElement('form');form.className='company-create-form';
  const field=(label,name,max,value,readOnly=false)=>{const wrap=document.createElement('label');const caption=document.createElement('span');caption.textContent=label;wrap.append(caption);const input=document.createElement('input');input.name=name;input.maxLength=max;input.required=name!=='digitoVerificacion';input.value=value||'';input.readOnly=readOnly;wrap.append(input);form.append(wrap);return input;};
  field('Código','codigo',20,record?.codigo);field('NIT','nit',20,record?.nit);field('Dígito de verificación','digitoVerificacion',1,record?.digitoVerificacion).pattern='[0-9]';field('Razón social','razonSocial',200,record?.razonSocial);
  field('Moneda funcional','monedaFuncional',3,record?.monedaFuncional||'COP',!!record);
  field('Zona horaria','zonaHoraria',80,record?.zonaHoraria||'America/Bogota',!!record);
  const marcoLabel=document.createElement('label');marcoLabel.textContent='Marco contable';const marco=document.createElement('select');marco.name='marcoContable';['GRUPO_1','GRUPO_2','GRUPO_3'].forEach(v=>marco.add(new Option(v.replace('_',' '),v)));marco.value=record?.marcoContable||'GRUPO_2';marco.disabled=!!record;marcoLabel.append(marco);form.append(marcoLabel);
  const error=document.createElement('p');error.className='login-error wide';error.setAttribute('role','alert');
  const actions=document.createElement('div');actions.className='saved-detail-actions wide';const cancel=document.createElement('button');cancel.type='button';cancel.className='button secondary';cancel.textContent='Cancelar';const save=document.createElement('button');save.type='submit';save.className='button primary';save.textContent=record?'Guardar cambios':'Crear empresa';actions.append(cancel,save);form.append(error,actions);dialog.append(heading,form);document.body.append(dialog);
  let busy=false;cancel.onclick=()=>dialog.close();dialog.addEventListener('cancel',e=>{if(busy)e.preventDefault();});dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  form.onsubmit=async event=>{
    event.preventDefault();if(busy)return;if(!state.erpSession?.superAdmin||token!==apiToken()){dialog.close();return;}
    const data=Object.fromEntries(new FormData(form));const payload=record?{codigo:data.codigo,nit:data.nit,digitoVerificacion:data.digitoVerificacion||null,razonSocial:data.razonSocial,version:record.version}:data;
    busy=true;save.disabled=cancel.disabled=true;error.textContent='';
    try{
      await apiRequest(record?'/api/v1/admin/companies/'+record.id:'/api/v1/companies',{method:record?'PUT':'POST',body:JSON.stringify(payload)});
      dialog.close();
      if(token!==apiToken()||!state.erpSession?.superAdmin)return;
      if(record&&String(state.erpSession.company.id)===String(record.id)){Object.assign(state.erpSession.company,{name:data.razonSocial.trim(),nit:'NIT '+data.nit.trim(),initials:initials(data.razonSocial)});localStorage.setItem(uiStorage.session,JSON.stringify(state.erpSession));renderErpSession();}
      await loadCompanyMaster();
      if(companyMasterCurrent(token)){elements.securityNotice.textContent=record?'Empresa actualizada.':'Empresa creada. La empresa de tu sesión no cambió.';elements.securityNotice.hidden=false;}
    }catch(e){error.textContent=e.message;}finally{busy=false;save.disabled=cancel.disabled=false;}
  };openErpDialog(dialog);
}
