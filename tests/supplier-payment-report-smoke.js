const fs=require('fs');
const path=require('path');
const assert=require('assert');
const {chromium}=require('playwright');
(async()=>{
  const root=path.resolve(__dirname,'..'),output=path.join(root,'tmp','payment-report-qa');
  fs.mkdirSync(output,{recursive:true});
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  try{
    const page=await browser.newPage({viewport:{width:1440,height:1000}});
    await page.setContent(fs.readFileSync(path.join(root,'public/index.html'),'utf8').replace(/<script[\s\S]*?<\/script>/g,'').replace(/<link[^>]*>/g,''));
    await page.addStyleTag({path:path.join(root,'public/styles.css')});
    for(const file of ['vendor/jspdf.umd.min.js','app.js','accounts-payable.js','supplier-payment-report.js'])await page.addScriptTag({path:path.join(root,'public',file)});
    await page.evaluate(()=>{
      const invoice={documentoPorPagarId:1,documentoProveedorId:1,terceroId:1,proveedor:'Proveedor de prueba S.A.S.',proveedorIdentificacion:'900123456-7',numeroDocumento:'001234',fechaDocumento:'2026-05-01',fechaVencimiento:'2026-06-01',fechaReconocimiento:'2026-05-02',estado:'VENCIDA',diasVencida:100,moneda:'COP',subtotalBruto:1000000,descuentoTotal:20000,impuestoTotal:186200,cargoTotal:0,valorOriginal:1166200,saldoPendiente:746200};
      window.fixture={empresa:'Comercializadora de prueba S.A.S.',nit:'900000001-1',proveedor:invoice.proveedor,identificacion:invoice.proveedorIdentificacion,generadoEnUtc:'2026-09-09T17:00:00Z',facturas:[invoice,{...invoice,documentoPorPagarId:2,documentoProveedorId:2,numeroDocumento:'FE-2'},{...invoice,documentoPorPagarId:3,documentoProveedorId:3,moneda:'USD'},{...invoice,documentoPorPagarId:4,documentoProveedorId:4,estado:'ANULADA'}],movimientos:[
        {movimientoId:1,documentoPorPagarId:1,factura:'001234',fecha:'2026-05-01',tipoMovimiento:'FACTURA',soporte:'001234',moneda:'COP',cargo:1166200,abono:0},
        ...Array.from({length:40},(_,i)=>({movimientoId:i+2,documentoPorPagarId:1,factura:'001234',fecha:'2026-05-20',tipoMovimiento:'PAGO',soporte:'EG-'+(i+1),moneda:'COP',cargo:0,abono:10000})),
        {movimientoId:42,documentoPorPagarId:1,factura:'001234',fecha:'2026-05-21',tipoMovimiento:'NOTA_CREDITO',soporte:'NC-1',moneda:'COP',cargo:0,abono:20000},
        {movimientoId:43,documentoPorPagarId:2,factura:'FE-2',fecha:'2026-05-21',tipoMovimiento:'PAGO',soporte:'EG-OTRA',moneda:'COP',cargo:0,abono:999}
      ]};
      state.runtimeMode='api';state.erpSession={api:true,superAdmin:true,company:{id:1,currency:'COP'}};
      state.apiContext={masterData:{suppliers:[{id:1,name:invoice.proveedor,identification:invoice.proveedorIdentificacion}]}};
      state.accountsPayable={documentos:fixture.facturas};
      $('#loginView').hidden=true;$('#erpShell').hidden=false;hideWorkspaces();$('#accountsPayableModule').hidden=false;
      populateAccountsPayableSuppliers();elements.accountsPayableSupplier.value='1';renderPayableDashboard();
      window.calls=[];apiRequest=async url=>{calls.push(url);return url.includes('/accounts-payable?')?{documentos:fixture.facturas}:fixture;};download=(name,content)=>{window.saved={name,content};};
    });
    const checks=await page.evaluate(()=>{
      const report=preparePaymentReport(fixture,[1],'COP','Relación 013');
      const fails=fn=>{try{fn();return false;}catch{return true;}};
      const old=structuredClone(fixture);delete old.facturas[0].impuestoTotal;
      const bad=structuredClone(fixture);bad.facturas[0].saldoPendiente=1;
      const csv=buildPaymentReportCsv({...report,reference:'=HYPERLINK("malicioso")'});
      return {net:report.rows[0].neto,payments:report.totals.pagos,balance:report.totals.saldoPendiente,entries:report.movements.length,warnings:report.warnings.length,
        mixed:fails(()=>preparePaymentReport(fixture,[1,3],'COP')),cancelled:fails(()=>preparePaymentReport(fixture,[4],'COP')),missing:fails(()=>preparePaymentReport(old,[1],'COP')),empty:fails(()=>preparePaymentReport(fixture,[],'COP')),
        discrepancy:preparePaymentReport(bad,[1],'COP').warnings.some(x=>x.includes('no concilia')),
        csvSafe:csv.includes("'=HYPERLINK"),leadingZero:csv.includes('"001234"'),noOther:!csv.includes('EG-OTRA')};
    });
    assert.deepStrictEqual(checks,{net:980000,payments:400000,balance:746200,entries:41,warnings:1,mixed:true,cancelled:true,missing:true,empty:true,discrepancy:true,csvSafe:true,leadingZero:true,noOther:true});
    await page.locator('#openPaymentReport').click();
    await page.locator('.payment-report-dialog').waitFor({state:'visible'});
    assert.strictEqual(await page.locator('[data-report-id]').count(),2);
    await page.locator('[data-report-select="none"]').click();assert(await page.locator('[data-report-download="pdf"]').isDisabled());
    await page.locator('[data-report-id="1"]').check();await page.locator('#paymentReportReference').fill('Relación 013');
    await page.screenshot({path:path.join(output,'seleccion.png')});
    await page.locator('[data-report-download="csv"]').click();
    await page.waitForFunction(()=>Boolean(window.saved));
    assert.deepStrictEqual(await page.evaluate(()=>calls),['/api/v1/companies/1/accounts-payable?terceroId=1','/api/v1/companies/1/suppliers/1/statement']);
    assert((await page.evaluate(()=>saved.content)).includes('NC-1'));
    const pdf=await page.evaluate(()=>buildPaymentReportPdf(preparePaymentReport(fixture,[1],'COP','Relación 013')).output('datauristring').split(',')[1]);
    fs.writeFileSync(path.join(output,'relacion.pdf'),Buffer.from(pdf,'base64'));
    const emptyPdf=await page.evaluate(()=>{const copy=structuredClone(fixture);copy.movimientos=copy.movimientos.filter(x=>x.tipoMovimiento==='FACTURA');copy.facturas[0].saldoPendiente=1166200;return buildPaymentReportPdf(preparePaymentReport(copy,[1],'COP')).output('datauristring').split(',')[1];});
    fs.writeFileSync(path.join(output,'sin-pagos.pdf'),Buffer.from(emptyPdf,'base64'));
    await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(output,'seleccion-movil.png')});
    assert(await page.evaluate(()=>document.querySelector('dialog').getBoundingClientRect().width<=innerWidth));
    await page.evaluate(()=>{state.erpSession.company.id=2;window.saved=null;});
    await page.locator('[data-report-download="csv"]').click();
    assert((await page.locator('[data-report-status]').innerText()).includes('empresa activa cambió'));
    assert.strictEqual(await page.evaluate(()=>calls.length),2);
    console.log('Relación: desglose, pagos separados de notas, selección, monedas, anulaciones, datos faltantes, conciliación, CSV seguro, cambio de empresa y PDF multipágina verificados.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
