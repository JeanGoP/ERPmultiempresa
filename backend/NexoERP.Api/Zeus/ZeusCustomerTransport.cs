using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Sales;

namespace NexoERP.Api.Zeus;

public sealed record ZeusCustomerResult(string Estado,string Mensaje);
public sealed record ZeusCity(string DivisionPolitica,string CiudadCodigo,string Ciudad,string DepartamentoCodigo,
    string Departamento,string PaisCodigo,string Pais);

public sealed partial class ZeusTransport
{
    public async Task<ZeusCity[]> SearchCitiesAsync(long company,ZeusSettings settings,string search,CancellationToken ct)
    {
        search=search.Trim();
        if(search.Length<2||search.Length>80)throw new ArgumentException("Escribe al menos dos caracteres para buscar la ciudad en Zeus.");
        await using var c=await OpenAsync(company,settings,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            SELECT TOP(30) RTRIM(d.IDDIVPOLITICA),RTRIM(d.DESDIVPOLITICA),
                RTRIM(ISNULL(p.DESDIVPOLITICA,''))
            FROM dbo.DIVPOLITICA d
            LEFT JOIN dbo.DIVPOLITICA p ON p.IDDIVPOLITICA=LEFT(RTRIM(d.IDDIVPOLITICA),4)
            WHERE d.TIPODIVPOLITICA='D'
              AND LEN(RTRIM(d.IDDIVPOLITICA))=7
              AND RTRIM(d.IDDIVPOLITICA) LIKE '57[0-9][0-9][0-9][0-9][0-9]'
              AND (d.DESDIVPOLITICA COLLATE Latin1_General_CI_AI LIKE @Search OR d.IDDIVPOLITICA LIKE @Code)
            ORDER BY d.DESDIVPOLITICA,d.IDDIVPOLITICA;
            """;
        q.Parameters.Add("@Search",SqlDbType.VarChar,90).Value="%"+search+"%";
        q.Parameters.Add("@Code",SqlDbType.VarChar,30).Value="%"+search+"%";
        var cities=new List<ZeusCity>();await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))cities.Add(City(r.GetString(0),r.GetString(1),r.GetString(2)));
        return cities.ToArray();
    }
    public async Task<ZeusCity> FindCityAsync(long company,ZeusSettings settings,string? cityCode,CancellationToken ct)
    {
        cityCode=cityCode?.Trim();
        if(cityCode is null||cityCode.Length!=5||cityCode.Any(c=>!char.IsAsciiDigit(c)))
            throw new ArgumentException("Selecciona una ciudad del catálogo Zeus.");
        await using var c=await OpenAsync(company,settings,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            SELECT RTRIM(d.IDDIVPOLITICA),RTRIM(d.DESDIVPOLITICA),RTRIM(ISNULL(p.DESDIVPOLITICA,''))
            FROM dbo.DIVPOLITICA d
            LEFT JOIN dbo.DIVPOLITICA p ON p.IDDIVPOLITICA=LEFT(RTRIM(d.IDDIVPOLITICA),4)
            WHERE d.IDDIVPOLITICA=@Division AND d.TIPODIVPOLITICA='D';
            """;
        q.Parameters.Add("@Division",SqlDbType.VarChar,25).Value="57"+cityCode;
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))throw new ArgumentException("La ciudad seleccionada ya no existe como división política válida en Zeus.");
        return City(r.GetString(0),r.GetString(1),r.GetString(2));
    }
    private static ZeusCity City(string division,string city,string department)
    {
        division=division.Trim();
        return new(division,division[2..],city.Trim(),division.Substring(2,2),department.Trim(),"57","Colombia");
    }
    private static async Task<bool> CustomerThirdExists(SqlConnection c,SqlTransaction? tx,string id,CancellationToken ct)
    {
        await using var q=c.CreateCommand();q.Transaction=tx;
        q.CommandText="SELECT ISNULL(Deshabilitado,0) FROM dbo.TERCEROS WHERE IDTERCERO=@Id";
        q.Parameters.Add("@Id",SqlDbType.VarChar,25).Value=id;
        var state=await q.ExecuteScalarAsync(ct);
        if(state is null)return false;
        if(Convert.ToInt32(state)!=0)throw new ArgumentException("El tercero existe deshabilitado en Zeus; requiere revisión allí.");
        return true;
    }
    public async Task<ZeusCustomerResult> EnsureCustomerThirdAsync(long company,ZeusSettings settings,CustomerRow customer,CancellationToken ct)
    {
        var stage="conexión";bool committing=false;
        if(customer.DivisionPoliticaZeus is null)throw new ArgumentException("Completa país Colombia y código DANE de cinco dígitos en el cliente.");
        if(customer.TipoPersona=="N"&&(string.IsNullOrWhiteSpace(customer.Nombre1)||string.IsNullOrWhiteSpace(customer.Apellido1)))
            throw new ArgumentException("Completa nombres y apellidos de la persona natural.");
        var secret=await ConnectionAsync(company,ct);
        await using var c=await OpenAsync(company,settings,ct,secret);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        try
        {
            await using var q=c.CreateCommand();q.Transaction=tx;q.CommandTimeout=90;
            q.CommandText="DECLARE @R int; EXEC @R=sys.sp_getapplock @Resource=@Lock,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000; IF @R<0 THROW 52210,'No fue posible bloquear el tercero.',1";
            q.Parameters.AddWithValue("@Lock","NexoERP.Zeus.Tercero:"+customer.NumeroIdentificacion);await q.ExecuteNonQueryAsync(ct);
            if(await CustomerThirdExists(c,tx,customer.NumeroIdentificacion,ct))
            {await tx.RollbackAsync(CancellationToken.None);return new("TERCERO","El tercero ya existe en Zeus; el cliente se creará con la primera factura.");}
            stage="validar maestros del tercero";q.Parameters.Clear();
            q.CommandText="""
                IF NOT EXISTS(SELECT 1 FROM dbo.DIVPOLITICA WHERE IDDIVPOLITICA=@Division AND TIPODIVPOLITICA='D') THROW 52211,'La division politica no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.SEGMENTO WHERE IDSEGMENTO='OTROS' AND TIPOSEGMENTO='D') THROW 52212,'El segmento OTROS no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.TiposDeEmpresa WHERE TipoEmpresa='OTROS') THROW 52213,'La categoria fiscal OTROS no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.TipoIdentificacion WHERE Codigo=@TipoId) THROW 52214,'El tipo de identificacion no existe en Zeus.',1;
                """;
            q.Parameters.AddWithValue("@Division",customer.DivisionPoliticaZeus);
            q.Parameters.AddWithValue("@TipoId",IdentificationCode(customer.TipoIdentificacion));await q.ExecuteNonQueryAsync(ct);
            stage="dbo.spMae_Terceros";
            await using var create=c.CreateCommand();create.Transaction=tx;create.CommandTimeout=90;
            create.CommandType=CommandType.StoredProcedure;create.CommandText="dbo.spMae_Terceros";
            void Add(string name,object? value)=>create.Parameters.AddWithValue(name,value??DBNull.Value);
            Add("@Op","I");Add("@ManejaTransaccionalidad","N");
            Add("@IDTERCERO",customer.NumeroIdentificacion);Add("@NOMBRETER",customer.RazonSocial);
            Add("@TIPOTERCE",customer.TipoPersona);Add("@TipoIdentificacion",IdentificationCode(customer.TipoIdentificacion));
            Add("@DIGIVERIf",customer.DigitoVerificacion??"");Add("@TIPOEMPRESA","OTROS");
            Add("@DIRECCION",customer.Direccion??"");Add("@CIUDAD",customer.Ciudad??"");
            Add("@TELEFONO",customer.Telefono??"");Add("@EMAIL",customer.Correo??"");
            Add("@DIVPOLITICA",customer.DivisionPoliticaZeus);Add("@CODIGODANE",customer.CiudadCodigo??"");
            Add("@SEGMENTO","OTROS");Add("@Usuario",settings.UsuarioZeus);Add("@Tipo","N");Add("@Deshabilitado",0);
            if(customer.TipoPersona=="N"){Add("@Nombre1",customer.Nombre1);Add("@Apellido1",customer.Apellido1);}
            var returned=create.Parameters.Add("@RETURN_VALUE",SqlDbType.Int);returned.Direction=ParameterDirection.ReturnValue;
            await using(var reader=await create.ExecuteReaderAsync(ct))do{while(await reader.ReadAsync(ct)){}}while(await reader.NextResultAsync(ct));
            if(returned.Value is not int code||code!=0)throw new ArgumentException($"spMae_Terceros devolvió {returned.Value}.");
            stage="verificar tercero";
            if(!await CustomerThirdExists(c,tx,customer.NumeroIdentificacion,ct))throw new InvalidOperationException("Zeus no confirmó el tercero.");
            stage="confirmar";committing=true;await tx.CommitAsync(ct);
            return new("TERCERO","Tercero confirmado en Zeus. El registro CLIENTES se creará al emitir la primera factura.");
        }
        catch(Exception error) when(error is SqlException or ArgumentException or InvalidOperationException or OperationCanceledException)
        {
            var uncertain=committing;
            if(!committing)try{await tx.RollbackAsync(CancellationToken.None);}catch{uncertain=true;}
            var detail=error is SqlException sql?string.Join(" | ",sql.Errors.Cast<SqlError>().Where(e=>e.Number!=3621).Take(3).Select(e=>$"SQL {e.Number} · {e.Procedure} · línea {e.LineNumber}: {e.Message}")):error.Message;
            return new(uncertain?"INCIERTO":"RECHAZADO",SafeSupplierDiagnostic($"Etapa: {stage}. {detail}",secret));
        }
    }
    public async Task<ZeusCustomerResult> EnsureCustomerMasterAsync(long company,ZeusSettings settings,CustomerRow customer,string account,CancellationToken ct)
    {
        if(string.IsNullOrWhiteSpace(customer.VendedorZeus)||string.IsNullOrWhiteSpace(customer.TipoClienteZeus))
            throw new ArgumentException("Selecciona vendedor y tipo de cliente de Zeus antes de emitir la primera factura.");
        if(customer.DivisionPoliticaZeus is null)throw new ArgumentException("Falta la división política del cliente.");
        await using var c=await OpenAsync(company,settings,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        bool committing=false;var stage="verificar cliente";
        try
        {
            await using var q=c.CreateCommand();q.Transaction=tx;q.CommandTimeout=90;
            q.CommandText="SELECT COUNT(*) FROM dbo.CLIENTES WHERE IDCLIENTE=@Id AND IDTERCERO=@Id AND ISNULL(Deshabilitado,0)=0";
            q.Parameters.AddWithValue("@Id",customer.NumeroIdentificacion);
            if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))==1)
            {await tx.RollbackAsync(CancellationToken.None);return new("CLIENTE","El cliente ya existe en Zeus.");}
            if(!await CustomerThirdExists(c,tx,customer.NumeroIdentificacion,ct))throw new ArgumentException("El tercero no existe en Zeus; espera su sincronización antes de facturar.");
            stage="validar cuenta y catálogos";q.Parameters.Clear();
            q.CommandText="""
                IF NOT EXISTS(SELECT 1 FROM dbo.MAECONT WHERE CODICTA=@Account AND TIPOCTA='D' AND INDCPICTA=2 AND HABILITARCTA=1) THROW 52220,'Cuenta 13 de clientes inválida.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.MAEVENDE WHERE IDVENDE=@Seller) THROW 52221,'Vendedor inválido en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.TIPOCLIENTES WHERE Codigo=@Kind) THROW 52222,'Tipo de cliente inválido en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.MAEZONAS WHERE IDZONA='GN') THROW 52223,'Zona GN no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.SEGMENTO WHERE IDSEGMENTO='OTROS' AND TIPOSEGMENTO='D') THROW 52224,'Segmento OTROS no existe en Zeus.',1;
                """;
            q.Parameters.AddWithValue("@Account",account);q.Parameters.AddWithValue("@Seller",customer.VendedorZeus);q.Parameters.AddWithValue("@Kind",customer.TipoClienteZeus);
            await q.ExecuteNonQueryAsync(ct);
            stage="dbo.spMae_Clientes";
            await using var create=c.CreateCommand();create.Transaction=tx;create.CommandTimeout=90;
            create.CommandType=CommandType.StoredProcedure;create.CommandText="dbo.spMae_Clientes";
            void Add(string name,object? value)=>create.Parameters.AddWithValue(name,value??DBNull.Value);
            Add("@OP","I");Add("@ManejaTransaccionalidad","N");Add("@IDCLIENTE",customer.NumeroIdentificacion);
            Add("@IDTERCERO",customer.NumeroIdentificacion);Add("@RAZONCIAL",customer.RazonSocial);
            Add("@DIRECCION",customer.Direccion??"");Add("@CIUDAD",customer.Ciudad??"");
            Add("@TELEFONO",customer.Telefono??"");Add("@EMAIL",customer.Correo??"");
            Add("@WEBSITE",customer.SitioWeb??"");Add("@IDZONA","GN");Add("@IDVENDE",customer.VendedorZeus);
            Add("@CODICTA",account);Add("@CONTACTO",customer.ContactoNombre??"");
            Add("@SEGMENTO","OTROS");Add("@TIPOCLIENTE",customer.TipoClienteZeus);
            Add("@DIVPOLITICA",customer.DivisionPoliticaZeus);Add("@CODIGODANE",customer.CiudadCodigo??"");
            Add("@Usuario",settings.UsuarioZeus);Add("@CodAlterno",customer.NumeroIdentificacion);
            var returned=create.Parameters.Add("@RETURN_VALUE",SqlDbType.Int);returned.Direction=ParameterDirection.ReturnValue;
            await using(var reader=await create.ExecuteReaderAsync(ct))do{while(await reader.ReadAsync(ct)){}}while(await reader.NextResultAsync(ct));
            if(returned.Value is not int code||code!=0)throw new ArgumentException($"spMae_Clientes devolvió {returned.Value}.");
            stage="verificar cliente creado";q.Parameters.Clear();q.CommandText="SELECT COUNT(*) FROM dbo.CLIENTES WHERE IDCLIENTE=@Id AND IDTERCERO=@Id AND CODICTA=@Account";
            q.Parameters.AddWithValue("@Id",customer.NumeroIdentificacion);q.Parameters.AddWithValue("@Account",account);
            if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new InvalidOperationException("Zeus no confirmó el cliente con la cuenta de cartera esperada.");
            stage="confirmar";committing=true;await tx.CommitAsync(ct);
            return new("CLIENTE","Cliente creado y verificado en Zeus con la cuenta 13 de su primera factura.");
        }
        catch(Exception error) when(error is SqlException or ArgumentException or InvalidOperationException or OperationCanceledException)
        {
            var uncertain=committing;
            if(!committing)try{await tx.RollbackAsync(CancellationToken.None);}catch{uncertain=true;}
            var detail=error is SqlException sql?string.Join(" | ",sql.Errors.Cast<SqlError>().Where(e=>e.Number!=3621).Take(3).Select(e=>$"SQL {e.Number} · {e.Procedure} · línea {e.LineNumber}: {e.Message}")):error.Message;
            return new(uncertain?"INCIERTO":"RECHAZADO",SafeSupplierDiagnostic($"Etapa: {stage}. {detail}"));
        }
    }
    public async Task<object> CustomerCatalogsAsync(long company,ZeusSettings settings,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,settings,ct);
        await using var q=c.CreateCommand();q.CommandText="SELECT RTRIM(IDVENDE) FROM dbo.MAEVENDE ORDER BY IDVENDE; SELECT RTRIM(Codigo) FROM dbo.TIPOCLIENTES ORDER BY Codigo";
        var sellers=new List<object>();var kinds=new List<object>();await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))sellers.Add(new{codigo=r.GetString(0)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))kinds.Add(new{codigo=r.GetString(0)});
        return new{vendedores=sellers,tipos=kinds};
    }
}
