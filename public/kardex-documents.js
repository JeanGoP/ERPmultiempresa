/* Consulta del documento de origen sin abandonar ni reconstruir el Kardex. */
(() => {
  const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const quantity=value=>new Intl.NumberFormat('es-CO',{maximumFractionDigits:6}).format(value||0);
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',maximumFractionDigits:2}).format(value||0);
  const date=value=>/^\d{4}-\d{2}-\d{2}/.test(String(value||''))?String(value).slice(0,10).split('-').reverse().join('/'):'—';
  const labels={FACTURA_VENTA:'Factura de venta',RECEPCION_MERCANCIA:'Entrada de mercancía',TRASLADO:'Traslado',DEVOLUCION_PROVEEDOR:'Devolución a proveedor',DEVOLUCION_VENTA:'Devolución de venta',REVERSA_MOVIMIENTO:'Reversión de inventario'};
  const id=value=>Number.isSafeInteger(Number(value))&&Number(value)>0?Number(value):null;
  const fields=values=>`<dl class="kardex-document-fields">${values.map(([label,value])=>`<div><dt>${esc(label)}</dt><dd>${esc(value||'—')}</dd></div>`).join('')}</dl>`;
  const party=(label,name,identification,contact=[])=>`<section class="kardex-document-party"><span>${esc(label)}</span><h3>${esc(name)}</h3><p>${esc([identification,...contact].filter(Boolean).join(' · '))}</p></section>`;
  const identifiers=units=>(units||[]).map(unit=>[['Chasis',unit.chasis],['VIN',unit.vin],['Serial',unit.serial],['Motor',unit.motor]].filter(([,value])=>value).map(([name,value])=>`${name} ${value}`).join(' · ')).filter(Boolean).map(value=>`<small>${esc(value)}</small>`).join('');
  const table=(headers,rows)=>`<div class="kardex-document-table"><table><thead><tr>${headers.map(value=>`<th scope="col">${esc(value)}</th>`).join('')}</tr></thead><tbody>${rows.join('')||`<tr><td colspan="${headers.length}">Sin líneas.</td></tr>`}</tbody></table></div>`;
  const totals=values=>`<div class="kardex-document-totals">${values.map(([name,value])=>`<div><span>${esc(name)}</span><strong>${money(value)}</strong></div>`).join('')}</div>`;
  const note=value=>value?`<section class="kardex-document-note"><h3>Observaciones</h3><p>${esc(value)}</p></section>`:'';

  function source(entry){
    const type=entry.tipoDocumentoOrigen,documentId=id(entry.documentoOrigenId);
    if(type==='FACTURA_VENTA'&&documentId)return {kind:'sale',path:`sales-invoices/${documentId}`};
    if(type==='RECEPCION_MERCANCIA'&&id(entry.documentoProveedorId))return {kind:'purchase',path:`supplier-documents/${id(entry.documentoProveedorId)}/detail`};
    if(type==='TRASLADO'&&documentId)return {kind:'transfer',path:`transfers/${documentId}`};
    return null;
  }
  function saleHtml(data){
    const h=data.header;
    const concepts=(data.conceptos||[]).filter(item=>item.mostrarEnCuerpo??item.ubicacionFormato!=='TOTALES');
    return party('Cliente',h.cliente,h.identificacion,[h.telefonoCliente,h.ciudadCliente])
      +fields([['Fecha',date(h.fecha)],['Sucursal',[h.sucursalCodigo,h.sucursal].filter(Boolean).join(' · ')],['Modalidad',h.modalidad],['Estado Zeus',h.zeusEstado]])
      +'<h3>Artículos</h3>'+table(['Artículo','Descripción','Bodega','Cantidad','Precio con IVA','Total'],(data.articulos||[]).map(item=>`<tr><td>${esc(item.codigo)}</td><td>${esc(item.descripcion)}${identifiers(item.unidades)}</td><td>${esc([item.bodegaCodigo,item.bodega].filter(Boolean).join(' · '))}</td><td class="number">${quantity(item.cantidad)}</td><td class="number">${money(item.precio)}</td><td class="number">${money(Number(item.base||0)+Number(item.iva||0))}</td></tr>`))
      +(concepts.length?'<h3>Conceptos</h3>'+table(['Concepto','Valor'],concepts.map(item=>`<tr><td>${esc(item.nombre)}</td><td class="number">${money(item.valor)}</td></tr>`)):'')
      +totals([['Total contable',h.total],['Anticipos aplicados',h.anticipo],['Saldo',h.saldo]])+note(h.observacion);
  }
  function purchaseHtml(data){
    const h=data.documento;
    return party('Proveedor',h.proveedor,h.proveedorIdentificacion)
      +fields([['Documento del proveedor',`${h.tipoDocumento} ${h.numeroDocumento}`],['Fecha de factura',date(h.fechaDocumento)],['Fecha contable',date(h.recepcionFechaContable)],['Condición de pago',h.condicionPago==='CREDITO'?`Crédito · ${h.diasCredito} días`:'Contado'],['Vencimiento',date(h.fechaVencimiento)],['Estado',h.recepcionEstado||h.estado]])
      +'<h3>Artículos y servicios</h3>'+table(['Artículo','Descripción','Bodega','Cantidad','Precio unitario','Total'],(data.lineas||[]).map(item=>`<tr><td>${esc(item.codigoArticulo||item.codigoExterno||'—')}</td><td>${esc(item.descripcion)}${identifiers(item.seriales)}</td><td>${esc([item.bodegaCodigo,item.bodega].filter(Boolean).join(' · ')||'—')}</td><td class="number">${quantity(item.cantidad)}</td><td class="number">${money(item.precioUnitario)}</td><td class="number">${money(item.totalNeto)}</td></tr>`))
      +totals([['Subtotal',h.subtotalBruto],['Impuestos',h.impuestoTotal],['Total del documento',h.totalPagar]]);
  }
  function movementHtml(entry){
    return fields([['Fecha contable',date(entry.fechaContable)],['Movimiento',entry.tipoMovimiento],['Documento',entry.numeroDocumento],['Bodega',entry.bodega],['Artículo',entry.codigo],['Descripción',entry.descripcion],['Entrada',quantity(entry.entrada)],['Salida',quantity(entry.salida)],['Costo unitario',money(entry.costoUnitario)],['Valor',money(entry.valorMovimiento)]])
      +((entry.unidades||[]).length?`<section class="kardex-document-note"><h3>Seriales e identificadores</h3>${identifiers(entry.unidades)}</section>`:'');
  }

  let active=null;
  function close(){active?.close();}
  function open(entry,trigger){
    const company=state.erpSession?.company;
    if(!company?.id)return;
    close();
    const companyId=String(company.id),documentSource=source(entry);
    const dialog=document.createElement('dialog');dialog.className='erp-dialog kardex-document-dialog';
    dialog.setAttribute('aria-labelledby','kardexDocumentTitle');
    dialog.innerHTML=`<header class="dialog-heading"><div><span class="dialog-kicker">${documentSource?'Documento de origen':'Detalle del movimiento'}</span><h2 id="kardexDocumentTitle"></h2><p data-movement-context></p></div><button type="button" class="dialog-close" data-close-document aria-label="Cerrar y volver al Kardex">×</button></header><div class="kardex-document-body" data-document-body aria-busy="true"><p role="status">Cargando documento…</p></div><footer class="kardex-document-footer"><p role="status" data-document-status></p><button type="button" class="button secondary" data-print-document hidden>Imprimir documento</button><button type="button" class="button primary" data-close-document>Volver al Kardex</button></footer>`;
    const title=dialog.querySelector('h2'),body=dialog.querySelector('[data-document-body]'),status=dialog.querySelector('[data-document-status]'),print=dialog.querySelector('[data-print-document]');
    title.textContent=[labels[entry.tipoDocumentoOrigen],entry.numeroDocumento].filter(Boolean).join(' · ')||'Movimiento de inventario';
    dialog.querySelector('[data-movement-context]').textContent=`${date(entry.fechaContable)} · ${entry.bodega||''}`;
    const current=()=>active===dialog&&dialog.open&&String(state.erpSession?.company?.id)===companyId;
    dialog.querySelectorAll('[data-close-document]').forEach(button=>button.addEventListener('click',()=>dialog.close()));
    dialog.addEventListener('close',()=>{const restoreFocus=active===dialog;if(restoreFocus)active=null;dialog.remove();if(restoreFocus&&trigger?.isConnected&&String(state.erpSession?.company?.id)===companyId)trigger.focus({preventScroll:true});},{once:true});
    active=dialog;document.body.append(dialog);dialog.showModal();
    if(!documentSource){body.innerHTML=movementHtml(entry);body.removeAttribute('aria-busy');return;}
    void (async()=>{
      try{
        const data=await apiRequest(`/api/v1/companies/${companyId}/${documentSource.path}`,{cache:'no-store'});
        if(!current()){if(active===dialog)dialog.close();return;}
        if(documentSource.kind==='sale'){
          title.textContent=`Factura de venta · ${data.header.numero}`;body.innerHTML=saleHtml(data);
          print.onclick=()=>{try{window.salesInvoicePrint.print(data,company);}catch(error){status.textContent=error.message;}};print.hidden=false;
        }else if(documentSource.kind==='purchase'){
          title.textContent=`Entrada · ${data.documento.recepcionNumero||entry.numeroDocumento}`;body.innerHTML=purchaseHtml(data);
          if((data.lineas||[]).some(item=>item.clasificacion==='INVENTARIO')){print.onclick=()=>{try{window.purchaseEntryPrint.print(data,company);}catch(error){status.textContent=error.message;}};print.hidden=false;}
        }else{
          title.textContent=`${data.trasladoOriginalId?'Reversión de traslado':'Traslado'} · ${data.numero}`;
          body.innerHTML=window.transferDocuments.receiptHtml(data);
          if(['RECIBIDO','REVERTIDO'].includes(data.estado)&&data.lineas?.length){print.onclick=()=>{try{window.transferDocuments.print(data);}catch(error){status.textContent=error.message;}};print.hidden=false;}
        }
      }catch(error){
        if(!current())return;
        body.replaceChildren();const message=document.createElement('p');message.className='kardex-document-error';message.setAttribute('role','alert');
        message.textContent=error.status===403?'Tu usuario no tiene permiso para consultar este documento.':error.status===404?'No se encontró el documento de origen en esta empresa.':`No fue posible consultar el documento. ${error.message}`;
        body.append(message);
      }finally{if(current())body.removeAttribute('aria-busy');}
    })();
  }
  function attach(table,rows){
    const tableRows=table.tBodies?.[0]?.rows;if(!tableRows)return;
    rows.forEach((entry,index)=>{
      if(!entry.movimientoInventarioId)return;
      for(const column of [1,2]){
        const cell=tableRows[index]?.cells[column];if(!cell)continue;
        const button=document.createElement('button');button.type='button';button.className='kardex-document-link';button.textContent=column===1?entry.tipoMovimiento:entry.numeroDocumento;
        button.setAttribute('aria-haspopup','dialog');button.setAttribute('aria-label',`Consultar ${entry.numeroDocumento} desde el Kardex`);
        button.addEventListener('click',()=>open(entry,button));cell.replaceChildren(button);
      }
    });
  }
  window.kardexDocuments={attach,open,close};
})();
