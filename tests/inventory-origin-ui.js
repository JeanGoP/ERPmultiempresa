const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('playwright');
(async()=>{
  const root=path.resolve(__dirname,'..'),out=path.join(root,'tmp','origin-qa');fs.mkdirSync(out,{recursive:true});
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  try{
    const page=await browser.newPage({viewport:{width:1500,height:1050}});
    await page.setContent(fs.readFileSync(path.join(root,'public/index.html'),'utf8').replace(/<script[\s\S]*?<\/script>/g,'').replace(/<link[^>]*>/g,''));
    await page.addStyleTag({path:path.join(root,'public/styles.css')});
    for(const script of ['app.js','accounts-payable.js','inventory-origin.js'])await page.addScriptTag({path:path.join(root,'public',script)});
    await page.evaluate(()=>{
      state.erpSession={api:true,superAdmin:true,company:{id:1}};state.runtimeMode='api';
      state.apiContext={warehouses:[{bodegaId:1,codigo:'01',nombre:'Principal'},{bodegaId:2,codigo:'02',nombre:'Logística'}],periods:[{periodoInventarioId:1,codigo:'2026-09',estado:'ABIERTO'}]};
      $('#loginView').hidden=true;$('#erpShell').hidden=false;hideWorkspaces();elements.inventoryModule.hidden=false;state.inventoryView='aging';
      elements.inventoryOperationPanel.hidden=false;populateInventoryWarehouses();
      originAgeRows=[8,45,75,125,240].map((dias,i)=>({recepcionMercanciaId:i+1,articuloId:25,codigo:'25',descripcion:'Nevera No Frost 350 litros',factura:'FE-2026-'+(100+i),proveedor:'Distribuidora del Caribe',entrada:'ENT-'+(100+i),fechaEntrada:'2026-02-01',bodega:i%2?'Logística':'Principal',cantidad:i+1,dias,serializado:true}));
      apiRequest=async()=>originAgeRows;
      showInventoryView('aging');
    });
    await page.locator('#inventoryOperationPanel .payable-bands button').first().waitFor();
    assert.strictEqual(await page.locator('#inventoryOperationPanel .payable-bands button').count(),5);
    assert.strictEqual(await page.locator('#inventoryTable tbody tr').count(),5);
    await page.screenshot({path:path.join(out,'edades.png'),fullPage:true});
    await page.locator('#inventoryOperationPanel .payable-bands button').last().click();
    assert.strictEqual(await page.locator('#inventoryTable tbody tr').count(),1);
    assert((await page.locator('#inventoryTable').innerText()).includes('240'));
    await page.evaluate(()=>{
      apiRequest=async()=>[{recepcionMercanciaLineaId:1,codigo:'25',descripcion:'Nevera',cantidad:1,bodegaId:1},{recepcionMercanciaLineaId:2,codigo:'40',descripcion:'Lavadora',cantidad:2,bodegaId:1}];
      window.distributionResult=null;void chooseReceiptWarehouses('/test').then(x=>window.distributionResult=x);
    });
    await page.locator('.origin-dialog').waitFor();
    await page.locator('.origin-dialog select').first().selectOption('2');
    await page.getByLabel('Bodega para 25',{exact:true}).selectOption('1');
    await page.screenshot({path:path.join(out,'bodegas.png'),fullPage:true});
    await page.getByRole('button',{name:'Confirmar bodegas y contabilizar'}).click();
    assert.deepStrictEqual(await page.evaluate(()=>distributionResult),[{recepcionMercanciaLineaId:1,bodegaId:1},{recepcionMercanciaLineaId:2,bodegaId:2}]);
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:path.join(out,'edades-mobile.png'),fullPage:true});
    console.log('QA UI: dashboard por edades, filtro y distribución individual correctos.');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
