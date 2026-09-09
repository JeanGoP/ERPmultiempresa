/* Relación de consulta: no registra pagos ni modifica obligaciones. */
const paymentReportLimitations='Los descuentos son los guardados en la factura, ya incluidos en su valor. No se aplican descuentos por pronto pago. Impuestos corresponde al total registrado, no necesariamente solo IVA. Banco, consignación y anticipos sin aplicar no están disponibles en esta consulta.';
const reportRound=value=>Math.round((value+Number.EPSILON)*100)/100;
function preparePaymentReport(data,ids,currency,reference=''){
  const selected=new Set(ids.map(String));
  const invoices=data.facturas.filter(x=>selected.has(String(x.documentoProveedorId))&&x.moneda.trim()===currency&&x.estado!=='ANULADA');
  if(!invoices.length)throw new Error('No hay facturas válidas para esta selección.');
  if(invoices.length!==selected.size)throw new Error('La selección cambió o contiene facturas anuladas. Actualiza la cartera y prepara nuevamente el reporte.');
  const keys=['subtotalBruto','descuentoTotal','impuestoTotal','cargoTotal','valorOriginal','saldoPendiente'];
  if(invoices.some(x=>keys.some(key=>!Number.isFinite(x[key]))))throw new Error('El backend no devuelve el desglose de las facturas. Publica la versión actualizada del backend antes de generar este reporte.');
  const payableIds=new Set(invoices.map(x=>String(x.documentoPorPagarId)));
  const movements=data.movimientos.filter(x=>payableIds.has(String(x.documentoPorPagarId))&&x.moneda.trim()===currency);
  const sum=(rows,key)=>reportRound(rows.reduce((total,x)=>total+x[key],0));
  const rows=invoices.map(x=>{
    const entries=movements.filter(m=>String(m.documentoPorPagarId)===String(x.documentoPorPagarId));
    const payments=entries.filter(m=>m.tipoMovimiento==='PAGO');
    const ledger=reportRound(sum(entries,'cargo')-sum(entries,'abono'));
    return {...x,neto:reportRound(x.subtotalBruto-x.descuentoTotal),
      otrosAjustes:reportRound(x.valorOriginal-(x.subtotalBruto-x.descuentoTotal+x.impuestoTotal+x.cargoTotal)),
      pagos:reportRound(sum(payments,'abono')-sum(payments,'cargo')),
      diferenciaCartera:reportRound(ledger-x.saldoPendiente)};
  }).sort((a,b)=>a.fechaDocumento.localeCompare(b.fechaDocumento)||String(a.numeroDocumento).localeCompare(String(b.numeroDocumento)));
  const totals=Object.fromEntries([...keys,'neto','otrosAjustes','pagos'].map(key=>[key,sum(rows,key)]));
  return {empresa:data.empresa,nit:data.nit,proveedor:data.proveedor,identificacion:data.identificacion,
    generadoEnUtc:data.generadoEnUtc,reference:String(reference).trim().slice(0,60),currency,rows,totals,
    movements:movements.filter(x=>x.tipoMovimiento!=='FACTURA').sort((a,b)=>a.fecha.localeCompare(b.fecha)||a.movimientoId-b.movimientoId),
    warnings:[paymentReportLimitations,
      ...(rows.some(x=>Math.abs(x.otrosAjustes)>.01)?['Otros ajustes factura es la diferencia entre el valor original y el neto más impuestos y cargos. Revisa el documento origen para identificar retenciones, anticipos o redondeos.']:[]),
      ...(rows.some(x=>Math.abs(x.diferenciaCartera)>.01)?['Hay facturas cuyo saldo no concilia con sus movimientos. Revisa la cartera antes de utilizar esta relación para pagar.']:[])]};
}

const paymentReportColumns=[['Factura','numeroDocumento'],['Bruto sin impuestos','subtotalBruto'],['Desc. factura','descuentoTotal'],['Neto sin impuestos','neto'],['Impuestos','impuestoTotal'],['Cargos','cargoTotal'],['Otros ajustes factura','otrosAjustes'],['Valor factura','valorOriginal'],['Pagos registrados','pagos'],['Saldo actual','saldoPendiente']];
function buildPaymentReportCsv(report){
  // Neutraliza fórmulas de texto recibido del XML al abrir el CSV en Excel.
  const cell=value=>{const text=typeof value==='number'?String(value).replace('.',','):String(value??'');return '"'+((typeof value!=='number'&&/^[\s]*[=+@-]/.test(text)?"'":'')+text).replaceAll('"','""')+'"';};
  const lines=[['RELACIÓN DE FACTURAS Y PAGOS'],['Empresa',report.empresa,'NIT',report.nit],['Proveedor',report.proveedor,'NIT',report.identificacion],['Referencia',report.reference,'Moneda',report.currency],['Generado',report.generadoEnUtc],['Alcance','Facturas seleccionadas. Valores y movimientos actuales, no corte histórico.'],[],
    paymentReportColumns.map(x=>x[0]),...report.rows.map(row=>paymentReportColumns.map(([,key])=>row[key])),
    ['TOTAL',...paymentReportColumns.slice(1).map(([,key])=>report.totals[key])],[],
    ['MOVIMIENTOS APLICADOS'],['Fecha','Factura','Tipo','Soporte','Cargo','Abono','Banco / consignación'],
    ...report.movements.map(m=>[m.fecha,m.factura,m.tipoMovimiento,m.soporte,m.cargo,m.abono,'No disponible']),
    ...(!report.movements.length?[['Sin pagos, notas ni aplicaciones registrados para las facturas seleccionadas.']]:[]),[],
    ...report.warnings.map(x=>[x])];
  return '\ufeff'+lines.map(row=>row.map(cell).join(';')).join('\r\n');
}

function buildPaymentReportPdf(report){
  const pdf=new window.jspdf.jsPDF({orientation:'landscape',unit:'mm',format:'a4'});
  const left=12,width=273,bottom=194;let y=0,repeat=null;
  const money=value=>new Intl.NumberFormat('es-CO',{minimumFractionDigits:2,maximumFractionDigits:2}).format(value);
  function page(){
    pdf.setTextColor('#173f37');pdf.setFont('helvetica','bold');pdf.setFontSize(16);
    pdf.text('Relación de facturas y pagos',left,14);pdf.setFontSize(9);pdf.setFont('helvetica','normal');
    const label=pdf.splitTextToSize(report.proveedor+' / NIT '+report.identificacion+' / '+report.currency,width);
    pdf.text(label,left,21);y=25+label.length*4;
  }
  function ensure(height){if(y+height>bottom){pdf.addPage();page();if(repeat)repeat();}}
  function text(value,size=9,bold=false){
    pdf.setFont('helvetica',bold?'bold':'normal');pdf.setFontSize(size);
    for(const line of pdf.splitTextToSize(String(value),width)){ensure(5);pdf.setFont('helvetica',bold?'bold':'normal');pdf.setFontSize(size);pdf.text(line,left,y);y+=5;}
  }
  function row(values,widths,header=false){
    pdf.setFontSize(8);pdf.setFont('helvetica',header?'bold':'normal');
    const wrapped=values.map((v,i)=>pdf.splitTextToSize(String(v),widths[i]-4));
    const count=Math.max(...wrapped.map(x=>x.length));let offset=0;
    while(offset<count){
      ensure(9);const n=Math.min(count-offset,Math.max(1,Math.floor((bottom-y-4)/4))),height=n*4+4;
      pdf.setFontSize(8);pdf.setFont('helvetica',header?'bold':'normal');
      if(header){pdf.setFillColor('#e5f0eb');pdf.rect(left,y-3,width,height,'F');}
      let x=left;wrapped.forEach((parts,i)=>{pdf.text(parts.slice(offset,offset+n),x+2,y+1);x+=widths[i];});
      y+=height;offset+=n;
    }
  }
  page();text(report.empresa+' / NIT '+report.nit,11,true);
  text('Referencia: '+(report.reference||'Sin referencia')+' / Generado: '+new Date(report.generadoEnUtc).toLocaleString('es-CO',{timeZone:'America/Bogota'}));
  text(report.rows.length+' facturas seleccionadas. Valores y movimientos actuales, no corte histórico.');
  text('Saldo actual: '+money(report.totals.saldoPendiente)+' '+report.currency+' / Pagos registrados: '+money(report.totals.pagos)+' '+report.currency,11,true);y+=3;
  const widths=[36,26,24,26,26,20,25,28,28,34];
  const headers=()=>row(paymentReportColumns.map(x=>x[0]),widths,true);
  headers();repeat=headers;
  for(const invoice of report.rows)row(paymentReportColumns.map(([,key],i)=>i?money(invoice[key]):invoice[key]),widths);
  row(['TOTAL',...paymentReportColumns.slice(1).map(([,key])=>money(report.totals[key]))],widths,true);
  repeat=null;y+=6;ensure(35);text('Movimientos aplicados a estas facturas',11,true);
  const movementWidths=[24,36,32,105,38,38];
  const movementHeaders=()=>row(['Fecha','Factura','Tipo','Soporte','Cargo','Abono'],movementWidths,true);
  movementHeaders();repeat=movementHeaders;
  for(const m of report.movements)row([m.fecha,m.factura,m.tipoMovimiento.replaceAll('_',' '),m.soporte,money(m.cargo),money(m.abono)],movementWidths);
  if(!report.movements.length)text('Sin pagos, notas ni aplicaciones registrados para las facturas seleccionadas.');
  repeat=null;y+=5;
  for(const warning of report.warnings)text(warning,9);
  for(let p=1;p<=pdf.getNumberOfPages();p++){pdf.setPage(p);pdf.setFont('helvetica','normal');pdf.setFontSize(8);pdf.setTextColor('#61756d');pdf.text('Nexo ERP / Consulta de cartera. No es un comprobante de pago.',left,203);pdf.text(p+' / '+pdf.getNumberOfPages(),285,203,{align:'right'});}
  return pdf;
}

function paymentReportCandidates(){
  const supplier=elements.accountsPayableSupplier.value,currency=$('#payableCurrency').value;
  return (state.accountsPayable?.documentos||[]).filter(x=>String(x.terceroId)===supplier&&x.moneda.trim()===currency&&x.estado!=='ANULADA'&&(payableBand===null||x.saldoPendiente>0&&payableBands[payableBand].test(x)));
}

async function openPaymentReport(){
  if(!canUseAccountsPayable())return;
  const scope=()=>JSON.stringify([state.erpSession?.company?.id,elements.accountsPayableSupplier.value,$('#payableCurrency').value,elements.accountsPayableSearch.value,elements.accountsPayableState.value,elements.accountsPayableFrom.value,elements.accountsPayableTo.value,payableBand]);
  const initialScope=scope();
  if(!await refreshAccountsPayable()||scope()!==initialScope)return;
  const candidates=paymentReportCandidates();
  if(!elements.accountsPayableSupplier.value||!candidates.length){
    elements.accountsPayableNotice.textContent='Selecciona un proveedor con facturas en los filtros actuales y pulsa Actualizar antes de preparar el reporte.';elements.accountsPayableNotice.hidden=false;elements.accountsPayableSupplier.focus();return;
  }
  const companyId=state.erpSession?.company?.id,supplierId=elements.accountsPayableSupplier.value,currency=$('#payableCurrency').value;
  const dialog=document.createElement('dialog');dialog.className='payment-report-dialog';
  dialog.innerHTML='<form method="dialog"><header><div><h2>Relación de facturas y pagos</h2><p>'+payableEscape(candidates[0].proveedor)+' · '+payableEscape(currency)+'</p></div><button class="button secondary" aria-label="Cerrar" type="submit">Cerrar</button></header></form>'+
    '<p>Escoge las facturas del reporte. Se consultarán nuevamente sus importes y movimientos en la base al descargar.</p>'+
    '<label>Referencia del reporte (opcional)<input id="paymentReportReference" maxlength="60" placeholder="Ej. Relación 013"></label>'+
    '<div class="payment-report-actions"><button type="button" class="button secondary" data-report-select="all">Seleccionar todas</button><button type="button" class="button secondary" data-report-select="none">Quitar selección</button><span data-report-count></span></div>'+
    '<div class="table-wrap payment-report-selection"><table><thead><tr><th>Incluir</th><th>Factura</th><th>Fecha</th><th>Valor factura</th><th>Saldo actual</th></tr></thead><tbody>'+
    candidates.map(x=>'<tr><td><input type="checkbox" checked data-report-id="'+x.documentoProveedorId+'" aria-label="Incluir factura '+payableEscape(x.numeroDocumento)+'"></td><td>'+payableEscape(x.numeroDocumento)+'</td><td>'+payableEscape(x.fechaDocumento)+'</td><td>'+payableEscape(payableMoney(x.valorOriginal,currency))+'</td><td>'+payableEscape(payableMoney(x.saldoPendiente,currency))+'</td></tr>').join('')+'</tbody></table></div>'+
    '<p class="payment-report-disclosure">'+paymentReportLimitations+'</p><p role="status" data-report-status></p>'+
    '<footer><button class="button secondary" type="button" data-report-download="pdf">Descargar PDF</button><button class="button primary" type="button" data-report-download="xlsx">Descargar Excel (.xlsx)</button></footer>';
  document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove());
  const selected=()=>[...dialog.querySelectorAll('[data-report-id]:checked')].map(x=>x.dataset.reportId);
  const update=()=>{const ids=selected();dialog.querySelector('[data-report-count]').textContent=ids.length+' facturas seleccionadas';dialog.querySelectorAll('[data-report-download]').forEach(x=>x.disabled=!ids.length);};
  dialog.addEventListener('change',update);
  dialog.addEventListener('click',async event=>{
    const select=event.target.closest('[data-report-select]');
    if(select){dialog.querySelectorAll('[data-report-id]').forEach(x=>x.checked=select.dataset.reportSelect==='all');update();return;}
    const button=event.target.closest('[data-report-download]');if(!button)return;
    const ids=selected(),reference=dialog.querySelector('#paymentReportReference').value;
    const controls=[...dialog.querySelectorAll('button,input')];controls.forEach(x=>x.disabled=true);
    const status=dialog.querySelector('[data-report-status]');status.textContent='Consultando facturas y movimientos…';
    try{
      if(String(state.erpSession?.company?.id)!==String(companyId))throw new Error('La empresa activa cambió. Abre nuevamente el reporte.');
      const data=await apiRequest('/api/v1/companies/'+companyId+'/suppliers/'+supplierId+'/statement');
      if(!dialog.isConnected||String(state.erpSession?.company?.id)!==String(companyId))return;
      const report=preparePaymentReport(data,ids,currency,reference);
      const filename='relacion-proveedor-'+supplierId+'-'+currency;
      if(button.dataset.reportDownload==='pdf')buildPaymentReportPdf(report).save(filename+'.pdf');
      else {
        const workbook=await buildPaymentReportXlsx(report);
        if(!dialog.isConnected||String(state.erpSession?.company?.id)!==String(companyId))return;
        download(filename+'.xlsx',workbook,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
      status.textContent='Reporte generado con '+report.rows.length+' facturas. La cartera no fue modificada.';
    }catch(error){status.textContent='No se pudo generar el reporte. '+error.message;}
    finally{controls.forEach(x=>x.disabled=false);update();}
  });
  update();dialog.showModal();
}
$('#openPaymentReport').addEventListener('click',openPaymentReport);
$('#supplierPaymentReportNav').addEventListener('click',()=>{showAccountsPayable();if(canUseAccountsPayable()){$('.payment-report-entry').scrollIntoView({behavior:'smooth',block:'center'});elements.accountsPayableSupplier.focus();}});
