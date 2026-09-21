// Servidor exclusivamente para QA visual: datos ficticios en memoria, sin SQL ni .env.
// Ejecutar explícitamente: node tests/zeus-ui-server.js (127.0.0.1:4175).
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../public');
const companies=[{empresaId:1,razonSocial:'EMPRESA DEMOSTRACIÓN UNO',nit:'TEST-1',monedaFuncional:'COP'},{empresaId:2,razonSocial:'EMPRESA DEMOSTRACIÓN DOS',nit:'TEST-2',monedaFuncional:'COP'}];
const permissions=['COMPRAS.DOCUMENTO.CREAR','COMPRAS.RECEPCION.CONTABILIZAR','SEGURIDAD.PERMISOS.ADMINISTRAR','MAESTROS.PROVEEDOR.ADMINISTRAR'].map((codigo,i)=>({codigo,permisoId:i+1,nombre:codigo,modulo:'PRUEBAS',accion:'QA'}));
const settings={habilitado:false,servidorEsperado:'servidor-prueba',baseEsperada:'ZEUS_PRUEBA',fuente:'01',serie:'01',unidadNegocio:'01',usuarioZeus:'PRUEBA',tipoFactura:'FA',cuentas:[{concepto:'INVENTARIO',cuenta:'1435'},{concepto:'IVA',cuenta:'2408',tarifa:19},{concepto:'PROVEEDOR',cuenta:'2205'}],proveedores:[{proveedorId:10,codigoProveedor:'P10',codigoTercero:'T10'}]};
const saved=new Map([[1,{version:1,configuracion:structuredClone(settings)}],[2,{version:1,configuracion:structuredClone(settings)}]]);
const receipt={RecepcionId:20,Factura:'PRUEBA-001',Proveedor:'Proveedor ficticio',FechaContable:'2026-09-21',FechaFactura:'2026-02-01',Total:1190000,Impuestos:190000,Retenciones:0,Moneda:'COP',EstadoZeus:'REQUIERE_REVISION'};
const jobs=new Map([[1,[]],[2,[]]]);
const users=new Map([[1,[]],[2,[]]]);
http.createServer(async(req,res)=>{
  const url=new URL(req.url,'http://127.0.0.1');
  const json=(value,code=200)=>{res.writeHead(code,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
  if(url.pathname.startsWith('/erp-api/')){
    let body={};const chunks=[];for await(const chunk of req)chunks.push(chunk);if(chunks.length)body=JSON.parse(Buffer.concat(chunks));
    const endpoint=url.pathname.replace('/erp-api',''),superAdmin=req.headers.authorization==='Bearer qa-super';
    if(endpoint.endsWith('/auth/login'))return json({token:body.correo.startsWith('super')?'qa-super':'qa-normal',nombreCompleto:'Usuario de prueba',usuarioId:body.correo.startsWith('super')?1:2,esSuperAdministrador:body.correo.startsWith('super'),empresaId:body.correo.startsWith('super')?null:1,expiraEnUtc:'2099-01-01'});
    if(endpoint.endsWith('/auth/me'))return json({usuarioId:superAdmin?1:2,esSuperAdministrador:superAdmin,empresaId:superAdmin?null:1});
    if(endpoint==='/api/v1/companies')return json(superAdmin?companies:companies.slice(0,1));
    if(endpoint.includes('/health'))return json({status:'ok',databaseMode:'sqlserver',migrations:50});
    const company=Number(endpoint.match(/companies\/(\d+)/)?.[1]||1);
    if(!superAdmin&&company!==1)return json({error:'Empresa no autorizada'},403);
    if(endpoint.endsWith('/zeus/status'))return json({configurado:true,habilitado:saved.get(company).configuracion.habilitado,despachadorActivo:false});
    if(endpoint.endsWith('/zeus/configuration')){if(req.method==='PUT'){saved.set(company,{version:body.version+1,configuracion:body.configuracion});return json(null);}return json(saved.get(company));}
    if(endpoint.endsWith('/zeus/jobs'))return json(jobs.get(company));
    if(endpoint.endsWith('/zeus/receipts'))return json([receipt]);
    if(endpoint.endsWith('/zeus/connection/check'))return json({contratoDisponible:true,baseDatos:'ZEUS_PRUEBA'});
    if(endpoint.endsWith('/zeus/receipts/20/preview'))return json({huella:'solo-prueba',debito:1190000,credito:1190000,comprobante:{configuracion:saved.get(company).configuracion,origen:{fechaContable:receipt.FechaContable},movimientos:[{regla:settings.cuentas[0],valor:1000000},{regla:settings.cuentas[1],valor:190000,base:1000000,tarifa:19},{regla:settings.cuentas[2],valor:-1190000}]}});
    if(endpoint.endsWith('/zeus/receipts/20/approve')){jobs.set(company,[{ZeusEnvioId:1,RecepcionMercanciaId:20,Factura:receipt.Factura,Proveedor:receipt.Proveedor,FechaContable:receipt.FechaContable,Total:receipt.Total,Estado:'PENDIENTE',Intentos:0}]);return json({envioId:1},202);}
    if(endpoint.endsWith('/permissions'))return json(permissions);
    if(endpoint.endsWith('/security/users')){if(req.method==='POST'){users.get(company).push({usuarioId:99,nombreCompleto:body.nombreCompleto,correo:body.correo,activoGlobal:true,accesoActivo:true,roles:[{rolId:1,nombre:'Administrador'}]});return json({});}return json(users.get(company));}
    if(endpoint.endsWith('/security/roles'))return json([{rolId:1,codigo:'ADMIN',nombre:'Administrador',permisoIds:[1,2,3,4]}]);
    if(endpoint.endsWith('/master-data/suppliers'))return json([{terceroId:10,tipoIdentificacion:'NIT',numeroIdentificacion:'PRUEBA',razonSocial:'Proveedor ficticio',activo:true}]);
    if(endpoint.endsWith('/master-data/articles'))return json([{articuloId:50,codigo:'25',descripcion:'Nevera de prueba',manejaInventario:true,activo:true}]);
    return json([]);
  }
  const file=path.resolve(root,'.'+(url.pathname==='/'?'/index.html':url.pathname));
  if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
  try{const data=fs.readFileSync(file);res.writeHead(200,{'Content-Type':{'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml'}[path.extname(file)]||'application/octet-stream'});res.end(data);}catch{res.writeHead(404);res.end();}
}).listen(4175,'127.0.0.1',()=>console.log('QA ficticio disponible en http://127.0.0.1:4175; sin conexión a bases reales.'));
