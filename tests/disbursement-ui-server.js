// Prueba visual local aislada: datos ficticios en memoria, sin API ni SQL remotos.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const files=new Set(['styles.css','tables-compact.css','disbursements.css','disbursements.js']);
const html=`<!doctype html><html lang="es"><meta charset="utf-8"><link rel="stylesheet" href="/styles.css"><link rel="stylesheet" href="/tables-compact.css"><link rel="stylesheet" href="/disbursements.css"><body><button id="disbursementsNav">Comprobantes de egreso</button>
<script>
const state={erpSession:{api:true,superAdmin:true,company:{id:1,name:'Empresa de prueba'}}};
// Confirmación aceptada únicamente en esta página de QA sin efectos externos.
const hasPermission=()=>true,showError=alert,confirm=()=>true;let rows=[];
async function apiRequest(url,opts={}){
 await new Promise(r=>setTimeout(r,80));
 if(url.includes('/options'))return {sucursales:[{id:1,codigo:'01',nombre:'Principal'}],beneficiarios:[{id:1,identificacion:'123',nombre:'Proveedor de prueba'}],facturas:[{id:1,numero:'F-100',moneda:'COP',original:1000,saldo:1000,fecha:'2026-09-01',vence:'2026-10-01'}]};
 if(url.endsWith('/accounts'))return [{sucursalId:1,medioPago:'TRANSFERENCIA',cuenta:'111005',nombre:'Banco prueba',monedaZeus:'TRA',version:1}];
 if(url.endsWith('/cash-chart'))return {cuentas:[{codigo:'111005',nombre:'Banco prueba'}],medios:[{codigo:'TRA',nombre:'Transferencia'}]};
 const id=Number(url.split('/').pop());
 if(opts.method){const datos=JSON.parse(opts.body),total=datos.lineas.reduce((s,l)=>s+l.valor,0),row={id:rows.length+1,datos,asiento:{origen:{total},movimientos:[{regla:{cuenta:'220501',concepto:'PROVEEDOR'},valor:total},{regla:{cuenta:'111005',concepto:'BANCO_CAJA'},valor:-total}],egreso:{facturas:datos.lineas.filter(l=>l.tipo==='FACTURA').map(l=>({numero:'F-100',valor:l.valor}))}}};rows.push(row);return {id:row.id,estado:'CONTABILIZADO',zeusEstado:'PENDIENTE'};}
 if(id)return rows.find(x=>x.id===id);
 return {items:rows.map(x=>({id:x.id,fecha:x.datos.fechaContable,beneficiario:'Proveedor de prueba',moneda:x.datos.moneda,total:x.datos.lineas.reduce((s,l)=>s+l.valor,0),estado:'CONTABILIZADO',zeusEstado:'CONTABILIZADO',fuente:'05',documento:'0000000001'})),siguiente:null};
}
</script><script src="/disbursements.js"></script></body></html>`;
const server=http.createServer((req,res)=>{
 const file=(req.url||'').slice(1);
 if(file===''){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(html);}
 if(!files.has(file)){res.statusCode=404;return res.end();}
 res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript; charset=utf-8':'text/css; charset=utf-8');res.end(fs.readFileSync(path.join(__dirname,'../public',file)));
});
server.listen(4178,'127.0.0.1',()=>console.log('QA egresos aislada: http://127.0.0.1:4178/'));
