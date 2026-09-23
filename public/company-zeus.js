/* Las credenciales solo viven en este formulario; nunca en storage ni en el listado. */
function companyZeusFields(form,record,token){
  const section=document.createElement('fieldset');section.className='company-zeus-fields wide';
  const legend=document.createElement('legend');legend.textContent='Conexión Zeus';section.append(legend);
  const enableLabel=document.createElement('label'),enable=document.createElement('input');enable.type='checkbox';enableLabel.append(enable,document.createTextNode(' Configurar conexión Zeus'));section.append(enableLabel);
  const grid=document.createElement('div');grid.className='company-zeus-grid';section.append(grid);
  const inputs={};
  for(const [key,label,max,type] of [['servidor','Servidor SQL',150,'text'],['baseDatos','Base de datos Zeus',128,'text'],['usuarioSql','Usuario SQL de conexión',128,'text'],['password','Contraseña SQL',1024,'password'],['usuarioContable','Usuario contable de Zeus',20,'text']]){
    const wrap=document.createElement('label'),caption=document.createElement('span'),input=document.createElement('input');caption.textContent=label;input.type=type;input.maxLength=max;input.autocomplete=type==='password'?'new-password':'off';wrap.append(caption,input);grid.append(wrap);inputs[key]=input;
  }
  const trustLabel=document.createElement('label'),trust=document.createElement('input');trust.type='checkbox';trustLabel.append(trust,document.createTextNode(' Confiar en el certificado SQL del servidor'));grid.append(trustLabel);
  const test=document.createElement('button');test.type='button';test.className='button secondary';test.textContent='Probar conexión';
  const message=document.createElement('p');message.className='wide';message.setAttribute('role','status');section.append(test,message);form.append(section);
  let loaded=!record,dirty=false,version=0,versionConfiguracion=0,testing=false;
  const current=()=>token===apiToken()&&state.erpSession?.superAdmin&&form.isConnected;
  function update(){grid.hidden=test.hidden=!enable.checked;for(const [key,input] of Object.entries(inputs)){input.disabled=!enable.checked||!loaded;input.required=enable.checked&&key!=='password';}trust.disabled=!enable.checked||!loaded;test.disabled=!loaded||testing;}
  enable.onchange=()=>{dirty=true;update();};section.addEventListener('input',()=>{dirty=true;message.textContent='';});update();
  function payload(){return {servidor:inputs.servidor.value.trim(),baseDatos:inputs.baseDatos.value.trim(),usuarioSql:inputs.usuarioSql.value.trim(),password:inputs.password.value||null,usuarioContable:inputs.usuarioContable.value.trim(),confiarCertificado:trust.checked,version,versionConfiguracion};}
  test.onclick=async()=>{
    if(testing||!current())return;
    testing=true;update();message.textContent='Comprobando conexión…';
    try{const result=await apiRequest(`/api/v1/admin/companies/${record?.id||0}/zeus-connection/test`,{method:'POST',body:JSON.stringify(payload())});if(current())message.textContent=result.contratoDisponible?`Conexión correcta a ${result.baseDatos}. No se contabilizó nada.`:`Conecta a ${result.baseDatos}, pero faltan objetos o permisos del contrato Zeus.`;}
    catch(e){if(current())message.textContent=e.message;}finally{testing=false;if(current())update();}
  };
  if(record){
    enable.disabled=true;message.textContent='Consultando configuración Zeus…';
    apiRequest(`/api/v1/admin/companies/${record.id}/zeus-connection`).then(data=>{
      if(!current())return;
      for(const key of ['servidor','baseDatos','usuarioSql','usuarioContable'])inputs[key].value=data[key]||'';
      trust.checked=data.confiarCertificado;version=data.version;versionConfiguracion=data.versionConfiguracion;
      enable.checked=data.origen!=='SIN_CONFIGURAR';enable.disabled=enable.checked;loaded=true;
      inputs.password.placeholder=data.tienePassword?'Vacía para conservar la contraseña':'';
      message.textContent=data.origen==='SERVIDOR'?'Conexión actual del servidor. Al guardar cambios se administrará desde aquí.':'';update();
    }).catch(e=>{if(current()){message.textContent=e.message;enable.disabled=true;}});
  }
  return {read(){if(testing)throw new Error('Espera a que termine la prueba de conexión.');if(!enable.checked||!dirty)return null;if(!loaded)throw new Error('La configuración Zeus todavía no está disponible.');return payload();},clear(){inputs.password.value='';}};
}
