/* Rellena la plantilla XLSX creada con Artifact Tool. Solo datos de la consulta. */
function paymentReportZip(files){
  const encoder=new TextEncoder(),parts=[],central=[];let offset=0;
  const crcTable=Array.from({length:256},(_,n)=>{for(let k=0;k<8;k++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
  for(const [name,text] of Object.entries(files)){
    const filename=encoder.encode(name),data=encoder.encode(text);let crc=0xffffffff;
    for(const byte of data)crc=crcTable[(crc^byte)&255]^(crc>>>8);crc=(crc^0xffffffff)>>>0;
    const header=new Uint8Array(30+filename.length),h=new DataView(header.buffer);
    h.setUint32(0,0x04034b50,true);h.setUint16(4,20,true);h.setUint16(6,0x800,true);h.setUint16(12,33,true);
    h.setUint32(14,crc,true);h.setUint32(18,data.length,true);h.setUint32(22,data.length,true);h.setUint16(26,filename.length,true);header.set(filename,30);
    const directory=new Uint8Array(46+filename.length),d=new DataView(directory.buffer);
    d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint16(8,0x800,true);d.setUint16(14,33,true);
    d.setUint32(16,crc,true);d.setUint32(20,data.length,true);d.setUint32(24,data.length,true);d.setUint16(28,filename.length,true);d.setUint32(42,offset,true);directory.set(filename,46);
    parts.push(header,data);central.push(directory);offset+=header.length+data.length;
  }
  const end=new Uint8Array(22),view=new DataView(end.buffer),centralSize=central.reduce((n,x)=>n+x.length,0);
  view.setUint32(0,0x06054b50,true);view.setUint16(8,central.length,true);view.setUint16(10,central.length,true);view.setUint32(12,centralSize,true);view.setUint32(16,offset,true);
  return new Blob([...parts,...central,end],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
}

async function buildPaymentReportXlsx(report,template){
  if(!template){const response=await fetch('assets/payment-report-template.json');if(!response.ok)throw new Error('No se pudo cargar el formato de Excel. Recarga la aplicación e intenta nuevamente.');template=await response.json();}
  if(template.version!==1||!template.files?.['xl/styles.xml'])throw new Error('El formato de Excel no es compatible.');
  if(report.rows.length>50000||report.movements.length>50000)throw new Error('Selecciona menos facturas: el Excel admite hasta 50.000 filas por hoja.');
  const files={...template.files},ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const clean=value=>String(value??'').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,'');
  const column=n=>String.fromCharCode(65+n);
  for(let i=0;i<2;i++){
    const file=`xl/worksheets/sheet${i+1}.xml`,doc=new DOMParser().parseFromString(files[file],'application/xml');
    if(doc.getElementsByTagName('parsererror').length)throw new Error('La plantilla de Excel está dañada.');
    const tag=(name)=>doc.createElementNS(ns,'x:'+name),nodes=name=>[...doc.getElementsByTagNameNS(ns,name)];
    const original=new Map(nodes('row').map(r=>[Number(r.getAttribute('r')),r.cloneNode(true)]));
    const sheetData=nodes('sheetData')[0],merges=nodes('mergeCells')[0],last=i?'H':'K';
    function value(cell,input,formula){
      cell.replaceChildren();cell.removeAttribute('t');
      if(typeof input==='number'){
        if(!Number.isFinite(input))throw new Error('Hay un importe no válido en el reporte.');
        cell.setAttribute('t','n');
        if(formula){const f=tag('f');f.textContent=formula;cell.append(f);}
        const v=tag('v');v.textContent=String(input);cell.append(v);
      }else{
        const text=clean(input);if(text.length>32767)throw new Error('Un texto excede el límite de una celda de Excel.');
        cell.setAttribute('t','inlineStr');const is=tag('is'),t=tag('t');t.setAttributeNS('http://www.w3.org/XML/1998/namespace','xml:space','preserve');t.textContent=text;is.append(t);cell.append(is);
      }
    }
    function row(prototype,number,values,formulas={}){
      const r=original.get(prototype).cloneNode(true);r.setAttribute('r',number);
      for(const c of [...r.children]){const letter=c.getAttribute('r').replace(/\d+$/,'');c.setAttribute('r',letter+number);value(c,'');}
      values.forEach((v,j)=>{const c=[...r.children].find(x=>x.getAttribute('r')===column(j+1)+number);if(!c)throw new Error('El formato no contiene la columna esperada.');value(c,v,formulas[j]);});
      // Ajusta solo las filas con referencias extensas, sin reducir el tamaño de letra.
      const widths=i?[15,20,20,48,20,20,20]:[24,20,20,20,20,20,20,20,20,20];
      r.setAttribute('ht',Math.min(409,Math.max(Number(r.getAttribute('ht')), ...values.map((v,j)=>typeof v==='string'?Math.ceil(v.length/widths[j])*15:0))));
      return r;
    }
    const context={4:`${report.empresa}   NIT ${report.nit}`,5:`Proveedor: ${report.proveedor}   NIT ${report.identificacion}`,6:`Referencia: ${report.reference||'Sin referencia'}   Moneda: ${report.currency}`,7:'Generado: '+new Date(report.generadoEnUtc).toLocaleString('es-CO',{timeZone:'America/Bogota'})+' (Colombia)',9:'Facturas seleccionadas. Valores actuales, no corte histórico.'};
    sheetData.replaceChildren(...[...original.entries()].filter(([n])=>n<=11).map(([n,r])=>{if(context[n]){value([...r.children].find(c=>c.getAttribute('r')==='B'+n),context[n]);r.setAttribute('ht',Math.max(24,Math.ceil(context[n].length/(i?140:200))*16));}return r;}));
    for(const m of [...merges.children])if(Number(m.getAttribute('ref').match(/\d+/)[0])>=12)m.remove();
    const merge=(number)=>{const m=tag('mergeCell');m.setAttribute('ref',`B${number}:${last}${number}`);merges.append(m);};
    const records=i?report.movements:report.rows;let at=12;
    for(const entry of records){
      let values,formulas={};
      if(i){const date=Date.parse(entry.fecha+'T00:00:00Z');if(!Number.isFinite(date))throw new Error('Un movimiento no tiene fecha válida.');values=[date/86400000+25569,entry.factura,entry.tipoMovimiento.replaceAll('_',' '),entry.soporte,entry.cargo,entry.abono,'No disponible'];}
      else{values=paymentReportColumns.map(([,key])=>entry[key]);formulas={3:`ROUND(C${at}-D${at},2)`,6:`ROUND(I${at}-(C${at}-D${at}+F${at}+G${at}),2)`};}
      sheetData.append(row(at%2?13:12,at,values,formulas));at++;
    }
    if(records.length){
      const totals=i?['TOTAL','','','',reportRound(records.reduce((n,x)=>n+x.cargo,0)),reportRound(records.reduce((n,x)=>n+x.abono,0)),'']:['TOTAL',...paymentReportColumns.slice(1).map(([,key])=>report.totals[key])];
      const formulas={};totals.forEach((v,j)=>{if(typeof v==='number')formulas[j]=`ROUND(SUM(${column(j+1)}12:${column(j+1)}${at-1}),2)`;});
      sheetData.append(row(14,at,totals,formulas));at+=2;
      const filter=tag('autoFilter');filter.setAttribute('ref',`B11:${last}${11+records.length}`);doc.documentElement.insertBefore(filter,merges);
    }else{sheetData.append(row(16,at,['Sin pagos, notas ni aplicaciones registrados para las facturas seleccionadas.']));merge(at);at+=2;}
    for(const warning of (i?['Banco y consignación no están disponibles. Las notas y reversos no son pagos.']:report.warnings)){
      const r=row(16,at,[warning]);r.setAttribute('ht',Math.max(32,Math.ceil(warning.length/(i?115:180))*16));sheetData.append(r);merge(at);at++;
    }
    merges.setAttribute('count',merges.children.length);
    files[file]=new XMLSerializer().serializeToString(doc);
  }
  return paymentReportZip(files);
}
