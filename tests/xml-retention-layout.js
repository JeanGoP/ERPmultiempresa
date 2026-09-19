const {chromium}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
  const browser=await chromium.launch({channel:'chrome',headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1100,height:700}});
    await page.setContent('<main style="padding:24px"><div class="amount-grid"><div class="amount-card" id="retention"><span>Retenciones</span></div><div class="amount-card total"><span>Total a pagar</span><strong id="payable">10000</strong></div></div></main>');
    await page.addStyleTag({content:fs.readFileSync('public/styles.css','utf8')});
    const source=fs.readFileSync('public/app.js','utf8');
    await page.addScriptTag({content:`
      const state={purchaseWorkflow:null};
      const invoice={items:[{lineTotal:10000,tax:0,retention:0}],retentions:[],totals:{retentions:0,payable:10000}};
      function renderInvoice(){document.querySelector('#payable').textContent=invoice.totals.payable;}
      function showError(message){throw Error(message);}
      ${source.slice(source.indexOf('function updateXmlRetentionTotal('),source.indexOf('function buildInvoiceClassificationTable('))}
      document.querySelector('#retention').append(buildXmlRetentionInput(invoice));
    `});
    await page.getByRole('spinbutton',{name:'Retención total'}).fill('120');
    await page.getByRole('spinbutton',{name:'Retención total'}).press('Tab');
    assert.equal(await page.locator('#payable').textContent(),'9880');
    await page.setViewportSize({width:390,height:844});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    const bounds=await page.locator('input').evaluate(input=>{const a=input.getBoundingClientRect(),b=input.parentElement.getBoundingClientRect();return a.left>=b.left&&a.right<=b.right;});
    assert.equal(bounds,true);
    await page.evaluate(()=>{state.purchaseWorkflow={documentId:1};document.querySelector('input').replaceWith(buildXmlRetentionInput(invoice));});
    assert.equal(await page.locator('input').isDisabled(),true);
    console.log('QA navegador: retención superior editable, total actualizado, diseño móvil y bloqueo después de guardar correctos.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
