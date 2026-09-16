// NODE_PATH may point to the bundled runtime's node_modules (Playwright).
const {chromium}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const source=fs.readFileSync('public/app.js','utf8');
const section=(start,end)=>source.slice(source.indexOf(start),source.indexOf(end));
(async()=>{
  const browser=await chromium.launch({channel:'chrome',headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1200,height:900}});
    await page.setContent('<main style="padding:24px"><div id="preview"></div></main>');
    await page.addStyleTag({content:fs.readFileSync('public/styles.css','utf8')});
    await page.addScriptTag({content:`
      const data={articles:[{id:1,code:'N-25',description:'Nevera de prueba de descripción larga',type:'INVENTARIO',active:true}]};
      const state={erpSession:{company:{id:24}}};
      const classificationLabels={inventory:'Mercancía inventariable'};
      const getCompanyMasterData=()=>({data});
      const mappingForLine=()=>null;
      const compatibleArticles=()=>data.articles;
      const findById=(rows,id)=>rows.find(x=>x.id===id);
      const invoice={items:[{line:1,code:'25',description:'Nevera de prueba con descripción larga y espacios para comprobar el ajuste',classification:'inventory'}],brandRecognition:{companyId:'24',status:'ready',brands:['HACEB']}};
      ${section('function xmlBrandLabel(','async function recognizeXmlBrands(')}
      ${section('function buildHomologationPanel(','function buildInvoiceClassificationTable(')}
      document.querySelector('#preview').append(buildHomologationPanel(invoice));
    `});
    assert.deepEqual(await page.locator('th').allTextContents(),['Producto del proveedor (XML)','Marca','Artículo correspondiente en el sistema']);
    assert.equal(await page.locator('td').nth(1).textContent(),'HACEB');
    const bounds=await page.locator('select').evaluate(select=>{const a=select.getBoundingClientRect(),b=select.parentElement.getBoundingClientRect();return {left:a.left,right:a.right,parentLeft:b.left,parentRight:b.right};});
    assert.ok(bounds.left>=bounds.parentLeft&&bounds.right<=bounds.parentRight,'El selector debe permanecer dentro de su columna');
    fs.mkdirSync('tmp/brand-qa',{recursive:true});
    await page.screenshot({path:'tmp/brand-qa/desktop.png',fullPage:true});
    await page.setViewportSize({width:390,height:844});
    assert.ok(await page.locator('td').nth(1).isVisible());
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth);
    assert.equal(overflow,false,'La tabla móvil no debe desbordar la página');
    await page.screenshot({path:'tmp/brand-qa/mobile.png',fullPage:true});
    console.log('QA visual marcas: tres columnas, selector contenido y vista móvil sin desbordamiento.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
