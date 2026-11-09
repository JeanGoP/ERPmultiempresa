/* Informes leídos del libro de Nexo. El Excel conserva importes como números. */
(function(){
  const module=document.querySelector('#accountingReportsModule');
  const nav=document.querySelector('#accountingReportsNav');
  const form=document.querySelector('#accountingReportsForm');
  const table=document.querySelector('#accountingReportTable');
  const status=document.querySelector('#accountingReportStatus');
  const title=document.querySelector('#accountingReportTitle');
  const count=document.querySelector('#accountingReportCount');
  const summary=document.querySelector('#accountingReportSummary');
  const subtotals=document.querySelector('#accountingReportSubtotals');
  const excel=document.querySelector('#accountingReportExcel');
  if(!module||!nav||!form)return;
  let report=null,reportCompany=null,request=0;
  const today=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'America/Bogota'});
  const money=new Intl.NumberFormat('es-CO',{minimumFractionDigits:2,maximumFractionDigits:2});
  const escapeXml=value=>String(value??'').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&apos;');
  function updateFields(){
    const kind=form.elements.tipo.value,inventory=kind==='inventario',portfolio=kind==='cxc'||kind==='cxp';
    form.elements.desde.closest('label').hidden=inventory;
    form.elements.cuenta.closest('label').hidden=inventory||portfolio;
    form.elements.cuenta.required=kind==='mayor';
    form.elements.tercero.closest('label').hidden=inventory;
    form.elements.centro.closest('label').hidden=inventory||portfolio;
  }
  form.elements.tipo.addEventListener('change',updateFields);updateFields();
  function defaultDates(){if(form.elements.desde.value)return;const end=today();form.elements.hasta.value=end;form.elements.desde.value=end.slice(0,8)+'01';}
  function clearResults(message){report=null;excel.disabled=true;table.replaceChildren();summary.replaceChildren();subtotals.replaceChildren();count.textContent='';title.textContent='Selecciona un informe';status.textContent=message;}
  function show(){
    if(!hasPermission('CONTABILIDAD.INFORMES.CONSULTAR'))return;
    hideWorkspaces();module.hidden=false;defaultDates();
    document.querySelectorAll('.nav-subitem.active').forEach(x=>x.classList.remove('active'));nav.classList.add('active');
    document.querySelector('.breadcrumb span').textContent='Informes';elements.breadcrumbCurrent.textContent='Contabilidad';
    const company=String(state.erpSession?.company?.id||'');
    if(reportCompany!==company){reportCompany=company;clearResults('Escoge un informe y consulta.');}
    window.scrollTo({top:0,behavior:'smooth'});
  }
  nav.addEventListener('click',show);
  window.showAccountingReports=show;
  const amountNames=new Set(['Saldo inicial','Debitos','Creditos','Saldo final','Debito','Credito','Saldo','Diferencia','Valor original','Saldo actual','ValorHistorico']);
  const classNames={'1':'Activo','2':'Pasivo','3':'Patrimonio','4':'Ingresos','5':'Gastos','6':'Costos de venta','7':'Costos de producción','8':'Cuentas de orden deudoras','9':'Cuentas de orden acreedoras'};
  function totalsFor(data){
    const columns=data.columnas||[],rows=data.filas||[];
    const amountIndexes=columns.map((name,index)=>amountNames.has(name)?index:-1).filter(index=>index>=0);
    const index=name=>columns.indexOf(name);
    const grouped={balance:'Cuenta',situacion:'Cuenta',resultados:'Cuenta',patrimonio:'Cuenta',efectivo:'Cuenta',diario:'Tipo',mayor:'Cuenta',terceros:'Nit',impuestos:'Cuenta',centros:'Centro',comprobantes:'Tipo',cuentas:'Cuenta',cxc:'Nit',cxp:'Moneda',inventario:'BodegaId'};
    const groupIndex=index(grouped[data.tipo]),groups=new Map(),sum=items=>{
      const result={};for(const i of amountIndexes)result[columns[i]]=Math.round(items.reduce((n,row)=>n+Number(row[i]||0),0)*10000)/10000;return result;
    };
    for(const row of rows){
      let key=groupIndex<0?'':String(row[groupIndex]??'Sin asignar').trim();
      if(['balance','situacion','resultados','patrimonio','cuentas'].includes(data.tipo))key=key.slice(0,1);
      if(data.tipo==='efectivo'||data.tipo==='impuestos')key=key.slice(0,4);
      const label=classNames[key]&&['balance','situacion','resultados','patrimonio','cuentas'].includes(data.tipo)?`${key} · ${classNames[key]}`:data.tipo==='inventario'?`Bodega ${key}`:data.tipo==='cxp'?`Moneda ${key}`:key;
      if(!groups.has(label))groups.set(label,[]);groups.get(label).push(row);
    }
    const groupRows=[...groups].map(([label,items])=>({label,values:sum(items)}));
    const mixedCurrency=data.tipo==='cxp'&&groups.size>1;
    return {amountIndexes,groupRows,grand:mixedCurrency?null:sum(rows),mixedCurrency};
  }
  function valueRow(columns,label,values){return columns.map((name,index)=>index===0?label:values?.[name]??'');}
  function render(data){
    table.replaceChildren();summary.replaceChildren();subtotals.replaceChildren();const rows=data.filas||[],columns=data.columnas||[];
    title.textContent=data.titulo;
    count.textContent=rows.length.toLocaleString('es-CO')+' filas';
    status.textContent=data.truncado?'Se muestran las primeras 20.000 filas. Acota fechas o filtros para un informe completo.':!rows.length?'No hay datos en Nexo para este período y filtros.':data.tipo==='cxc'||data.tipo==='cxp'?'Saldo actual de documentos reconocidos en el período; no es un saldo histórico al corte.':'Consulta actualizada.';
    if(!rows.length)return;
    if(data.truncado){
      const note=document.createElement('p');note.textContent='No se calculan totales de un resultado incompleto. Acota los filtros.';summary.append(note);
      const grid=document.createElement('table'),head=document.createElement('thead'),body=document.createElement('tbody'),heading=document.createElement('tr');
      for(const column of columns){const cell=document.createElement('th');cell.textContent=column;heading.append(cell);}head.append(heading);
      for(const row of rows.slice(0,250)){const line=document.createElement('tr');row.forEach(value=>{const cell=document.createElement('td');cell.textContent=typeof value==='number'?money.format(value):value==null?'—':String(value);line.append(cell);});body.append(line);}
      grid.append(head,body);table.append(grid);return;
    }
    const totals=totalsFor(data);
    let cards=totals.mixedCurrency?totals.groupRows.map(group=>({label:`${group.label} · saldo actual`,value:group.values['Saldo actual']})):
      Object.entries(totals.grand||{}).map(([label,value])=>({label,value}));
    if(data.tipo==='resultados'&&totals.grand){
      const income=totals.groupRows.find(x=>x.label.startsWith('4 ·'));
      const revenue=-(income?.values['Saldo final']||0),expenses=totals.groupRows.filter(x=>/^[567] ·/.test(x.label)).reduce((n,x)=>n+(x.values['Saldo final']||0),0);
      cards=[{label:'Ingresos',value:revenue},{label:'Costos y gastos',value:expenses},{label:'Resultado del período',value:revenue-expenses}];
    }
    if(data.tipo==='situacion'&&totals.grand){
      const part=code=>totals.groupRows.find(x=>x.label.startsWith(code+' ·'))?.values['Saldo final']||0;
      const assets=part('1'),liabilities=-part('2'),equity=-part('3');
      cards=[{label:'Activo',value:assets},{label:'Pasivo',value:liabilities},{label:'Patrimonio',value:equity},{label:'Diferencia',value:assets-liabilities-equity}];
    }
    for(const card of cards.slice(0,8)){const box=document.createElement('div'),label=document.createElement('span'),value=document.createElement('strong');label.textContent=card.label;value.textContent=money.format(card.value);box.append(label,value);summary.append(box);}
    const grid=document.createElement('table'),head=document.createElement('thead'),body=document.createElement('tbody');
    const heading=document.createElement('tr');for(const column of columns){const cell=document.createElement('th');cell.textContent=column;heading.append(cell);}head.append(heading);
    for(const row of rows.slice(0,250)){
      const line=document.createElement('tr');row.forEach(value=>{const cell=document.createElement('td');if(typeof value==='number'){cell.className='number';cell.textContent=money.format(value);}else cell.textContent=value==null?'—':String(value).slice(0,10)==='0001-01-01'?'—':String(value);line.append(cell);});body.append(line);
    }
    grid.append(head,body);
    if(totals.grand){const foot=document.createElement('tfoot'),line=document.createElement('tr');valueRow(columns,data.tipo==='resultados'?'TOTAL · SALDO CONTABLE':'TOTAL',totals.grand).forEach(value=>{const cell=document.createElement('td');cell.textContent=typeof value==='number'?money.format(value):value;cell.className=typeof value==='number'?'number':'';line.append(cell);});foot.append(line);grid.append(foot);}
    table.append(grid);
    if(rows.length>250){const note=document.createElement('p');note.textContent='Vista previa de 250 filas. El Excel incluye todas las filas consultadas.';table.append(note);}
    if(totals.groupRows.length>1){const details=document.createElement('details'),caption=document.createElement('summary'),list=document.createElement('table');caption.textContent=totals.mixedCurrency?'Totales separados por moneda':`Ver ${totals.groupRows.length} subtotales`;const thead=document.createElement('thead'),header=document.createElement('tr');for(const name of ['Grupo',...Object.keys(totals.groupRows[0].values)]){const cell=document.createElement('th');cell.textContent=name;header.append(cell);}thead.append(header);const body=document.createElement('tbody');for(const group of totals.groupRows.slice(0,100)){const line=document.createElement('tr');for(const value of [group.label,...Object.values(group.values)]){const cell=document.createElement('td');cell.textContent=typeof value==='number'?money.format(value):value;line.append(cell);}body.append(line);}list.append(thead,body);details.append(caption,list);subtotals.append(details);}
  }
  form.addEventListener('submit',async event=>{
    event.preventDefault();const company=state.erpSession?.company?.id;
    if(!company)return;const current=++request;
    const params=new URLSearchParams();for(const key of ['desde','hasta','cuenta','tercero','centro']){const value=String(form.elements[key].value||'').trim();if(value)params.set(key,value);}
    const kind=form.elements.tipo.value;
    clearResults('Consultando asientos en Nexo…');
    form.querySelector('[type="submit"]').disabled=true;
    try{
      const data=await apiRequest(`/api/v1/companies/${company}/accounting-reports/${encodeURIComponent(kind)}?${params}`);
      if(current!==request||String(state.erpSession?.company?.id)!==String(company))return;
      report=data;reportCompany=String(company);render(data);excel.disabled=!data.filas?.length||data.truncado;
    }catch(error){if(current===request)status.textContent=error.message;}
    finally{if(current===request)form.querySelector('[type="submit"]').disabled=false;}
  });
  function workbook(data){
    if(!data.filas?.length||data.truncado)throw new Error('Acota el informe antes de descargarlo.');
    const columns=data.columnas,rows=data.filas,totals=totalsFor(data);
    const col=n=>String.fromCharCode(65+n);
    const cell=(value,reference,style=0)=>{
      if(typeof value==='number')return `<c r="${reference}" s="2"><v>${value}</v></c>`;
      const clean=String(value??'').slice(0,32767);
      return `<c r="${reference}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${escapeXml(clean)}</t></is></c>`;
    };
    const row=(number,values,style=0)=>`<row r="${number}">${values.map((value,index)=>cell(value,col(index)+number,style)).join('')}</row>`;
    const sheet=[row(1,[data.titulo],1),row(2,[`Período ${data.desde} a ${data.hasta} · ${document.querySelector('#companyName')?.textContent||''}`]),row(3,['Fuente: asientos confirmados conservados en Nexo. Verificar saldos iniciales e historia previa en Zeus.']),row(4,columns,1)];
    rows.forEach((values,index)=>sheet.push(row(index+5,values)));
    let final=rows.length+4;sheet.push(row(++final,['SUBTOTALES'],1));
    for(const group of totals.groupRows)sheet.push(row(++final,valueRow(columns,group.label,group.values)));
    if(totals.grand)sheet.push(row(++final,valueRow(columns,'TOTAL',totals.grand),1));
    if(data.tipo==='resultados'&&totals.grand)sheet.push(row(++final,valueRow(columns,'RESULTADO DEL PERÍODO',{'Saldo final':-totals.grand['Saldo final']}),1));
    if(data.tipo==='situacion'&&totals.grand)sheet.push(row(++final,valueRow(columns,'DIFERENCIA ACTIVO - PASIVO - PATRIMONIO',{'Saldo final':totals.grand['Saldo final']}),1));
    const last=col(columns.length-1),dataEnd=rows.length+4;
    const files={
      '[Content_Types].xml':'<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
      '_rels/.rels':'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':'<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Informe" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'xl/styles.xml':'<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="10"/><name val="Aptos"/></font><font><b/><sz val="10"/><color rgb="FF195540"/><name val="Aptos"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>',
      'xl/worksheets/sheet1.xml':`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:${last}${final}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="${columns.length}" width="22" customWidth="1"/></cols><sheetData>${sheet.join('')}</sheetData><autoFilter ref="A4:${last}${dataEnd}"/></worksheet>`
    };
    return paymentReportZip(files);
  }
  excel.addEventListener('click',()=>{
    if(!report||String(state.erpSession?.company?.id)!==reportCompany)return;
    try{
      const blob=workbook(report),url=URL.createObjectURL(blob),link=document.createElement('a');
      link.href=url;link.download=`contabilidad-${report.tipo}-${report.desde}-${report.hasta}.xlsx`;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
    }catch(error){status.textContent=error.message;}
  });
  window.resetAccountingReports=()=>{request++;reportCompany=null;clearResults('Escoge un informe y consulta.');};
})();
