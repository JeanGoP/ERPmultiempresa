using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.MasterData;
using NexoERP.Api.Zeus;

static class SupplierSyncTests
{
    public static async Task Run(string cs,string root,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        q.CommandText="""
            ALTER TABLE ter.Tercero ALTER COLUMN EmpresaId bigint NOT NULL;
            ALTER TABLE ter.Tercero ALTER COLUMN TerceroId bigint NOT NULL;
            ALTER TABLE ter.Tercero ADD CONSTRAINT UQ_TestTercero UNIQUE(EmpresaId,TerceroId);
            ALTER TABLE ter.Tercero ADD TipoIdentificacion varchar(10),DigitoVerificacion char(1),
              NombreComercial nvarchar(200),CodigoResponsabilidadFiscal nvarchar(100),RegimenFiscalCodigo nvarchar(20),RegimenFiscalNombre nvarchar(100),
              Direccion nvarchar(300),Ciudad nvarchar(100),DepartamentoCodigo nvarchar(20),Departamento nvarchar(100),CodigoPostal nvarchar(20),Pais nvarchar(100),
              ContactoNombre nvarchar(150),Telefono nvarchar(50),Correo nvarchar(254),SitioWeb nvarchar(300),DatosXmlJson nvarchar(max),EsProveedor bit NOT NULL DEFAULT 1,Activo bit NOT NULL DEFAULT 1;
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="UPDATE ter.Tercero SET TipoIdentificacion='NIT',NumeroIdentificacion='800000010'";await q.ExecuteNonQueryAsync();
        var migration=await File.ReadAllTextAsync(Path.Combine(root,"database/migrations/053_supplier_zeus_sync.sql"));
        for(var pass=0;pass<2;pass++)foreach(var batch in System.Text.RegularExpressions.Regex.Split(migration,@"(?im)^\s*GO\s*$"))
        {if(string.IsNullOrWhiteSpace(batch))continue;q.CommandText=batch;await q.ExecuteNonQueryAsync();}
        check(true,"Migración 053 idempotente con FK y RLS en base aislada");
        var supplierSql=await File.ReadAllTextAsync(Path.Combine(root,"database/migrations/042_supplier_complete_data.sql"));
        var signature=supplierSql[supplierSql.IndexOf("CREATE OR ALTER PROCEDURE ter.usp_GuardarProveedor")..].Split("\nAS",2)[0];
        q.CommandText=signature+"""

            AS BEGIN
              SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
              DECLARE @Id bigint;
              SELECT @Id=TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND NumeroIdentificacion=@NumeroIdentificacion;
              IF @Id IS NULL BEGIN
                SELECT @Id=ISNULL(MAX(TerceroId),100)+1 FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK);
                INSERT ter.Tercero(EmpresaId,TerceroId,TipoIdentificacion,NumeroIdentificacion,RazonSocial) VALUES(@EmpresaId,@Id,@TipoIdentificacion,@NumeroIdentificacion,@RazonSocial);
              END;
              UPDATE ter.Tercero SET RazonSocial=@RazonSocial,Direccion=@Direccion,CiudadCodigo=@CiudadCodigo,Ciudad=@Ciudad,PaisCodigo=@PaisCodigo,DatosXmlJson=@DatosXmlJson WHERE EmpresaId=@EmpresaId AND TerceroId=@Id;
              COMMIT; SELECT @Id Id,CONVERT(bit,1) Creado;
            END
            """;await q.ExecuteNonQueryAsync();
        var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["ConnectionStrings:NexoErp"]=cs,["Zeus:Companies:1:ConnectionString"]=cs}).Build();
        var factory=new TenantConnectionFactory(config);var masters=new MasterDataRepository(factory);var repo=new ZeusRepository(factory);var transport=new ZeusTransport(config);var sync=new ZeusSupplierSync(factory,repo,masters,transport);
        var settings=new ZeusSettings(false,c.DataSource,c.Database,"01","01","01","ERP","FA",[new("PROVEEDOR","2205")],[]);
        var old=await repo.SettingsAsync(1,default);await repo.SaveSettingsAsync(1,1,new(old!.Version,settings),default);
        SaveSupplierRequest Input(string nit)=>new("NIT",nit,"1","Proveedor XML",null,null,null,null,"Calle prueba","08001","Barranquilla",null,null,null,"CO","Colombia",null,null,null,null,"{\"AdditionalAccountID\":[{\"value\":\"1\"}]}",1);
        var saved=await masters.SaveSupplierAsync(1,Input("900000001"),default);
        check((await masters.GetSuppliersAsync(1,default)).Single(s=>s.TerceroId==saved.Id).ZeusEstado is null,"Creación manual ERP no se encola automáticamente");
        await masters.SaveSupplierAsync(1,Input("900000001"),default,fromXml:true);
        await masters.SaveSupplierAsync(1,Input("900000001"),default,fromXml:true);
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;SELECT COUNT(*) FROM core.ZeusProveedorEnvio";
        check(Convert.ToInt32(await q.ExecuteScalarAsync())==1,"Reimportar XML no duplica trabajo");
        var claims=await Task.WhenAll(sync.ClaimAsync(default),sync.ClaimAsync(default));
        check(claims.Count(j=>j is not null)==1,"Dos workers no envían el mismo proveedor");var job=claims.Single(j=>j is not null)!;
        try{await sync.StartManualAsync(1,saved.Id,1,settings,default);throw new Exception("Permitió envío paralelo");}catch(SqlException e)when(e.Number==51761){check(true,"Envío manual bloqueado mientras trabaja la cola");}
        q.CommandText="UPDATE dbo.SupplierTestMode SET Mode='OK'";await q.ExecuteNonQueryAsync();
        var result=await sync.ProcessAsync(job,default);check(result.Estado=="CREADO","XML crea proveedor automáticamente usando conexión de su empresa");await sync.FinishAsync(job,result,default);
        check((await masters.GetSuppliersAsync(1,default)).Single(s=>s.TerceroId==saved.Id).ZeusEstado=="CREADO","Estado automático visible en el maestro");
        check((await sync.ProcessAsync(job with{BaseDatos="OTRA_BASE"},default)).Estado=="PENDIENTE","Cambio de destino bloquea envío automático");
        await masters.SaveSupplierAsync(1,Input("900000001"),default,fromXml:true);check(await sync.ClaimAsync(default) is null,"Reimportar proveedor confirmado no vuelve a enviar");
        var missing=await masters.SaveSupplierAsync(2,Input("900000003"),default,fromXml:true);var other=(await sync.ClaimAsync(default))!;
        var pending=await sync.ProcessAsync(other,default);check(pending.Estado=="PENDIENTE","Empresa sin destino conserva proveedor y motivo pendiente");await sync.FinishAsync(other,pending,default);
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=2;SELECT COUNT(*) FROM core.ZeusProveedorEnvio WHERE EmpresaId=1";
        check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"RLS impide leer envíos de otra empresa");
        check(!(await masters.GetSuppliersAsync(1,default)).Any(s=>s.NumeroIdentificacion=="900000003"),"Listado no cruza proveedores de empresas");
        var failure=await masters.SaveSupplierAsync(1,Input("900000002"),default,fromXml:true);var failedJob=(await sync.ClaimAsync(default))!;
        q.CommandText="UPDATE dbo.SupplierTestMode SET Mode='RETURNFAIL'";await q.ExecuteNonQueryAsync();
        var rejected=await sync.ProcessAsync(failedJob,default);await sync.FinishAsync(failedJob,rejected,default);
        check((await masters.GetSuppliersAsync(1,default)).Single(s=>s.TerceroId==failure.Id).ZeusEstado=="PENDIENTE","Fallo Zeus no revierte proveedor ERP y guarda causa");
        check(await sync.ClaimAsync(default) is null,"No reintenta automáticamente fallos pendientes");
        q.CommandText="UPDATE dbo.SupplierTestMode SET Mode='OK'";await q.ExecuteNonQueryAsync();
        var manual=await sync.StartManualAsync(1,failure.Id,1,settings,default);var supplier=(await masters.GetSuppliersAsync(1,default)).Single(s=>s.TerceroId==failure.Id);
        var retry=await transport.SendSupplierAsync(1,settings,supplier,new(),default);await sync.FinishAsync(manual,retry,default);
        check(retry.Estado=="CREADO","Enviar a Zeus recupera un pendiente sin duplicar");
        check(ZeusTransport.SupplierFingerprint(settings,supplier)==ZeusTransport.SupplierFingerprint(settings,supplier with{ZeusEstado="CREADO",ZeusMensaje="Otro"}),"Estado operativo no invalida huella de datos del proveedor");
        var abandoned=await sync.StartManualAsync(1,failure.Id,1,settings,default);
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;UPDATE core.ZeusProveedorEnvio SET ActualizadoEnUtc=DATEADD(minute,-20,SYSUTCDATETIME()) WHERE TerceroId="+failure.Id;await q.ExecuteNonQueryAsync();
        check(await sync.ClaimAsync(default) is null,"Envío abandonado no se repite");
        await sync.FinishAsync(abandoned,new("CREADO","","Respuesta tardía"),default);
        check((await masters.GetSuppliersAsync(1,default)).Single(s=>s.TerceroId==failure.Id).ZeusEstado=="INCIERTO","Respuesta tardía no sobrescribe revisión requerida");
        var natural=await masters.SaveSupplierAsync(1,Input("900000004") with{DatosXmlJson="{\"AdditionalAccountID\":[{\"value\":\"2\"}]}"},default,fromXml:true);
        var naturalJob=(await sync.ClaimAsync(default))!;var naturalResult=await sync.ProcessAsync(naturalJob,default);await sync.FinishAsync(naturalJob,naturalResult,default);
        check((await masters.GetSuppliersAsync(1,default)).Single(s=>s.TerceroId==natural.Id).ZeusEstado=="PENDIENTE"&&naturalResult.Mensaje.Contains("nombres"),"Persona natural pendiente sin inventar nombres");
        q.CommandText="CREATE TRIGGER core.TestRejectQueue ON core.ZeusProveedorEnvio AFTER INSERT AS BEGIN IF EXISTS(SELECT 1 FROM inserted i JOIN ter.Tercero t ON t.EmpresaId=i.EmpresaId AND t.TerceroId=i.TerceroId WHERE t.NumeroIdentificacion='900000009') THROW 51999,'Fallo de cola simulado',1; END";await q.ExecuteNonQueryAsync();
        try{await masters.SaveSupplierAsync(1,Input("900000009"),default,fromXml:true);throw new Exception("Ignoró fallo cola");}catch(SqlException e)when(e.Number==51999){check(true,"Fallo de cola revierte toda la transacción ERP");}
        check(!(await masters.GetSuppliersAsync(1,default)).Any(s=>s.NumeroIdentificacion=="900000009"),"Proveedor y cola se guardan atómicamente");
    }
}
