const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('playwright');
(async()=>{
  const root=path.resolve(__dirname,'..'),out=path.join(root,'tmp','homologation-qa');fs.mkdirSync(out,{recursive:true});
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  try{
    const page=await browser.newPage({viewport:{width:1400,height:850}});
    await page.setContent(fs.readFileSync(path.join(root,'public/index.html'),'utf8').replace(/<script[\s\S]*?<\/script>/g,'').replace(/<link[^>]*>/g,''));
    await page.addStyleTag({path:path.join(root,'public/styles.css')});
    await page.addScriptTag({path:path.join(root,'public/app.js')});
    await page.evaluate(()=>{
      getCompanyMasterData=()=>({data:{articles:[{id:1,code:'MOT-25',description:'MOTOCICLETA 160 FI ABS NEGRO NEBULOSA MODELO 2027 / '+ 'Descripción extensa '.repeat(12),active:true,inventory:true}],mappings:[]}});
      mappingForLine=(_data,_invoice,item)=>item.line===1?{articleId:1}:null;
      const fixture={items:[1,2,3].map(line=>({line,code:'COD-PROVEEDOR-'+line,description:'MOTOCICLETA 160 FI ABS NG GRIS GRAFITO NEGRO NEBULOSA MODELO 2027 (159.7CC)',classification:'inventory'}))};
      const container=document.createElement('main');container.className='invoice-table-card';container.style.cssText='margin:20px;min-width:0';container.append(buildHomologationPanel(fixture));document.body.replaceChildren(container);
    });
    for(const width of [1400,800,390]){
      await page.setViewportSize({width,height:950});
      const geometry=await page.evaluate(()=>{
        const wrap=document.querySelector('.homologation-table');
        return {overflow:wrap.scrollWidth>wrap.clientWidth+1,rows:[...wrap.querySelectorAll('tbody tr')].map(row=>{
          const select=row.querySelector('select').getBoundingClientRect(),badge=row.querySelector('.mapping-status').getBoundingClientRect(),cell=row.lastElementChild.getBoundingClientRect();
          return select.right<=cell.right+1&&select.left>=cell.left&&badge.top>=select.bottom;
        })};
      });
      assert(!geometry.overflow,'Desbordamiento horizontal a '+width);assert(geometry.rows.every(Boolean),'Selector o estado superpuesto');
      await page.screenshot({path:path.join(out,'tabla-'+width+'.png'),fullPage:true});
    }
    assert.strictEqual(await page.getByText('Falta seleccionar',{exact:true}).count(),2);
    assert.strictEqual(await page.getByText('Relacionado',{exact:true}).count(),1);
    assert.strictEqual(await page.getByRole('combobox').count(),3);
    console.log('Homologación: sin desbordamiento ni superposición a 1400, 800 y 390 px, incluso con opciones extensas.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
