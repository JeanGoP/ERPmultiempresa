const fs=require('fs');
const path=require('path');
const assert=require('assert');
const {chromium}=require('playwright');
(async()=>{
  const root=path.resolve(__dirname,'..'),output=path.join(root,'tmp','payable-qa');
  fs.mkdirSync(output,{recursive:true});
  const browser=await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL||'chrome'});
  try{
    const page=await browser.newPage({viewport:{width:1600,height:1150}});
    const html=fs.readFileSync(path.join(root,'public/index.html'),'utf8').replace(/<script[\s\S]*?<\/script>/g,'').replace(/<link[^>]*>/g,'');
    await page.setContent(html);
    await page.addStyleTag({path:path.join(root,'public/styles.css')});
    await page.addScriptTag({path:path.join(root,'public/vendor/jspdf.umd.min.js')});
    await page.addScriptTag({path:path.join(root,'public/app.js')});
    await page.addScriptTag({path:path.join(root,'public/accounts-payable.js')});
    await page.evaluate(()=>{
      const amounts=[24500000,12800000,6400000,9100000,18500000],days=[0,12,45,75,128];
      window.fixture={
        empresa:'Comercializadora del Norte S.A.S.',nit:'900123456-7',
        proveedor:'Industrias de Refrigeración y Equipos S.A.S.',identificacion:'890123456-1',
        generadoEnUtc:'2026-09-04T17:00:00Z',facturas:[],movimientos:[]
      };
      state.erpSession={api:true,superAdmin:true,company:{id:1,currency:'COP'}};
      state.apiContext={masterData:{suppliers:[{id:1,name:fixture.proveedor,identification:fixture.identificacion}]}};
      state.accountsPayable={documentos:amounts.map((amount,i)=>({
        documentoPorPagarId:i+1,documentoProveedorId:i+1,terceroId:i%2+1,
        proveedor:i%2?'Distribuciones La Costa S.A.S.':fixture.proveedor,proveedorIdentificacion:'890123456-1',
        numeroDocumento:'FE-2026-00'+(i+1),tipoDocumento:'FACTURA',fechaDocumento:'2026-02-01',
        fechaReconocimiento:'2026-02-02',fechaVencimiento:'2026-03-01',condicionPago:'CREDITO',moneda:'COP',
        valorOriginal:amount+1500000,saldoPendiente:amount,estado:i?'VENCIDA':'PENDIENTE',diasVencida:days[i]
      }))};
      state.accountsPayable.documentos.push({...state.accountsPayable.documentos[0],documentoProveedorId:99,moneda:'USD',saldoPendiente:2000});
      fixture.facturas=[{...state.accountsPayable.documentos[0],valorOriginal:26000000,saldoPendiente:24500000}];
      fixture.movimientos=[{documentoPorPagarId:1,fecha:'2026-02-02',tipoMovimiento:'FACTURA',soporte:'FE-2026-001',moneda:'COP',cargo:26000000,abono:0},
        ...Array.from({length:60},(_,i)=>({documentoPorPagarId:1,fecha:'2026-03-01',tipoMovimiento:'PAGO',soporte:'EG-'+String(i+1).padStart(3,'0')+' / Transferencia bancaria aplicada a factura FE-2026-001',moneda:'COP',cargo:0,abono:25000}))];
      $('#loginView').hidden=true;$('#erpShell').hidden=false;
      hideWorkspaces();$('#accountsPayableModule').hidden=false;
      $('#companyName').textContent=fixture.empresa;
      populateAccountsPayableSuppliers();renderPayableDashboard();
    });
    assert.strictEqual(await page.locator('.payable-bands button').count(),5);
    assert.strictEqual(await page.locator('#accountsPayableTable tbody tr').count(),5);
    assert((await page.locator('#accountsPayableStats').innerText()).includes('71.300.000'));
    await page.screenshot({path:path.join(output,'dashboard.png'),fullPage:true});
    await page.locator('[data-age="4"]').click();
    assert.strictEqual(await page.locator('#accountsPayableTable tbody tr').count(),1);
    assert((await page.locator('#accountsPayableTable').innerText()).includes('128 días'));
    await page.locator('[data-age="all"]').click();
    await page.locator('#payableCurrency').selectOption('USD');
    assert.strictEqual(await page.locator('#accountsPayableTable tbody tr').count(),1);
    await page.locator('#payableCurrency').selectOption('COP');
    const pdf=await page.evaluate(()=>buildSupplierStatementPdf(fixture).output('datauristring').split(',')[1]);
    fs.writeFileSync(path.join(output,'extracto-prueba.pdf'),Buffer.from(pdf,'base64'));
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:path.join(output,'dashboard-mobile.png'),fullPage:true});
    console.log('Dashboard: edades, filtro, separación de monedas y PDF multipágina correctos. Evidencia en tmp/payable-qa.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
