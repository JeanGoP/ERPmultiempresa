using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Treasury;
using NexoERP.Api.Zeus;

var root=Directory.GetCurrentDirectory();
var db="EgresoTest_"+Guid.NewGuid().ToString("N");
await using var master=new SqlConnection("Server=(localdb)\\MSSQLLocalDB;Database=master;Integrated Security=True;TrustServerCertificate=True");
await master.OpenAsync();
async Task Exec(SqlConnection c,string sql){await using var q=c.CreateCommand();q.CommandTimeout=180;q.CommandText=sql;await q.ExecuteNonQueryAsync();}
async Task<object?> Scalar(SqlConnection c,string sql){await using var q=c.CreateCommand();q.CommandText=sql;return await q.ExecuteScalarAsync();}
int checks=0;
void Check(bool ok,string name){if(!ok)throw new Exception(name);checks++;Console.WriteLine("OK: "+name);}
async Task Reject(Func<Task> action,string name){try{await action();}catch(Exception e)when(e is ArgumentException or DraftConflict){Check(true,name);return;}throw new Exception("No rechazó: "+name);}
await Exec(master,$"CREATE DATABASE [{db}]");
try
{
    var cs=$"Server=(localdb)\\MSSQLLocalDB;Database={db};Integrated Security=True;TrustServerCertificate=True";
    await using var c=new SqlConnection(cs);await c.OpenAsync();
    foreach(var path in Directory.GetFiles(Path.Combine(root,"database/migrations"),"*.sql").Order())
        foreach(var batch in Regex.Split(await File.ReadAllTextAsync(path),@"(?im)^\s*GO\s*$"))if(!string.IsNullOrWhiteSpace(batch))await Exec(c,batch);
    await Exec(c,"""
        EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
        INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES('A','123','Empresa A'),('B','456','Empresa B');
        INSERT seg.Usuario(Correo,NombreCompleto,EsSuperAdministrador) VALUES('test@invalid.test','Prueba',1);
        INSERT core.Sucursal(EmpresaId,Codigo,Nombre) VALUES(1,'01','Norte'),(2,'01','Otra empresa');
        INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(1,'123','Proveedor',1),(2,'123','Proveedor ajeno',1),(1,'456','Otro proveedor',1);
        INSERT comp.DocumentoProveedor(EmpresaId,TerceroId,TipoDocumento,NumeroDocumento,FechaDocumento,Fuente,Estado,TotalPagar) VALUES(1,1,'FACTURA','F1','20260901','MANUAL','CONTABILIZADO',1000);
        INSERT cxp.DocumentoPorPagar(EmpresaId,DocumentoProveedorId,TerceroId,FechaReconocimiento,FechaDocumento,FechaVencimiento,Moneda,ValorOriginal,SaldoPendiente)
        VALUES(1,1,1,'20260901','20260901','20261001','COP',1000,1000);
        """);
    var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{{"ConnectionStrings:NexoErp",cs}}).Build();
    var factory=new TenantConnectionFactory(config);var repo=new DisbursementRepository(factory);
    var draft=new DisbursementDraft(Guid.NewGuid(),0,1,1,new(2026,9,23),"COP","TRANSFERENCIA","Banco prueba","111005","REF-1","Pago parcial y gasto",
        [new("FACTURA",1,"","Abono F1",200),new("GASTO",null,"519595","Gasto ocasional",25.25m)]);
    var saved=await repo.SaveAsync(1,null,draft,1,default);
    Check(saved.Id>0&&saved.Version==1,"Guarda borrador mixto");
    Check(await repo.SaveAsync(1,null,draft,1,default)==saved,"Reintento idéntico no duplica");
    await Reject(async()=>{await repo.SaveAsync(1,null,draft with{Concepto="Otro"},1,default);},"Misma llave con otro contenido no sobrescribe");
    var updated=draft with{Version=1,Concepto="Actualizado"};
    Check((await repo.SaveAsync(1,saved.Id,updated,1,default)).Version==2,"Control de versión al editar");
    Check((await repo.SaveAsync(1,saved.Id,updated,1,default)).Version==2,"Reintento de edición idempotente");
    await Reject(async()=>{await repo.SaveAsync(1,saved.Id,updated with{Concepto="Edición obsoleta"},1,default);},"Rechaza edición desactualizada");
    await Reject(async()=>{await repo.SaveAsync(2,saved.Id,updated,1,default);},"No modifica borrador de otra empresa");
    Check(await repo.GetAsync(2,saved.Id,default) is null,"No consulta borrador de otra empresa");
    async Task New(DisbursementDraft d)=>await repo.SaveAsync(1,null,d with{OperacionGuid=Guid.NewGuid(),Version=0},1,default);
    await Reject(()=>New(draft with{SucursalId=2}),"Sucursal ajena");
    await Reject(()=>New(draft with{TerceroId=2}),"Beneficiario ajeno");
    await Reject(()=>New(draft with{TerceroId=3}),"Factura de otro proveedor");
    await Reject(()=>New(draft with{Moneda="USD"}),"Moneda distinta de la factura");
    await Reject(()=>New(draft with{FechaContable=new(2026,8,31)}),"Pago anterior al reconocimiento");
    await Reject(()=>New(draft with{Lineas=[new("FACTURA",1,"","Abono",1000.01m)]}),"Abono sobre saldo");
    await Reject(()=>New(draft with{Lineas=[new("GASTO",null,"","Gasto",0.001m)]}),"Sin fracciones ocultas de centavo");
    await Reject(()=>New(draft with{Lineas=[draft.Lineas[0],draft.Lineas[0]]}),"Factura duplicada");
    await Reject(()=>New(draft with{Lineas=[]}),"Sin líneas");
    await Reject(()=>New(draft with{Lineas=[new("GASTO",null,"","Uno",1000000000000m),new("GASTO",null,"","Dos",0.01m)]}),"Límite total conserva precisión monetaria del cliente");
    await Reject(()=>New(draft with{Lineas=[null!]}),"Línea nula");
    await Reject(()=>New(draft with{Lineas=[new("FACTURA",1,"2205","Abono",10)]}),"Cuenta no editable de obligación");
    await Exec(c,"UPDATE ter.Tercero SET Activo=0 WHERE TerceroId=1");
    await Reject(()=>New(draft),"Beneficiario inactivo");
    await Exec(c,"UPDATE ter.Tercero SET Activo=1 WHERE TerceroId=1");
    Check(Convert.ToDecimal(await Scalar(c,"SELECT SaldoPendiente FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=1"))==1000,"Borradores no descuentan cartera");
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM cxp.MovimientoProveedor"))==0,"No crea pagos");
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM core.ZeusEnvio"))==0,"No crea envíos Zeus");
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM audit.Evento WHERE Operacion='GUARDAR_BORRADOR_EGRESO'"))==2,"Auditoría solo en creación/edición efectiva");
    await using(var tenant=await factory.OpenAsync(2,false,default))
        Check(Convert.ToInt32(await Scalar(tenant,"SELECT COUNT(*) FROM cxp.EgresoBorrador"))==0,"RLS oculta borrador ajeno aun sin filtro WHERE");
    var detail=JsonSerializer.SerializeToElement(await repo.GetAsync(1,saved.Id,default));
    Check(detail.GetProperty("datos").GetProperty("Version").GetInt32()==2,"Recupera versión actual, no versión del payload original");
    // Dos creaciones simultáneas con igual operación solo producen un borrador.
    var concurrent=draft with{OperacionGuid=Guid.NewGuid()};
    var pair=await Task.WhenAll(repo.SaveAsync(1,null,concurrent,1,default),repo.SaveAsync(1,null,concurrent,1,default));
    Check(pair[0]==pair[1],"Doble clic concurrente no duplica");
    var migration=await File.ReadAllTextAsync(Path.Combine(root,"database/migrations/058_disbursement_drafts.sql"));
    foreach(var batch in Regex.Split(migration,@"(?im)^\s*GO\s*$"))if(!string.IsNullOrWhiteSpace(batch))await Exec(c,batch);
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM core.SchemaMigration WHERE MigrationId='058_disbursement_drafts'"))==1,"Migración idempotente");
    // Flujo real ERP + transporte sobre un doble SQL local del contrato Zeus.
    foreach(var batch in Regex.Split(await File.ReadAllTextAsync("tests/egreso-zeus-fixture.sql"),@"(?im)^\s*GO\s*$"))if(!string.IsNullOrWhiteSpace(batch))await Exec(c,batch);
    var transportConfig=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{{"Zeus:Companies:1:ConnectionString",cs}}).Build();
    var transport=new ZeusTransport(transportConfig);var posting=new DisbursementPosting(factory,transport);
    var settings=new ZeusSettings(true,"(localdb)\\MSSQLLocalDB",db,"12","00","Local","test","FA",[new("PROVEEDOR","220501")],[],[new("Norte","EGRESO","05","00",[],1,"Local","FA")]);
    var original=new ZeusSnapshot(settings,new(1,1,"F1",new(2026,9,1),new(2026,9,1),new(2026,10,1),1000,0,0,[],ProveedorNombre:"Proveedor"),new(1,"123","123"),[new(new("PROVEEDOR","220501"),-1000)]);
    await Exec(c,"""
        INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin,Estado) VALUES(1,'2026-09','20260901','20260930','ABIERTO');
        INSERT inv.Bodega(EmpresaId,Codigo,Nombre,SucursalId) VALUES(1,'01','Bodega',1);
        INSERT inv.RecepcionMercancia(EmpresaId,Numero,DocumentoProveedorId,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado) VALUES(1,'R1',1,1,1,'20260901','20260901',1,'CONTABILIZADA');
        """);
    await using(var q=c.CreateCommand())
    {
        q.CommandText="INSERT core.ZeusConfiguracion(EmpresaId,Configuracion,ActualizadoPor) VALUES(1,@Settings,1); INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId,Estado,Snapshot) VALUES(1,1,'CONTABILIZADO',@Snapshot);";
        q.Parameters.AddWithValue("@Settings",JsonSerializer.Serialize(settings));q.Parameters.AddWithValue("@Snapshot",JsonSerializer.Serialize(original));await q.ExecuteNonQueryAsync();
    }
    await posting.SaveAccountAsync(1,new(1,"TRANSFERENCIA","111005","TRA"),1,settings,new("111005","Banco","001",1,"123456"),default);
    var payment=draft with{OperacionGuid=Guid.NewGuid(),BancoCaja="",CuentaSalida="",Referencia="1234"};
    async Task Pay(DisbursementDraft d)=>await posting.PostAsync(1,d with{OperacionGuid=Guid.NewGuid()},1,default);
    await Reject(()=>Pay(payment with{FechaContable=new(2026,10,1)}),"Egreso exige período abierto");
    await Reject(()=>Pay(payment with{SucursalId=2}),"Egreso rechaza sucursal ajena");
    await Reject(()=>Pay(payment with{TerceroId=3}),"Egreso rechaza factura ajena");
    await Reject(()=>Pay(payment with{Lineas=[new("FACTURA",1,"","Abono",1000.01m)]}),"Egreso rechaza sobrepago");
    await Reject(()=>Pay(payment with{CuentaSalida="999"}),"No admite sustitución de cuenta desde navegador");
    await Reject(()=>Pay(payment with{Referencia=""}),"Transferencia requiere referencia en Zeus");
    var posted=JsonSerializer.SerializeToElement(await posting.PostAsync(1,payment,1,default));var postedId=posted.GetProperty("id").GetInt64();
    Check(Convert.ToDecimal(await Scalar(c,"SELECT SaldoPendiente FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=1"))==800,"Contabilizar descuenta abono ERP");
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM cxp.MovimientoProveedor WHERE TipoMovimiento='PAGO'"))==1,"Registra aplicación en extracto de proveedor");
    Check(Convert.ToDecimal(await Scalar(c,"SELECT SUM(Debito-Credito) FROM cxp.EgresoLinea"))==0,"Asiento mixto de egreso balanceado");
    await posting.PostAsync(1,payment,1,default);
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM cxp.Egreso"))==1,"Reintento no duplica egreso ni pago");
    await Reject(()=>posting.PostAsync(1,payment with{Concepto="Otro"},1,default),"Misma operación con otro contenido rechazada");
    var queue=new DisbursementQueue(factory);var job=(await queue.ClaimAsync(default))!.Value;
    Check(job.Id==postedId,"Despachador toma egreso persistido");
    var sent=await transport.SendAsync(1,job.Snapshot,job.Key,default);
    Check(sent.Estado=="CONTABILIZADO","Zeus doble SQL confirma saldo y comprobante: "+sent.Error);
    await queue.FinishAsync(1,job.Id,sent,default);
    Check(Convert.ToDecimal(await Scalar(c,"SELECT Sactfac FROM dbo.Facturas_Bu"))==-800,"Zeus doble SQL aplica factura exacta");
    var repeat=await transport.SendAsync(1,job.Snapshot,job.Key,default);
    Check(repeat.Estado=="CONTABILIZADO"&&Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM dbo.DOCUMENT"))==1,"Reenvío de clave existente no duplica Zeus");
    Check(await posting.GetAsync(2,postedId,default) is null,"Egreso definitivo aislado por empresa");
    await using(var tenant=await factory.OpenAsync(1,false,default))
    {
        try{await Exec(tenant,$"UPDATE cxp.Egreso SET Total=1 WHERE EgresoId={postedId}");throw new Exception("Editó comprobante");}catch(SqlException e)when(e.Number==52111){Check(true,"No edita egreso contabilizado");}
        try{await Exec(tenant,"DELETE cxp.EgresoLinea");throw new Exception("Borró líneas");}catch(SqlException e)when(e.Number==52110){Check(true,"No borra asiento contabilizado");}
    }
    // Zeus administra sus acumulados: no dependemos de saldo en el período ni de actualización inmediata.
    await Exec(c,"UPDATE dbo.EgresoTestControl SET UpdateBalance=0; UPDATE dbo.Facturas_Bu SET Anomesfac='202608'");
    var second=payment with{OperacionGuid=Guid.NewGuid(),Lineas=[new("FACTURA",1,"","Abono",100)]};
    await posting.PostAsync(1,second,1,default);var rejectedJob=(await queue.ClaimAsync(default))!.Value;
    var rejected=await transport.SendAsync(1,rejectedJob.Snapshot,rejectedJob.Key,default);await queue.FinishAsync(1,rejectedJob.Id,rejected,default);
    Check(rejected.Estado=="CONTABILIZADO","Confirma comprobante sin depender del acumulado Zeus: "+rejected.Error);
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM dbo.DOCUMENT"))==2,"Conserva comprobante y movimientos confirmados");
    Check(Convert.ToDecimal(await Scalar(c,"SELECT Sactfac FROM dbo.Facturas_Bu"))==-800,"ERP no modifica directamente la cartera Zeus");
    await Exec(c,"UPDATE dbo.EgresoTestControl SET UpdateBalance=1; UPDATE dbo.Facturas_Bu SET Anomesfac='202609'");
    var confirmedAgain=await transport.SendAsync(1,rejectedJob.Snapshot,rejectedJob.Key,default);
    Check(confirmedAgain.Estado=="CONTABILIZADO"&&Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM dbo.DOCUMENT"))==2,"Consultar envío confirmado no repite el procedimiento");
    Check(Convert.ToDecimal(await Scalar(c,"SELECT SaldoPendiente FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=1"))==700,"Repetir envío no descuenta otra vez el ERP");
    Check(Convert.ToDecimal(await Scalar(c,"SELECT Sactfac FROM dbo.Facturas_Bu"))==-800,"No intenta un segundo descuento en Zeus");
    var paymentXml=System.Xml.Linq.XDocument.Parse(ZeusXml.Build(rejectedJob.Snapshot,rejectedJob.Key));
    var invoiceLine=paymentXml.Descendants("Transac").Single(x=>x.Element("INDCPITRA")?.Value=="3");
    var expectedInvoice=rejectedJob.Snapshot.Egreso!.Facturas.Single();
    Check(invoiceLine.Element("CLIPRV")!.Value==rejectedJob.Snapshot.Proveedor.CodigoProveedor,"XML incluye proveedor");
    Check(invoiceLine.Element("NUMEFAC")!.Value==expectedInvoice.Numero&&invoiceLine.Element("TIPOFAC")!.Value==expectedInvoice.Tipo,"XML incluye número y tipo de factura");
    Check(invoiceLine.Element("VENCEFAC")!.Value==expectedInvoice.Vencimiento.ToString("yyyy/MM/dd"),"XML incluye vencimiento de factura");
    Check(decimal.Parse(invoiceLine.Element("VALORTRA")!.Value,System.Globalization.CultureInfo.InvariantCulture)==expectedInvoice.Valor,"XML incluye valor del abono");
    var cashSnapshot=job.Snapshot with{Movimientos=[new(new("GASTO","519595"),10),new(new("BANCO_CAJA","110505"),-10)],Origen=job.Snapshot.Origen with{Total=10},Egreso=new("Caja","","110505","",[],"EFE")};
    Check((await transport.SendAsync(1,cashSnapshot,Guid.NewGuid(),default)).Estado=="CONTABILIZADO","Admite caja con indicador 6 y medio EFE");
    var concurrentPayment=payment with{OperacionGuid=Guid.NewGuid(),Lineas=[new("FACTURA",1,"","Abono",50)]};
    await Task.WhenAll(posting.PostAsync(1,concurrentPayment,1,default),posting.PostAsync(1,concurrentPayment,1,default));
    Check(Convert.ToDecimal(await Scalar(c,"SELECT SaldoPendiente FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=1"))==650,"Doble clic concurrente aplica una sola vez");
    var finalPayment=payment with{OperacionGuid=Guid.NewGuid(),Lineas=[new("FACTURA",1,"","Saldo completo",650)]};await posting.PostAsync(1,finalPayment,1,default);
    Check(Convert.ToString(await Scalar(c,"SELECT Estado FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=1"))=="PAGADA","Pago total cierra obligación");
    await Reject(()=>Pay(payment with{Lineas=[new("FACTURA",1,"","Exceso",1)]}),"Factura pagada no admite otro pago");
    await Exec(c,"INSERT dbo.Facturas_Bu VALUES('202609','123','220501','FA','F2','','','Local',-300),('202609','123','220501','FA','F3','','','Otra BU',-500)");
    var multi=job.Snapshot with{Movimientos=[new(new("PROVEEDOR","220501"),100),new(new("PROVEEDOR","220501"),200),new(new("BANCO_CAJA","111005"),-300)],Origen=job.Snapshot.Origen with{Total=300},Egreso=job.Snapshot.Egreso! with{Facturas=[new(2,"220501","FA","F2","","Local",new(2026,10,1),100),new(3,"220501","FA","F3","","Otra BU",new(2026,10,1),200)]}};
    Check((await transport.SendAsync(1,multi,Guid.NewGuid(),default)).Estado=="CONTABILIZADO","Un egreso aplica varias facturas preservando sus unidades de negocio");
    Check(Convert.ToDecimal(await Scalar(c,"SELECT Sactfac FROM dbo.Facturas_Bu WHERE numefac='F2'"))==-200&&Convert.ToDecimal(await Scalar(c,"SELECT Sactfac FROM dbo.Facturas_Bu WHERE numefac='F3'"))==-300,"Saldos independientes por factura y BU");
    var abandoned=(await queue.ClaimAsync(default))!.Value;
    await Exec(c,$"UPDATE cxp.Egreso SET ActualizadoEnUtc=DATEADD(minute,-20,SYSUTCDATETIME()) WHERE EgresoId={abandoned.Id}");
    await queue.ClaimAsync(default);
    Check(Convert.ToString(await Scalar(c,$"SELECT ZeusEstado FROM cxp.Egreso WHERE EgresoId={abandoned.Id}"))=="INCIERTO","Envío abandonado no se reenvía automáticamente");
    try{await queue.RetryAsync(1,abandoned.Id,1,default);throw new Exception("Reenvió incierto");}catch(SqlException e)when(e.Number==52114){Check(true,"Bloquea reenvío de resultado incierto");}
    await using(var otherTenant=await factory.OpenAsync(2,false,default))
        Check(Convert.ToInt32(await Scalar(otherTenant,"SELECT COUNT(*) FROM cxp.Egreso"))==0&&Convert.ToInt32(await Scalar(otherTenant,"SELECT COUNT(*) FROM cxp.EgresoLinea"))==0,"RLS protege cabecera y asiento aun sin WHERE");
    foreach(var batch in Regex.Split(await File.ReadAllTextAsync("database/migrations/059_disbursement_posting.sql"),@"(?im)^\s*GO\s*$"))if(!string.IsNullOrWhiteSpace(batch))await Exec(c,batch);
    Check(Convert.ToInt32(await Scalar(c,"SELECT COUNT(*) FROM core.SchemaMigration WHERE MigrationId='059_disbursement_posting'"))==1,"Migración 059 idempotente");
    Console.WriteLine($"{checks} comprobaciones de egresos correctas.");
}
finally
{
    SqlConnection.ClearAllPools();await Exec(master,$"ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{db}]");
}
