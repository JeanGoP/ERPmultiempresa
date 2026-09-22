using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.MasterData;
using NexoERP.Api.Zeus;

static class BranchCatalogTests
{
    public static async Task Run(string cs,string root,ZeusSettings settings,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;UPDATE core.ZeusConfiguracion SET Configuracion=@J WHERE EmpresaId=1";
        q.Parameters.AddWithValue("@J",JsonSerializer.Serialize(settings with{FuentesAutomaticas=[new("Norte","ENTRADA_MERCANCIA","13","01",[1])]}));await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        var migration=await File.ReadAllTextAsync(Path.Combine(root,"database","migrations","055_company_branches.sql"));
        for(var pass=0;pass<2;pass++)foreach(var batch in Regex.Split(migration,@"(?im)^\s*GO\s*$")){if(string.IsNullOrWhiteSpace(batch))continue;q.CommandText=batch;await q.ExecuteNonQueryAsync();}
        var factory=new TenantConnectionFactory(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{{"ConnectionStrings:NexoErp",cs}}).Build());
        var repo=new BranchCatalogRepository(factory);
        var migrated=(await repo.ListAsync(1,default)).Single();
        check(migrated.Nombre=="Norte"&&migrated.Activa,"Migración 055 idempotente conserva sucursales de reglas existentes");
        check((await repo.ListAsync(2,default)).Count==0,"Catálogo de sucursales aislado por empresa");
        var id=await repo.SaveAsync(2,null,new("01","Centro",true),1,default);
        await repo.SaveAsync(2,id,new("01","Centro actualizado",true),1,default);
        check((await repo.ListAsync(2,default)).Single().Nombre=="Centro actualizado","Permite crear y editar sucursal");
        async Task Reject(Func<Task> action,string title){try{await action();throw new Exception("No rechazó: "+title);}catch(ArgumentException){check(true,title);}}
        await Reject(async()=>{await repo.SaveAsync(1,id,new("99","Ajena",true),1,default);},"No modifica sucursal de otra empresa");
        await Reject(async()=>{await repo.SaveAsync(1,migrated.Id,new(migrated.Codigo,migrated.Nombre,false),1,default);},"No desactiva sucursal asignada a fuentes");
        try{await repo.SaveAsync(2,null,new("01","Duplicada",true),1,default);throw new Exception("Aceptó código duplicado");}catch(SqlException e) when(e.Number is 2601 or 2627){check(true,"Código de sucursal único por empresa");}
        await using(var tenant=await factory.OpenAsync(1,false,default))
        {
            await using var tx=(SqlTransaction)await tenant.BeginTransactionAsync();
            await Reject(async()=>{await BranchCatalogRepository.ResolveAsync(tenant,tx,1,new("Centro actualizado","EGRESO","20","00",[],id),default);},"Fuente rechaza sucursal de otra empresa aunque envíen su ID");
            var valid=await BranchCatalogRepository.ResolveAsync(tenant,tx,1,new("Nombre manipulado","EGRESO","20","00",[],migrated.Id),default);
            check(valid.Nombre=="Norte","Nombre de sucursal se obtiene del catálogo, no del cliente");
            await tx.RollbackAsync();
        }
        await repo.SaveAsync(2,id,new("01","Centro actualizado",false),1,default);
        await using(var tenant=await factory.OpenAsync(2,false,default))
        {
            await using var tx=(SqlTransaction)await tenant.BeginTransactionAsync();
            await Reject(async()=>{await BranchCatalogRepository.ResolveAsync(tenant,tx,2,new("Centro actualizado","EGRESO","20","00",[],id),default);},"Fuente rechaza sucursal inactiva");
            await tx.RollbackAsync();
        }
        q.CommandText="SELECT COUNT(*) FROM core.Sucursal WHERE EmpresaId=2";check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"RLS filtra catálogo aun consultando empresa ajena directamente");
        q.CommandText="SELECT COUNT(*) FROM audit.Evento WHERE Operacion='GUARDAR_SUCURSAL'";check(Convert.ToInt32(await q.ExecuteScalarAsync())>=3,"Cambios de sucursales quedan auditados");
    }
}
