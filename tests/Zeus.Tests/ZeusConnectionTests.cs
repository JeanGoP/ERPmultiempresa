using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

internal static class ZeusConnectionTests
{
    public static async Task Run(string cs,string root,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        // Este conjunto usa un esquema mínimo, no el ERP completo de Disbursement.Tests.
        q.CommandText="IF SCHEMA_ID('cxp') IS NULL EXEC('CREATE SCHEMA cxp'); IF OBJECT_ID('cxp.Egreso') IS NULL CREATE TABLE cxp.Egreso(EmpresaId bigint,ZeusEstado varchar(20));";await q.ExecuteNonQueryAsync();
        var migration=await File.ReadAllTextAsync(Path.Combine(root,"database/migrations/057_company_zeus_connection.sql"));
        for(int pass=0;pass<2;pass++)foreach(var batch in System.Text.RegularExpressions.Regex.Split(migration,@"(?im)^\s*GO\s*$")){if(string.IsNullOrWhiteSpace(batch))continue;q.CommandText=batch;await q.ExecuteNonQueryAsync();}
        check(true,"Migración 057 idempotente");
        q.CommandText="INSERT core.Empresa(EmpresaId,Codigo,Nit,RazonSocial) VALUES(3,'CON3','3','Conexión 3'),(4,'CON4','4','Conexión 4')";await q.ExecuteNonQueryAsync();
        var legacy=new SqlConnectionStringBuilder(cs){Password="legacy-test-secret"}.ConnectionString;
        var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["ConnectionStrings:NexoErp"]=cs,["Zeus:Companies:4:ConnectionString"]=legacy}).Build();
        var factory=new TenantConnectionFactory(config);var store=new ZeusConnectionStore(factory,config,new EphemeralDataProtectionProvider());
        async Task Save(long company,ZeusConnectionInput input,bool commit=true){await using var cc=await factory.OpenAsync(company,false,default);await using var tx=(SqlTransaction)await cc.BeginTransactionAsync(IsolationLevel.Serializable);await store.SaveAsync(cc,tx,company,1,input,default);if(commit)await tx.CommitAsync();else await tx.RollbackAsync();}
        const string password="solo-prueba-secreta-123";
        var input=new ZeusConnectionInput("servidor-test","base-test","usuario-sql",password,"usuario-contable");
        await Save(3,input,false);check((await store.GetAsync(3,default)).Origen=="SIN_CONFIGURAR","Rollback conserva empresa sin conexión parcial");
        await Save(3,input);
        var info=await store.GetAsync(3,default);var resolved=new SqlConnectionStringBuilder((await store.ResolveAsync(3,default))!);
        check(info.UsuarioSql=="usuario-sql"&&info.UsuarioContable=="usuario-contable"&&resolved.Password==password,"Usuarios SQL y contable separados; transporte resuelve contraseña protegida");
        check(!JsonSerializer.Serialize(info).Contains(password)&&info.TienePassword,"Lectura de empresa no devuelve contraseña");
        q.CommandText="EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;SELECT PasswordProtegido FROM core.ZeusConexion WHERE EmpresaId=3";var encrypted=(string)(await q.ExecuteScalarAsync())!;
        check(!encrypted.Contains(password),"Contraseña no se persiste en texto plano");
        try{store.Unprotect(4,encrypted);throw new Exception("Descifró credencial de otra empresa");}catch(ArgumentException){check(true,"Cifrado está vinculado a la empresa");}
        q.CommandText="SELECT COUNT(*) FROM audit.Evento WHERE ValoresPosteriores LIKE '%solo-prueba-secreta%'";check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"Auditoría no contiene secretos");
        await Save(3,input with{Password=null,Version=1,VersionConfiguracion=1});
        check(new SqlConnectionStringBuilder((await store.ResolveAsync(3,default))!).Password==password,"Contraseña vacía conserva la anterior");
        try{await Save(3,input);throw new Exception("Aceptó versión obsoleta");}catch(ArgumentException){check(true,"Versión obsoleta no sobrescribe conexión");}
        try{await Save(3,input with{Password=null,Servidor="otro",Version=2,VersionConfiguracion=2});throw new Exception("Reutilizó secreto en otro destino");}catch(ArgumentException){check(true,"Cambiar destino exige contraseña explícita");}
        q.CommandText="INSERT ter.Tercero(EmpresaId,TerceroId,RazonSocial) VALUES(3,333,'Proveedor prueba');INSERT core.ZeusProveedorEnvio(EmpresaId,TerceroId,SolicitadoPor,Estado) VALUES(3,333,1,'EN_COLA')";await q.ExecuteNonQueryAsync();
        foreach(var status in new[]{"EN_COLA","ENVIANDO","INCIERTO"}){
            q.CommandText="UPDATE core.ZeusProveedorEnvio SET Estado='"+status+"' WHERE EmpresaId=3";await q.ExecuteNonQueryAsync();
            try{await Save(3,input with{Version=2,VersionConfiguracion=2});throw new Exception("Aceptó cambios durante envío");}catch(SqlException e)when(e.Number==52041){check(true,"Bloquea conexión con proveedor "+status);}
        }
        check((await store.GetAsync(3,default)).Version==2,"Rechazo no deja conexión guardada parcialmente");
        q.CommandText="DELETE core.ZeusProveedorEnvio WHERE EmpresaId=3";await q.ExecuteNonQueryAsync();
        foreach(var status in new[]{"PENDIENTE","ENVIANDO","INCIERTO"}){
            q.CommandText="DELETE cxp.Egreso;INSERT cxp.Egreso(EmpresaId,ZeusEstado) VALUES(3,'"+status+"')";await q.ExecuteNonQueryAsync();
            try{await Save(3,input with{Version=2,VersionConfiguracion=2});throw new Exception("Cambió destino con egreso pendiente");}catch(SqlException e)when(e.Number==52041){check(true,"Bloquea conexión con egreso "+status);}
        }
        q.CommandText="DELETE cxp.Egreso";await q.ExecuteNonQueryAsync();
        await using(var isolated=await factory.OpenAsync(4,false,default)){await using var read=isolated.CreateCommand();read.CommandText="SELECT COUNT(*) FROM core.ZeusConexion";check(Convert.ToInt32(await read.ExecuteScalarAsync())==0,"RLS oculta conexiones de otras empresas");}
        check((await store.GetAsync(4,default)).Origen=="SERVIDOR"&&await store.ResolveAsync(4,default)==legacy,"Conexión heredada del servidor sigue funcionando sin migrar secretos");
        check(await store.ResolveAsync(999,default) is null,"Sin conexión no reutiliza credenciales de otra empresa");
    }
}
