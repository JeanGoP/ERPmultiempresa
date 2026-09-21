/* Cuentas de bodega: persistencia exclusiva en la API, por empresa. */
const warehouseAccountFields=[['inventario','Cuenta de inventario'],['ivaCompras','Cuenta de IVA en compras'],['ivaVentas','Cuenta de IVA en ventas'],['ivaDevolucionVentas','Cuenta de IVA de devolución en ventas'],['ingreso','Cuenta de ingreso'],['costoVenta','Cuenta de costo de venta'],['devolucionVenta','Cuenta de devolución en venta']];
function warehouseAccountsButton(warehouse){
  const button=document.createElement('button');button.type='button';button.className='button secondary';button.textContent='Configuración contable';
  button.addEventListener('click',async()=>{
    const company=String(state.erpSession?.company?.id),epoch=zeusUI.epoch;
    const current=()=>company===String(state.erpSession?.company?.id)&&epoch===zeusUI.epoch;
    const url=`/api/v1/companies/${company}/zeus/warehouses/${warehouse.id}/accounts`;
    button.disabled=true;let dialog;
    try{
      const result=await apiRequest(url);if(!current())return;
      const saved=result.configuracion;
      const changed=saved.version>0&&(saved.servidor.toLowerCase()!==result.servidor.toLowerCase()||saved.baseDatos.toLowerCase()!==result.baseDatos.toLowerCase());
      dialog=document.createElement('dialog');dialog.className='zeus-supplier-dialog warehouse-accounts-dialog';
      dialog.innerHTML=`<form><p class="eyebrow">BODEGAS · CONFIGURACIÓN CONTABLE</p><h2>${zeusEscape(warehouse.code)} · ${zeusEscape(warehouse.name)}</h2><p>Empresa: <strong>${zeusEscape(state.erpSession.company.name)}</strong><br>Plan de cuentas: <strong>${zeusEscape(result.baseDatos)}</strong></p>${changed?'<p class="zeus-notice error">Cambió el destino Zeus. Debes seleccionar nuevamente las siete cuentas.</p>':''}<p>Busca por código o nombre y selecciona una cuenta. Solo se admiten cuentas de detalle habilitadas y compatibles; no cuentas de cartera o bancos.</p><div class="warehouse-account-fields">${warehouseAccountFields.map(([key,label])=>`<label>${label}<input name="${key}" list="warehouse-chart" required autocomplete="off" placeholder="Código o nombre de cuenta" value="${changed?'':zeusEscape(saved.cuentas?.[key]||'')}"></label>`).join('')}</div><datalist id="warehouse-chart">${result.cuentas.map(a=>`<option value="${zeusEscape(a.codigo)}">${zeusEscape(a.codigo)} · ${zeusEscape(a.nombre)}</option>`).join('')}</datalist><p>Inventario e IVA de compras se aplicarán según la bodega de entrada. Las otras cinco cuentas quedan preparadas para ventas y devoluciones. Configura todas las bodegas de compras antes de preparar nuevos comprobantes.</p><p role="status" class="zeus-notice" hidden></p><div class="zeus-form-end"><button type="button" data-close class="button secondary">Cerrar</button><button type="submit" class="button primary" ${result.cuentas.length?'':'disabled'}>Guardar cuentas</button></div></form>`;
      document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove());dialog.querySelector('[data-close]').addEventListener('click',()=>dialog.close());
      const notice=dialog.querySelector('[role="status"]');
      if(!result.cuentas.length){notice.hidden=false;notice.textContent='Zeus no devolvió cuentas habilitadas compatibles. No es posible guardar.';}
      dialog.querySelector('form').addEventListener('submit',async event=>{
        event.preventDefault();if(!current()){dialog.close();return;}
        const form=event.currentTarget,submit=dialog.querySelector('[type="submit"]');if(submit.disabled||!form.reportValidity())return;
        const cuentas=Object.fromEntries(warehouseAccountFields.map(([key])=>[key,form.elements[key].value.trim()]));
        notice.hidden=false;
        if(Object.values(cuentas).some(code=>!result.cuentas.some(a=>a.codigo===code))){notice.textContent='Selecciona un código válido del listado de Zeus en cada campo.';notice.classList.add('error');return;}
        submit.disabled=true;notice.textContent='Validando y guardando cuentas…';
        try{
          await apiRequest(url,{method:'PUT',body:JSON.stringify({version:saved.version,versionEmpresa:result.versionEmpresa,cuentas})});
          if(!current()){dialog.close();return;}
          notice.classList.remove('error');notice.textContent='Cuentas guardadas. No se contabilizó ningún documento en Zeus.';
        }catch(error){notice.classList.add('error');notice.textContent=`${error.message} Cierra y vuelve a consultar antes de guardar otra vez.`;}
      });
      dialog.showModal();
    }catch(error){if(current())showMasterNotice(error.message,true);dialog?.remove();}
    finally{button.disabled=false;}
  });return button;
}
