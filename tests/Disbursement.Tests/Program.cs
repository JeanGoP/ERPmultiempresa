using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Treasury;

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
    Console.WriteLine($"{checks} comprobaciones de egresos correctas.");
}
finally
{
    SqlConnection.ClearAllPools();await Exec(master,$"ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{db}]");
}
