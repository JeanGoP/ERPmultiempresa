using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Security;

internal static class CompanySecurityTests
{
    public static async Task Run(string cs,string root,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();
        await using var q=c.CreateCommand();
        q.CommandText="""
            ALTER TABLE core.Empresa ADD Codigo varchar(20) NOT NULL DEFAULT 'TEST',Nit varchar(20) NOT NULL DEFAULT 'TEST',RazonSocial nvarchar(200) NOT NULL DEFAULT 'Empresa prueba',MonedaFuncional char(3) NOT NULL DEFAULT 'COP',Activa bit NOT NULL DEFAULT 1;
            ALTER TABLE seg.Usuario ADD Correo nvarchar(254) NULL,NombreCompleto nvarchar(150) NOT NULL DEFAULT 'Prueba',Activo bit NOT NULL DEFAULT 1,EsSuperAdministrador bit NOT NULL DEFAULT 0;
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="""
            UPDATE seg.Usuario SET EsSuperAdministrador=1,Correo='super@test.invalid' WHERE UsuarioId=1;
            INSERT seg.Usuario(UsuarioId,Correo) VALUES(2,'normal@test.invalid'),(3,'legacy@test.invalid'),(4,'sinempresa@test.invalid'),(5,'concurrente@test.invalid');
            CREATE TABLE seg.Rol(RolId bigint PRIMARY KEY,Codigo varchar(50),Nombre nvarchar(100));INSERT seg.Rol VALUES(1,'ADMIN','Administrador'),(2,'USER','Usuario');
            CREATE TABLE seg.UsuarioEmpresaRol(EmpresaId bigint,UsuarioId bigint,RolId bigint,Activo bit,PRIMARY KEY(EmpresaId,UsuarioId,RolId));
            INSERT seg.UsuarioEmpresaRol VALUES(1,2,1,1),(1,3,2,1),(2,3,2,1),(1,1,1,1),(2,2,2,0);
            CREATE TABLE seg.UsuarioCredencial(UsuarioId bigint PRIMARY KEY,PasswordHash varbinary(64),PasswordSalt varbinary(32),Iteraciones int,IntentosFallidos int DEFAULT 0,BloqueadoHastaUtc datetime2 NULL,PasswordActualizadoEnUtc datetime2 NULL);
            CREATE TABLE seg.SesionApi(UsuarioId bigint,TokenHash binary(32),ExpiraEnUtc datetime2,DireccionIp nvarchar(64),RevocadaEnUtc datetime2 NULL);
            """;await q.ExecuteNonQueryAsync();
        var migration=await File.ReadAllTextAsync(Path.Combine(root,"database","migrations","050_single_company_users.sql"));
        for(int pass=0;pass<2;pass++)foreach(var batch in System.Text.RegularExpressions.Regex.Split(migration,@"(?im)^\s*GO\s*$"))
        {if(string.IsNullOrWhiteSpace(batch))continue;q.CommandText=batch;await q.ExecuteNonQueryAsync();}
        check(true,"Migración 050 ejecutable e idempotente con accesos históricos");
        const string password="Solo-Prueba-Local-123!";
        var salt=RandomNumberGenerator.GetBytes(32);var hash=Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password),salt,1000,HashAlgorithmName.SHA512,64);
        q.CommandText="INSERT seg.UsuarioCredencial(UsuarioId,PasswordHash,PasswordSalt,Iteraciones) SELECT UsuarioId,@hash,@salt,1000 FROM seg.Usuario";
        q.Parameters.AddWithValue("@hash",hash);q.Parameters.AddWithValue("@salt",salt);await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        var configuration=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["ConnectionStrings:NexoErp"]=cs}).Build();
        var factory=new TenantConnectionFactory(configuration);var auth=new AuthRepository(factory);var security=new SecurityAdminRepository(factory);
        var normal=await auth.LoginAsync(new("normal@test.invalid",password),null,default);
        check(normal?.EmpresaId==1 && !normal.EsSuperAdministrador,"Login normal resuelve empresa asignada sin selector");
        check((await auth.GetCompaniesAsync(2,default)).Count==1 && !await auth.HasCompanyAccessAsync(2,2,default),"Administrador normal no accede a empresa ajena");
        check((await auth.GetCompaniesAsync(1,default)).Count==2 && await auth.HasCompanyAccessAsync(1,2,default),"Superadministrador conserva acceso a todas las empresas");
        check((await auth.LoginAsync(new("super@test.invalid",password),null,default))?.EmpresaId is null,"Login superadministrador permite elegir empresa");
        foreach(var email in new[]{"legacy@test.invalid","sinempresa@test.invalid"})
        {
            try{await auth.LoginAsync(new(email,password),null,default);throw new Exception("Aceptó asignación inválida");}
            catch(InvalidOperationException){check(true,"Login bloquea asignación múltiple o ausente: "+email);}
        }
        check(!await auth.HasCompanyAccessAsync(3,1,default),"Sesión antigua con asignación múltiple no habilita acceso");
        async Task RejectSql(Func<Task> action,int number,string title)
        {try{await action();throw new Exception("No rechazó: "+title);}catch(SqlException e)when(e.Number==number){check(true,title);}}
        await RejectSql(async()=>{q.CommandText="INSERT seg.UsuarioEmpresaRol VALUES(2,2,1,1)";await q.ExecuteNonQueryAsync();},51730,"Trigger impide segunda empresa activa");
        await RejectSql(async()=>await security.UpdateUserAsync(1,1,2,new(true,[1]),default),51731,"Administrador de empresa no modifica superadministrador");
        await RejectSql(()=>security.ResetPasswordAsync(1,1,2,false,password,default),51731,"Administrador de empresa no cambia contraseña de superadministrador");
        await RejectSql(()=>security.ResetPasswordAsync(2,2,4,false,password,default),51730,"Acceso histórico inactivo no permite cambiar contraseña de usuario ajeno");
        await RejectSql(async()=>await security.CreateUserAsync(2,1,new("super@test.invalid","Super",password,true,[1]),default),51731,"No vincula superadministradores como usuarios de empresa");
        await RejectSql(async()=>await security.CreateUserAsync(2,1,new("normal@test.invalid","Normal",password,true,[1]),default),51730,"No crea segundo acceso activo mediante API");
        q.CommandText="UPDATE seg.UsuarioEmpresaRol SET Activo=0 WHERE UsuarioId=3 AND EmpresaId=2;INSERT seg.UsuarioEmpresaRol VALUES(2,1,1,1)";await q.ExecuteNonQueryAsync();
        check((await auth.LoginAsync(new("legacy@test.invalid",password),null,default))?.EmpresaId==1,"Desactivar acceso histórico recupera login sin reasignación automática");
        check((await auth.GetCompaniesAsync(1,default)).Count==2,"Excepción del trigger para superadministrador");
        await security.UpdateUserAsync(1,2,1,new(true,[1,2]),default);
        check((await auth.GetCompaniesAsync(2,default)).Count==1,"Varios roles de la misma empresa siguen permitidos");
        async Task<bool> Assign(int company)
        {
            await using var cc=new SqlConnection(cs);await cc.OpenAsync();await using var cmd=cc.CreateCommand();
            cmd.CommandText=$"INSERT seg.UsuarioEmpresaRol VALUES({company},5,1,1)";
            try{await cmd.ExecuteNonQueryAsync();return true;}catch(SqlException e)when(e.Number is 51730 or 1205){return false;}
        }
        var assigned=await Task.WhenAll(Assign(1),Assign(2));
        q.CommandText="SELECT COUNT(DISTINCT EmpresaId) FROM seg.UsuarioEmpresaRol WHERE UsuarioId=5 AND Activo=1";
        check(assigned.Count(x=>x)==1 && Convert.ToInt32(await q.ExecuteScalarAsync())==1,"Asignaciones concurrentes no crean usuario multiempresa");
        q.CommandText="ALTER TABLE core.Empresa ADD DigitoVerificacion char(1) NULL,ZonaHoraria nvarchar(80) NOT NULL DEFAULT 'America/Bogota',MarcoContable varchar(20) NOT NULL DEFAULT 'GRUPO_2',RowVersion rowversion";await q.ExecuteNonQueryAsync();
        var master=new CompanyMasterRepository(factory,auth);
        var companies=await master.ListAsync(1,default);
        check(companies.Count==2,"Maestro global lista empresas para superadministrador");
        try{await master.ListAsync(2,default);throw new Exception("Acceso indebido");}catch(UnauthorizedAccessException){check(true,"Maestro rechaza administrador de empresa");}
        var company=companies.Single(x=>x.Id==1);
        var edit=new EditCompanyRequest("TEST1", "123456789", "1", "Empresa editada",company.Version);
        try{await master.UpdateAsync(2,1,edit,default);throw new Exception("Edición indebida");}catch(UnauthorizedAccessException){check(true,"Edición global rechaza usuario normal");}
        await master.UpdateAsync(1,1,edit,default);
        var updated=(await master.ListAsync(1,default)).Single(x=>x.Id==1);
        check(updated.RazonSocial=="Empresa editada"&&updated.MonedaFuncional==company.MonedaFuncional&&updated.MarcoContable==company.MarcoContable&&updated.Version!=company.Version,"Edición conserva parámetros contables y renueva versión");
        await RejectSql(()=>master.UpdateAsync(1,1,edit,default),52040,"Maestro impide sobrescribir una versión antigua");
        q.CommandText="SELECT COUNT(*) FROM audit.Evento WHERE Operacion='EMPRESA_ACTUALIZADA' AND EmpresaId=1";
        check(Convert.ToInt32(await q.ExecuteScalarAsync())==1,"Edición de empresa deja auditoría transaccional");
        try{CompanyMasterRepository.Validate("A","123","12","Empresa");throw new Exception("DV inválido aceptado");}catch(ArgumentException){check(true,"DV inválido no se trunca silenciosamente");}
    }
}
