/* Cartera: las edades se calculan desde el vencimiento y nunca suman monedas distintas. */
const payableBands = [
  {name:'Por vencer',short:'Al día',color:'#208573',test:x=>x.diasVencida===0},
  {name:'1–30 días',short:'Vencimiento reciente',color:'#b99230',test:x=>x.diasVencida>0&&x.diasVencida<=30},
  {name:'31–60 días',short:'Atención',color:'#d17b3c',test:x=>x.diasVencida>30&&x.diasVencida<=60},
  {name:'61–90 días',short:'Prioridad alta',color:'#ba5551',test:x=>x.diasVencida>60&&x.diasVencida<=90},
  {name:'Más de 90 días',short:'Prioridad crítica',color:'#8a3f59',test:x=>x.diasVencida>90}
];
let payableBand = null;
const payableEscape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const payableMoney=(value,currency)=>new Intl.NumberFormat('es-CO',{style:'currency',currency,maximumFractionDigits:2}).format(value||0);
const payableSum=rows=>rows.reduce((sum,row)=>sum+row.saldoPendiente,0);

function renderPayableDashboard(){
  const all=state.accountsPayable?.documentos||[];
  const select=$('#payableCurrency');
  const previous=select.value;
  const currencies=[...new Set(all.map(x=>x.moneda.trim()))].sort();
  if(!currencies.length)currencies.push(state.erpSession?.company?.currency||'COP');
  select.replaceChildren(...currencies.map(x=>new Option(x,x)));
  select.value=currencies.includes(previous)?previous:currencies[0];
  const currency=select.value,money=value=>payableMoney(value,currency);
  const rows=all.filter(x=>x.moneda.trim()===currency);
  const open=rows.filter(x=>x.saldoPendiente>0&&x.estado!=='ANULADA');
  const overdue=open.filter(x=>x.diasVencida>0),total=payableSum(open),expired=payableSum(overdue);
  const percentage=total?Math.round(expired/total*100):0;
  const suppliers=new Map();
  open.forEach(row=>{const key=row.terceroId;const group=suppliers.get(key)||{name:row.proveedor,balance:0,overdue:0};group.balance+=row.saldoPendiente;if(row.diasVencida>0)group.overdue+=row.saldoPendiente;suppliers.set(key,group);});
  const kpis=[
    ['Saldo por pagar',money(total),suppliers.size+' proveedores con saldo','primary'],
    ['Cartera vencida',money(expired),percentage+'% del saldo requiere atención','alert'],
    ['Por vencer',money(total-expired),(open.length-overdue.length)+' facturas al día',''],
    ['Facturas abiertas',open.length,overdue.length+' vencidas · '+currency,'']
  ];
  elements.accountsPayableStats.innerHTML=kpis.map(([title,value,note,tone])=>'<article class="'+tone+'"><span>'+title+'</span><strong>'+payableEscape(value)+'</strong><small>'+payableEscape(note)+'</small></article>').join('');
  const bands=payableBands.map(band=>{const invoices=open.filter(band.test);return {...band,invoices,balance:payableSum(invoices)};});
  const ranked=[...suppliers.entries()].sort((a,b)=>b[1].balance-a[1].balance).slice(0,5);
  const priority=[...overdue].sort((a,b)=>b.diasVencida-a.diasVencida||b.saldoPendiente-a.saldoPendiente).slice(0,4);
  $('#payableDashboard').innerHTML=
    '<section class="payable-aging"><header><div><span class="payable-overline">DISTRIBUCIÓN DEL SALDO</span><h2>¿Qué edad tiene tu cartera?</h2><p>Días transcurridos desde el vencimiento de la factura.</p></div><button type="button" class="button secondary" data-age="all">Ver todas</button></header>'+
    '<div class="payable-stacked" aria-label="Distribución por edades">'+bands.filter(x=>x.balance>0).map(x=>'<span style="width:'+(total?x.balance/total*100:0)+'%;background:'+x.color+'" title="'+payableEscape(x.name+': '+money(x.balance))+'"></span>').join('')+'</div>'+
    '<div class="payable-bands">'+bands.map((x,i)=>'<button type="button" data-age="'+i+'" class="'+(payableBand===i?'selected':'')+'" style="--band-color:'+x.color+'" aria-pressed="'+(payableBand===i)+'"><span>'+x.name+'</span><strong>'+payableEscape(money(x.balance))+'</strong><small>'+x.invoices.length+' facturas · '+(total?Math.round(x.balance/total*100):0)+'%</small><em>'+x.short+'</em></button>').join('')+'</div></section>'+
    '<div class="payable-insights"><section><span class="payable-overline">CONCENTRACIÓN</span><h2>Proveedores con mayor saldo</h2><p>Los 5 mayores saldos de la selección actual.</p>'+
    (ranked.length?ranked.map(([id,x])=>'<button type="button" class="payable-rank" data-supplier="'+id+'"><span>'+payableEscape(x.name)+'</span><strong>'+payableEscape(money(x.balance))+'</strong><i style="--rank-width:'+Math.round(x.balance/ranked[0][1].balance*100)+'%"></i><small>Vencido: '+payableEscape(money(x.overdue))+'</small></button>').join(''):'<p class="payable-empty">No hay saldos pendientes.</p>')+'</section>'+
    '<section><span class="payable-overline">FOCO DE ATENCIÓN</span><h2>Facturas prioritarias</h2><p>Primero las más antiguas; después las de mayor saldo.</p>'+
    (priority.length?priority.map(x=>'<button type="button" class="payable-priority" data-statement="'+x.documentoProveedorId+'" data-supplier-id="'+x.terceroId+'"><span class="payable-days">'+x.diasVencida+'<small>días</small></span><span><strong>'+payableEscape(x.numeroDocumento)+'</strong><small>'+payableEscape(x.proveedor)+'</small></span><b>'+payableEscape(money(x.saldoPendiente))+'</b></button>').join(''):'<div class="payable-empty">Todo al día<br><small>No hay facturas vencidas en esta selección.</small></div>')+'</section></div>';
  const visible=payableBand===null?rows:open.filter(payableBands[payableBand].test);
  elements.accountsPayableTable.innerHTML='<table><thead><tr><th>Proveedor / factura</th><th>Vencimiento</th><th>Edad</th><th>Valor original</th><th>Saldo</th><th>Estado</th><th>Extracto</th></tr></thead><tbody>'+
    visible.map(x=>'<tr><td><strong>'+payableEscape(x.proveedor)+'</strong><small>'+payableEscape(x.numeroDocumento+' · NIT '+x.proveedorIdentificacion)+'</small></td><td>'+payableEscape(x.fechaVencimiento)+'</td><td>'+payableEscape(x.diasVencida>0?x.diasVencida+' días vencida':x.estado==='PAGADA'?'Pagada':x.estado==='ANULADA'?'Anulada':'Al día')+'</td><td>'+payableEscape(money(x.valorOriginal))+'</td><td class="accounts-payable-balance">'+payableEscape(money(x.saldoPendiente))+'</td><td><span class="saved-purchase-badge state-'+x.estado.toLowerCase()+'">'+payableEscape(x.estado)+'</span></td><td><button type="button" class="button secondary" data-statement="'+x.documentoProveedorId+'" data-supplier-id="'+x.terceroId+'">PDF factura</button> <button type="button" class="button secondary" data-payable-document-id="'+x.documentoProveedorId+'">Abrir</button></td></tr>').join('')+
    (!visible.length?'<tr><td colspan="7" class="empty">No hay facturas en esta selección.</td></tr>':'')+'</tbody></table>';
  $('#payableScope').textContent=(payableBand===null?'Todas las edades':payableBands[payableBand].name)+' · '+visible.length+' facturas · '+currency+'. Indicadores sujetos a los filtros superiores.';
  $('#supplierStatementPdf').disabled=!elements.accountsPayableSupplier.value||!rows.length;
  $('#supplierStatementPdf').title='Selecciona un proveedor para descargar su extracto completo, sin los filtros del dashboard.';
  elements.accountsPayableStatus.textContent=rows.length+' facturas · '+currency;
}

function buildSupplierStatementPdf(data){
  const pdf=new window.jspdf.jsPDF({unit:'mm',format:'a4'});
  const left=16,right=194,width=178;
  let y=0,continuation=null;
  const money=(n,c)=>payableMoney(n,c).replace(/\u00a0/g,' ');
  function page(){
    pdf.setFillColor('#193f3b');pdf.rect(0,0,210,31,'F');pdf.setTextColor('#ffffff');
    pdf.setFont('helvetica','bold');pdf.setFontSize(18);pdf.text('NEXO / Extracto de proveedor',left,16);
    pdf.setFont('helvetica','normal');pdf.setFontSize(9);pdf.text('Detalle de facturas y movimientos aplicados',left,24);
    pdf.setTextColor('#233d39');y=43;
  }
  function ensure(height){if(y+height>276){pdf.addPage();page();if(continuation)continuation();}}
  function text(value,size=10,bold=false){
    pdf.setFont('helvetica',bold?'bold':'normal');pdf.setFontSize(size);
    const lines=pdf.splitTextToSize(String(value),width);
    for(const line of lines){ensure(size*.5+2);pdf.setFont('helvetica',bold?'bold':'normal');pdf.setFontSize(size);pdf.text(line,left,y);y+=size*.5+2;}
  }
  function columns(values,widths,bold=false,fill=false){
    pdf.setFont('helvetica',bold?'bold':'normal');pdf.setFontSize(8);
    const wrapped=values.map((v,i)=>pdf.splitTextToSize(String(v),widths[i]-4));
    const lineCount=Math.max(...wrapped.map(x=>x.length));
    // Fragment long references across pages, keeping every character in the report.
    let offset=0;
    while(offset<lineCount){
      ensure(10);pdf.setFont('helvetica',bold?'bold':'normal');pdf.setFontSize(8);
      const count=Math.min(lineCount-offset,Math.max(1,Math.floor((276-y-4)/4)));
      const height=count*4+4;if(fill){pdf.setFillColor('#eaf2ef');pdf.rect(left,y-3,width,height,'F');}
      let x=left;
      wrapped.forEach((lines,i)=>{pdf.text(lines.slice(offset,offset+count),x+2,y+1);x+=widths[i];});
      y+=height;offset+=count;
    }
  }
  page();
  text(data.empresa,13,true);text('NIT '+data.nit,9);
  y+=3;text(data.proveedor,12,true);text('Identificación: '+data.identificacion,9);
  text('Generado: '+new Date(data.generadoEnUtc).toLocaleString('es-CO',{timeZone:'America/Bogota'})+' (Colombia)',9);
  text('Alcance: '+(data.facturas.length===1?'factura '+data.facturas[0].numeroDocumento:'todas las facturas del proveedor')+'. Saldos actuales.',9);
  const currencies=[...new Set(data.facturas.map(x=>x.moneda.trim()))];
  for(const currency of currencies){
    y+=4;
    const invoices=data.facturas.filter(x=>x.moneda.trim()===currency);
    text('Resumen / '+currency,11,true);
    text('Saldo pendiente: '+money(payableSum(invoices),currency),12,true);
    const movements=data.movimientos.filter(x=>x.moneda.trim()===currency);
    text('Pagos registrados: '+money(movements.filter(x=>x.tipoMovimiento==='PAGO').reduce((sum,x)=>sum+x.abono-x.cargo,0),currency),10);
    for(const invoice of invoices){
      ensure(55);y+=6;text('Factura '+invoice.numeroDocumento,12,true);
      text('Emisión: '+invoice.fechaDocumento+' | Vencimiento: '+invoice.fechaVencimiento+' | '+invoice.estado,9);
      text('Original: '+money(invoice.valorOriginal,currency)+' | Saldo: '+money(invoice.saldoPendiente,currency),10,true);
      const entries=movements.filter(x=>x.documentoPorPagarId===invoice.documentoPorPagarId);
      const widths=[22,27,51,26,26,26];
      columns(['Fecha','Movimiento','Soporte aplicado','Cargo','Abono','Saldo'],widths,true,true);
      continuation=()=>{
        text('Factura '+invoice.numeroDocumento+' / continuación / '+currency,10,true);
        columns(['Fecha','Movimiento','Soporte aplicado','Cargo','Abono','Saldo'],widths,true,true);
      };
      let balance=0;
      for(const entry of entries){
        balance+=entry.cargo-entry.abono;
        columns([entry.fecha,entry.tipoMovimiento.replaceAll('_',' '),entry.soporte,money(entry.cargo,currency),money(entry.abono,currency),money(balance,currency)],widths);
      }
      if(!entries.some(x=>x.tipoMovimiento==='PAGO'&&x.abono>0))text('Sin pagos registrados para esta factura.',9);
      if(Math.abs(balance-invoice.saldoPendiente)>.01)text('Observación: el saldo de movimientos difiere del saldo de cartera. Requiere conciliación.',9,true);
      text('Las aplicaciones, notas y reversos se presentan por separado de los pagos.',8);
      continuation=null;
    }
  }
  for(let number=1;number<=pdf.getNumberOfPages();number++){
    pdf.setPage(number);pdf.setDrawColor('#cbd9d3');pdf.line(left,283,right,283);
    pdf.setFontSize(8);pdf.setFont('helvetica','normal');pdf.setTextColor('#64756e');
    pdf.text('Nexo ERP | Extracto de movimientos registrados',left,289);
    pdf.text(number+' / '+pdf.getNumberOfPages(),right,289,{align:'right'});
  }
  return pdf;
}

async function downloadSupplierStatement(supplierId,documentId,button){
  const companyId=state.erpSession?.company?.id;if(!companyId)return;
  button.disabled=true;const label=button.textContent;button.textContent='Generando…';
  try{
    const query=documentId?'?documentoId='+encodeURIComponent(documentId):'';
    const data=await apiRequest('/api/v1/companies/'+companyId+'/suppliers/'+supplierId+'/statement'+query);
    if(String(state.erpSession?.company?.id)!==String(companyId))return;
    buildSupplierStatementPdf(data).save('extracto-proveedor-'+supplierId+(documentId?'-factura-'+documentId:'')+'.pdf');
  }catch(error){elements.accountsPayableNotice.textContent='No se pudo generar el extracto. '+error.message;elements.accountsPayableNotice.hidden=false;}
  finally{button.disabled=false;button.textContent=label;}
}
$('#payableCurrency').addEventListener('change',renderPayableDashboard);
$('#accountsPayableModule').addEventListener('click',event=>{
  const age=event.target.closest('[data-age]');
  if(age){payableBand=age.dataset.age==='all'?null:Number(age.dataset.age);renderPayableDashboard();return;}
  const supplier=event.target.closest('[data-supplier]');
  if(supplier){elements.accountsPayableSupplier.value=supplier.dataset.supplier;payableBand=null;void refreshAccountsPayable();return;}
  const statement=event.target.closest('[data-statement]');
  if(statement)void downloadSupplierStatement(statement.dataset.supplierId,statement.dataset.statement,statement);
});
$('#supplierStatementPdf').addEventListener('click',event=>{const supplier=elements.accountsPayableSupplier.value;if(supplier)void downloadSupplierStatement(supplier,null,event.currentTarget);});
