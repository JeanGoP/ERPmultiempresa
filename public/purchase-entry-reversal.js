(() => {
  const permission='INVENTARIO.AJUSTE.REVERSAR';
  const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const reversed=entry=>entry.estado==='REVERTIDO'||entry.recepcionEstado==='REVERTIDA';
  const base=(company,id)=>`/api/v1/companies/${company}/supplier-documents/${id}`;
  const active=company=>String(state.erpSession?.company?.id)===company;
  const labelDate=value=>String(value||'').slice(0,10).split('-').reverse().join('/');
  const pending=state=>['PENDIENTE','ENVIANDO'].includes(state);

  function attach(container,detail,onChanged){
    const entry=detail.documento;
    if(!hasPermission(permission)||!entry.recepcionMercanciaId||!['CONTABILIZADA','REVERTIDA'].includes(entry.recepcionEstado))return;
    const company=String(state.erpSession.company.id),open=document.createElement('button');
    open.type='button';open.className=`button ${reversed(entry)?'secondary':'danger'}`;
    open.textContent=reversed(entry)?'Ver reversión':'Revertir entrada';
    open.addEventListener('click',()=>{if(active(company))void show(company,entry,onChanged);});
    container.append(open);
  }

  async function show(company,entry,onChanged){
    const dialog=document.createElement('dialog');
    dialog.className='erp-dialog purchase-entry-reversal';
    dialog.setAttribute('aria-labelledby','purchaseReversalTitle');
    dialog.innerHTML=`<header class="dialog-heading"><div><span class="dialog-kicker">COMPRAS</span><h2 id="purchaseReversalTitle">${reversed(entry)?'Reversión de entrada':'Revertir entrada'}</h2></div><button type="button" class="dialog-close" data-reversal-close aria-label="Cerrar">×</button></header>
      <div class="purchase-reversal-body"><div class="purchase-reversal-document"><strong>${escape(entry.numeroDocumento)}</strong><span>${escape(entry.proveedor)} · ${escape(entry.proveedorIdentificacion)}</span><span>${escape(entry.recepcionNumero||'Entrada de mercancía')}</span></div>
      <p role="status" data-reversal-notice>Consultando el estado de la entrada…</p><div data-reversal-content></div></div>`;
    document.body.append(dialog);dialog.showModal();
    const content=dialog.querySelector('[data-reversal-content]'),notice=dialog.querySelector('[data-reversal-notice]'),close=dialog.querySelector('[data-reversal-close]');
    let posting=false,pollTimer,attempts=0,version=0,notified=false;
    const current=()=>{if(!active(company)){dialog.close();return false;}return dialog.open;};
    const message=(text,error=false)=>{notice.textContent=text;notice.hidden=!text;notice.classList.toggle('error',error);};
    close.addEventListener('click',()=>dialog.close());
    dialog.addEventListener('cancel',event=>{if(posting)event.preventDefault();});
    dialog.addEventListener('close',()=>{clearTimeout(pollTimer);version++;dialog.remove();},{once:true});
    async function changed(){
      if(notified||!active(company))return;notified=true;
      try{await onChanged?.();}catch{if(current())message('La reversión quedó registrada. Actualiza el listado para consultar el documento.');}
    }

    function result(data){
      clearTimeout(pollTimer);content.replaceChildren();
      const info=document.createElement('section');info.className='purchase-reversal-result';
      const title=document.createElement('h3');title.textContent='Entrada revertida en Nexo';
      const details=document.createElement('p');details.textContent=[data.fechaContable&&`Fecha: ${labelDate(data.fechaContable)}`,data.motivo&&`Motivo: ${data.motivo}`].filter(Boolean).join(' · ');
      const zeus=document.createElement('p');zeus.textContent=data.zeus?.mensaje||'Consulta el estado del contrasiento en Zeus.';
      zeus.dataset.reversalZeus=data.zeus?.estado||'';
      const refresh=document.createElement('button');refresh.type='button';refresh.className='button secondary';refresh.textContent='Actualizar estado';
      refresh.addEventListener('click',()=>void load());
      info.append(title,details,zeus,refresh);content.append(info);message('');
      if(['RECHAZADO','INCIERTO'].includes(data.zeus?.estado)){
        const reconcile=data.zeus.estado==='INCIERTO',action=document.createElement('button');
        action.type='button';action.className='button secondary';
        action.textContent=reconcile?'Conciliar en Zeus sin reenviar':'Reintentar solo Zeus';
        action.addEventListener('click',async()=>{
          if(posting||!current())return;posting=true;action.disabled=refresh.disabled=close.disabled=true;
          message(reconcile?'Verificando el comprobante en Zeus…':'Registrando el reintento del contrasiento…');
          try{
            const next=await apiRequest(`${base(company,entry.documentoProveedorId)}/reversal/${reconcile?'reconcile':'retry'}`,{method:'POST',body:'{}'});
            if(current())result(next);
          }catch(error){if(current())message(error.message,true);}
          finally{posting=false;if(dialog.open)action.disabled=refresh.disabled=close.disabled=false;}
        });
        info.append(action);
      }
      if(pending(data.zeus?.estado)&&attempts++<20)pollTimer=setTimeout(()=>void load(),3000);
    }

    function form(){
      content.innerHTML=`<p class="purchase-reversal-explanation">Se registrarán los movimientos contrarios de inventario, seriales y cuenta por pagar. Si la entrada ya está contabilizada en Zeus, se enviará su contrasiento conservando el comprobante original.</p>
        <form><div class="purchase-reversal-date"><label>Fecha contable<input name="fecha" type="date" required></label><p data-reversal-period></p></div>
        <label>Motivo de la reversión<textarea name="motivo" rows="3" minlength="10" maxlength="500" required placeholder="Describe el error que deseas corregir"></textarea></label>
        <p class="purchase-reversal-limit">La operación se bloqueará si la mercancía ya fue vendida, trasladada o utilizada, o si la factura tiene pagos o procesos que deban resolverse antes.</p>
        <div class="purchase-reversal-actions"><button type="button" class="button secondary" data-reversal-cancel>Cancelar</button><button type="submit" class="button danger">Confirmar reversión</button></div></form>`;
      const form=content.querySelector('form'),date=form.elements.fecha,reason=form.elements.motivo,submit=form.querySelector('[type="submit"]'),cancel=form.querySelector('[data-reversal-cancel]'),period=content.querySelector('[data-reversal-period]');
      date.value=accountingToday();date.min=entry.recepcionFechaContable||entry.fechaDocumento||'';
      const validate=()=>{
        const match=receiptPeriodForDate(date.value);
        period.textContent=match?`Período: ${match.codigo}`:'Abre el período de esta fecha en Inventarios → Períodos de inventario.';
        date.setCustomValidity(match?'':'Escoge una fecha con período de inventario abierto.');
        submit.disabled=posting||!match;return match;
      };
      date.addEventListener('change',validate);cancel.addEventListener('click',()=>dialog.close());validate();
      form.addEventListener('submit',async event=>{
        event.preventDefault();if(posting||!current())return;
        const match=validate(),motivo=reason.value.trim();if(!match||!form.reportValidity())return;
        if(motivo.length<10){message('Escribe un motivo de al menos 10 caracteres.',true);reason.focus();return;}
        posting=true;submit.disabled=close.disabled=cancel.disabled=date.disabled=reason.disabled=true;
        message('Registrando la reversión…');
        try{
          const data=await apiRequest(`${base(company,entry.documentoProveedorId)}/reverse`,{method:'POST',body:JSON.stringify({periodoInventarioId:match.periodoInventarioId,fechaContable:date.value,motivo})});
          if(!current())return;
          if(data.yaExistia)await load();
          else result({...data,fechaContable:date.value,motivo});
          await changed();
        }catch(error){
          if(!current())return;
          if(error.status){message(error.message,true);}
          else{
            message('No se pudo confirmar el resultado. Consulta el estado antes de repetir la operación.',true);
            const refresh=document.createElement('button');refresh.type='button';refresh.className='button secondary';refresh.textContent='Consultar resultado';refresh.addEventListener('click',()=>void load());content.append(refresh);
            submit.dataset.uncertain='true';
          }
        }finally{
          posting=false;if(dialog.open){close.disabled=cancel.disabled=date.disabled=reason.disabled=false;if(submit.isConnected)submit.disabled=submit.dataset.uncertain==='true'||!receiptPeriodForDate(date.value);}
        }
      });
      message('');reason.focus();
    }

    async function load(){
      const request=++version;clearTimeout(pollTimer);
      try{
        const data=await apiRequest(`${base(company,entry.documentoProveedorId)}/reversal`,{cache:'no-store'});
        if(!current()||request!==version)return;
        if(!data.reversionId&&!state.apiContext){await loadApiCompanyContext();if(!current()||request!==version)return;}
        if(data.reversionId){result(data);if(!reversed(entry))await changed();}
        else if(reversed(entry)){message('La entrada figura revertida, pero no se encontró su registro de reversión.',true);}
        else if(!content.querySelector('form'))form();
      }catch(error){if(current()&&request===version)message(error.status===404?'Actualiza el backend para consultar y revertir entradas completas.':error.message,true);}
    }
    await load();
  }

  window.purchaseEntryReversal={attach};
})();
