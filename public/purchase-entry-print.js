/* Comprobante interno de entrada: refleja el estado persistido, no una factura del proveedor. */
(() => {
  const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const money=(value,currency)=>new Intl.NumberFormat('es-CO',{style:'currency',currency:currency||'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(value)||0);
  const table=(headers,rows)=>`<table><thead><tr>${headers.map(x=>`<th>${escape(x)}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table>`;
  function html(detail,company){
    const d=detail.documento,lines=detail.lineas.filter(x=>x.clasificacion==='INVENTARIO');
    const posted=d.recepcionEstado==='CONTABILIZADA';
    const status=posted?'ENTRADA CONTABILIZADA':d.recepcionEstado&&d.recepcionEstado!=='BORRADOR'?`${d.recepcionEstado} / NO CONTABILIZADA`:'BORRADOR / PENDIENTE DE CONTABILIZAR';
    const serials=lines.flatMap(x=>x.seriales.map(unit=>({line:x.numeroLinea,code:x.codigoArticulo||x.codigoExterno||'',...unit})));
    const inventoryTotal=lines.reduce((sum,x)=>sum+Number(x.totalNeto),0);
    return `<header><span class="print-kicker">${escape(status)}</span><h1>Entrada de mercancía</h1><div class="print-columns"><div><strong>${escape(company.name)}</strong><span>${escape(company.nit)}</span></div><div><strong>${escape(d.recepcionNumero||'Sin número de recepción')}</strong><span>Factura del proveedor: ${escape(d.tipoDocumento)} ${escape(d.numeroDocumento)}</span></div></div></header>
      <section class="print-meta"><div><small>Proveedor</small><strong>${escape(d.proveedor)}</strong><span>${escape(d.proveedorIdentificacion)}</span></div><div><small>Fecha factura</small><strong>${escape(d.fechaDocumento)}</strong></div><div><small>Fecha contable de entrada</small><strong>${escape(d.recepcionFechaContable||'Pendiente')}</strong></div><div><small>Estado de recepción</small><strong>${escape(d.recepcionEstado||'Sin preparar')}</strong></div></section>
      <section><h2>Artículos de inventario</h2>${table(['Línea / artículo','Descripción','Bodega destino','Cantidad','Unidad','Total línea'],lines.map(x=>`<tr><td>${escape(x.numeroLinea)} · ${escape(x.codigoArticulo||x.codigoExterno||'—')}</td><td>${escape(x.descripcion)}</td><td>${escape([x.bodegaCodigo,x.bodega].filter(Boolean).join(' · ')||'Pendiente de asignar')}</td><td class="numeric">${escape(x.cantidad)}</td><td>${escape(x.unidad||'—')}</td><td class="numeric">${money(x.totalNeto,d.moneda)}</td></tr>`).join(''))}</section>
      ${serials.length?`<section><h2>Unidades serializadas</h2>${table(['Línea','Unidad','Serial','Motor','Chasis','VIN','Color / modelo'],serials.map(x=>`<tr><td>${escape(x.line)} · ${escape(x.code)}</td><td>${escape(x.numeroUnidad)}</td><td>${escape(x.serial||'—')}</td><td>${escape(x.motor||'—')}</td><td>${escape(x.chasis||'—')}</td><td>${escape(x.vin||'—')}</td><td>${escape([x.color,x.modelo].filter(Boolean).join(' · ')||'—')}</td></tr>`).join(''))}</section>`:''}
      <section class="print-totals"><span>Valor de las líneas de inventario</span><strong>${money(inventoryTotal,d.moneda)}</strong><small>Factura del proveedor completa: ${money(d.totalPagar,d.moneda)}${detail.lineas.length!==lines.length?' · incluye líneas que no son mercancía':''}</small></section>
      <footer>${posted?'Entrada contabilizada en el ERP.':'Documento aún no contabilizado: no acredita ingreso definitivo a inventario.'} Este comprobante de entrada no sustituye la factura del proveedor ni el soporte fiscal.</footer>`;
  }
  let printNode=null;
  function print(detail,company){
    if(!detail?.documento||!detail.lineas?.some(x=>x.clasificacion==='INVENTARIO'))throw new Error('El documento no contiene mercancía para imprimir.');
    printNode?.remove();printNode=document.createElement('article');printNode.id='purchaseEntryPrint';printNode.innerHTML=html(detail,company);
    document.body.append(printNode);document.body.classList.add('printing-purchase-entry');
    const printed=printNode;
    const cleanup=()=>{if(printed.isConnected)printed.remove();if(printNode===printed){printNode=null;document.body.classList.remove('printing-purchase-entry');}};
    window.addEventListener('afterprint',cleanup,{once:true});
    try{window.print();}catch(error){cleanup();throw error;}
    window.setTimeout(cleanup,120000);
  }
  window.purchaseEntryPrint={html,print};
})();
