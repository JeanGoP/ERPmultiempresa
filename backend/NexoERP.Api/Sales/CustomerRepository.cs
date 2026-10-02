using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Sales;

public sealed record CustomerInput(
    string TipoIdentificacion,string NumeroIdentificacion,string? DigitoVerificacion,string RazonSocial,
    string? NombreComercial,string? CodigoResponsabilidadFiscal,string? RegimenFiscalCodigo,string? RegimenFiscalNombre,
    string? Direccion,string? CiudadCodigo,string? Ciudad,string? DepartamentoCodigo,string? Departamento,
    string? CodigoPostal,string? PaisCodigo,string? Pais,string? ContactoNombre,string? Telefono,string? Correo,
    string? SitioWeb,string TipoPersona,string? Nombre1,string? Apellido1,string? VendedorZeus,string? TipoClienteZeus);

public sealed record CustomerRow(long TerceroId,string TipoIdentificacion,string NumeroIdentificacion,string? DigitoVerificacion,
    string RazonSocial,string? NombreComercial,string? CodigoResponsabilidadFiscal,string? RegimenFiscalCodigo,
    string? RegimenFiscalNombre,string? Direccion,string? CiudadCodigo,string? Ciudad,string? DepartamentoCodigo,
    string? Departamento,string? CodigoPostal,string? PaisCodigo,string? Pais,string? ContactoNombre,string? Telefono,
    string? Correo,string? SitioWeb,string TipoPersona,string? Nombre1,string? Apellido1,string? VendedorZeus,
    string? TipoClienteZeus,string? DivisionPoliticaZeus,string ZeusEstado,string? ZeusMensaje,bool Activo);

public sealed class CustomerRepository(TenantConnectionFactory connections)
{
    private static string? Text(SqlDataReader r,int i)=>r.IsDBNull(i)?null:r.GetString(i);
    public async Task<bool> RetryZeusAsync(long company,long id,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            UPDATE ven.ClientePerfil SET ZeusEstado='PENDIENTE',ZeusMensaje=N'Reintentando creación o verificación del tercero.',
                ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND TerceroId=@Id AND ZeusEstado IN('RECHAZADO','INCIERTO');
            """;
        q.Parameters.AddWithValue("@E",company);q.Parameters.AddWithValue("@Id",id);
        return await q.ExecuteNonQueryAsync(ct)==1;
    }
    public async Task<CustomerRow[]> ListAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            SELECT t.TerceroId,t.TipoIdentificacion,t.NumeroIdentificacion,t.DigitoVerificacion,t.RazonSocial,
                t.NombreComercial,t.CodigoResponsabilidadFiscal,t.RegimenFiscalCodigo,t.RegimenFiscalNombre,
                t.Direccion,t.CiudadCodigo,t.Ciudad,t.DepartamentoCodigo,t.Departamento,t.CodigoPostal,
                t.PaisCodigo,t.Pais,t.ContactoNombre,t.Telefono,t.Correo,t.SitioWeb,
                p.TipoPersona,p.Nombre1,p.Apellido1,p.VendedorZeus,p.TipoClienteZeus,t.DivisionPoliticaZeus,
                p.ZeusEstado,p.ZeusMensaje,t.Activo
            FROM ter.Tercero t JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId
            WHERE t.EmpresaId=@E AND t.EsCliente=1 ORDER BY t.RazonSocial;
            """;q.Parameters.AddWithValue("@E",company);
        var rows=new List<CustomerRow>();await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))rows.Add(new(r.GetInt64(0),r.GetString(1),r.GetString(2),Text(r,3),r.GetString(4),
            Text(r,5),Text(r,6),Text(r,7),Text(r,8),Text(r,9),Text(r,10),Text(r,11),Text(r,12),Text(r,13),
            Text(r,14),Text(r,15),Text(r,16),Text(r,17),Text(r,18),Text(r,19),Text(r,20),r.GetString(21),
            Text(r,22),Text(r,23),Text(r,24),Text(r,25),Text(r,26),r.GetString(27),Text(r,28),r.GetBoolean(29)));
        return rows.ToArray();
    }
    public async Task<object> SaveAsync(long company,long? id,CustomerInput input,long user,CancellationToken ct)
    {
        if(string.IsNullOrWhiteSpace(input.NumeroIdentificacion)||string.IsNullOrWhiteSpace(input.RazonSocial))
            throw new ArgumentException("Identificación y nombre del cliente son obligatorios.");
        if(input.NumeroIdentificacion.Trim().Length>10||input.NumeroIdentificacion.Any(c=>!char.IsAsciiLetterOrDigit(c)))
            throw new ArgumentException("La identificación de Zeus admite máximo 10 letras o dígitos sin separadores.");
        if(input.TipoIdentificacion is "NIT" && input.TipoPersona!="J"||input.TipoIdentificacion is "CC" && input.TipoPersona!="N")
            throw new ArgumentException("NIT corresponde a persona jurídica y CC a persona natural.");
        if(string.IsNullOrWhiteSpace(input.VendedorZeus)||string.IsNullOrWhiteSpace(input.TipoClienteZeus))
            throw new ArgumentException("Selecciona vendedor y tipo de cliente de Zeus.");
        if(input.TipoPersona=="N"&&(string.IsNullOrWhiteSpace(input.Nombre1)||string.IsNullOrWhiteSpace(input.Apellido1)))
            throw new ArgumentException("Completa nombres y apellidos de la persona natural.");
        if(input.PaisCodigo?.Trim().ToUpperInvariant() is not ("CO" or "COL" or "57")||
            input.CiudadCodigo?.Length!=5||!input.CiudadCodigo.All(char.IsAsciiDigit))
            throw new ArgumentException("Selecciona Colombia y escribe el código DANE de cinco dígitos para Zeus.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=c.CreateCommand();q.CommandType=CommandType.StoredProcedure;q.CommandText="ter.usp_GuardarCliente";
        void Add(string name,SqlDbType type,object? value,int? size=null){var p=q.Parameters.Add(name,type);if(size.HasValue)p.Size=size.Value;p.Value=value??DBNull.Value;}
        Add("@EmpresaId",SqlDbType.BigInt,company);Add("@TerceroId",SqlDbType.BigInt,id);
        Add("@TipoIdentificacion",SqlDbType.VarChar,input.TipoIdentificacion,10);
        Add("@NumeroIdentificacion",SqlDbType.NVarChar,input.NumeroIdentificacion,30);
        Add("@DigitoVerificacion",SqlDbType.Char,input.DigitoVerificacion,1);
        Add("@RazonSocial",SqlDbType.NVarChar,input.RazonSocial,200);
        Add("@NombreComercial",SqlDbType.NVarChar,input.NombreComercial,200);
        Add("@CodigoResponsabilidadFiscal",SqlDbType.NVarChar,input.CodigoResponsabilidadFiscal,100);
        Add("@RegimenFiscalCodigo",SqlDbType.NVarChar,input.RegimenFiscalCodigo,20);
        Add("@RegimenFiscalNombre",SqlDbType.NVarChar,input.RegimenFiscalNombre,100);
        Add("@Direccion",SqlDbType.NVarChar,input.Direccion,300);
        Add("@CiudadCodigo",SqlDbType.NVarChar,input.CiudadCodigo,20);
        Add("@Ciudad",SqlDbType.NVarChar,input.Ciudad,100);
        Add("@DepartamentoCodigo",SqlDbType.NVarChar,input.DepartamentoCodigo,20);
        Add("@Departamento",SqlDbType.NVarChar,input.Departamento,100);
        Add("@CodigoPostal",SqlDbType.NVarChar,input.CodigoPostal,20);
        Add("@PaisCodigo",SqlDbType.NVarChar,input.PaisCodigo,10);
        Add("@Pais",SqlDbType.NVarChar,input.Pais,100);
        Add("@ContactoNombre",SqlDbType.NVarChar,input.ContactoNombre,150);
        Add("@Telefono",SqlDbType.NVarChar,input.Telefono,50);
        Add("@Correo",SqlDbType.NVarChar,input.Correo,254);
        Add("@SitioWeb",SqlDbType.NVarChar,input.SitioWeb,300);
        Add("@TipoPersona",SqlDbType.Char,input.TipoPersona,1);
        Add("@Nombre1",SqlDbType.NVarChar,input.Nombre1,60);
        Add("@Apellido1",SqlDbType.NVarChar,input.Apellido1,60);
        Add("@VendedorZeus",SqlDbType.VarChar,input.VendedorZeus,3);
        Add("@TipoClienteZeus",SqlDbType.VarChar,input.TipoClienteZeus,3);
        Add("@UsuarioId",SqlDbType.BigInt,user);
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))throw new InvalidOperationException("Zeus no recibió el cliente porque el ERP no confirmó el maestro.");
        return new{id=r.GetInt64(0),creado=r.GetBoolean(1),zeusEstado="PENDIENTE"};
    }
}
