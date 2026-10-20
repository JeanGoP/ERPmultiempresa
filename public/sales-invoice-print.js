/* Representación interna. Una factura electrónica DIAN requiere validación, CUFE y QR reales. */
(() => {
  const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const money=value=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(value)||0);
  const table=(heads,rows,empty)=>`<table><thead><tr>${heads.map(x=>`<th>${escape(x)}</th>`).join('')}</tr></thead><tbody>${rows||`<tr><td colspan="${heads.length}">${escape(empty)}</td></tr>`}</tbody></table>`;
  function html(data,company){
    const h=data.header;
    const base=data.articulos.reduce((sum,x)=>sum+Number(x.base||0),0);
    const iva=data.articulos.reduce((sum,x)=>sum+Number(x.iva||0),0);
    const bodyConcepts=data.conceptos.filter(x=>x.mostrarEnCuerpo??x.ubicacionFormato!=='TOTALES');
    const totalConcepts=data.conceptos.filter(x=>x.mostrarEnTotales??x.ubicacionFormato==='TOTALES');
    return `<header><p class="print-kicker">Documento interno del ERP · No válido como factura electrónica DIAN</p><h1>Comprobante interno de venta</h1><div class="print-columns"><div><strong>${escape(company.name)}</strong><span>${escape(company.nit)}</span></div><div><strong>Referencia ERP ${escape(h.numero)}</strong><span>Fecha contable: ${escape(h.fecha)}</span><span>Sucursal: ${escape(h.sucursalCodigo)} · ${escape(h.sucursal)}</span></div></div></header>
      <section><h2>Cliente</h2><p><strong>${escape(h.cliente)}</strong><br>Identificación: ${escape(h.identificacion)}</p></section>
      <section><h2>Artículos</h2>${table(['Código / descripción','Bodega','Cant.','Unitario con IVA','Base','IVA','Total'],data.articulos.map(x=>`<tr><td>${escape(x.codigo)} · ${escape(x.descripcion)}</td><td>${escape(x.bodegaCodigo)} · ${escape(x.bodega)}</td><td class="numeric">${escape(x.cantidad)}</td><td class="numeric">${money(x.precio)}</td><td class="numeric">${money(x.base)}</td><td class="numeric">${money(x.iva)}<small>${escape(x.ivaTarifa)} %</small></td><td class="numeric">${money(Number(x.base)+Number(x.iva))}</td></tr>`).join(''),'Sin artículos')}</section>
      ${bodyConcepts.length?`<section><h2>Conceptos</h2>${table(['Código / concepto','Valor'],bodyConcepts.map(x=>`<tr><td>${escape(x.codigo)} · ${escape(x.nombre)}</td><td class="numeric">${money(x.valor)}</td></tr>`).join(''),'')}</section>`:''}
      <section class="print-summary"><h2>Resumen de la operación</h2><dl><dt>Base artículos</dt><dd>${money(base)}</dd><dt>IVA artículos</dt><dd>${money(iva)}</dd>${totalConcepts.map(x=>`<dt>${escape(x.nombre)}</dt><dd>${money(x.valor)}</dd>`).join('')}<dt>Total venta</dt><dd><strong>${money(h.total)}</strong></dd></dl></section>
      ${h.observacion?`<section><h2>Observaciones</h2><p class="print-observation">${escape(h.observacion)}</p></section>`:''}
      <footer>Documento de consulta interna. No contiene resolución de numeración, CUFE, código QR ni validación previa de la DIAN. No entregarlo como factura electrónica de venta.</footer>`;
  }
  let printNode=null;
  function print(data,company){
    if(!data?.header||!company)throw new Error('No hay datos suficientes para imprimir el comprobante.');
    printNode?.remove();
    printNode=document.createElement('article');printNode.id='salesInvoicePrint';printNode.innerHTML=html(data,company);
    document.body.append(printNode);document.body.classList.add('printing-sales-invoice');
    const printed=printNode;
    const cleanup=()=>{if(printed.isConnected)printed.remove();if(printNode===printed){printNode=null;document.body.classList.remove('printing-sales-invoice');}};
    window.addEventListener('afterprint',cleanup,{once:true});
    try{window.print();}catch(error){cleanup();throw error;}
    // Algunos navegadores no emiten afterprint si se cancela la vista previa.
    window.setTimeout(cleanup,120000);
  }
  window.salesInvoicePrint={html,print};
})();
