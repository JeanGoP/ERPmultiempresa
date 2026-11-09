using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Zeus;

// La clave identifica una cuota de FACTURAS_BU, no una factura interna de Nexo.
public sealed record ZeusObligationKey(string Bu,string Cuenta,string Unidad,string ClienteProveedor,
    string Tipo,string Numero,string Vencimiento,string Referencia);
public sealed record ZeusOpenObligation(ZeusObligationKey Clave,string Tercero,string Nombre,
    decimal Saldo,string FechaFactura);
public sealed record ZeusHistoricalParty(string Identificacion,string Nombre);
public sealed record ZeusLinkPartyInput(string Identificacion);

public sealed class ZeusHistoricalPortfolio(TenantConnectionFactory connections,ZeusConnectionStore store,ZeusRepository repository)
{
    public async Task<ZeusHistoricalParty[]> SearchPartiesAsync(long company,string term,bool supplier,CancellationToken ct)
    {
        term=term?.Trim()??"";
        if(term.Length<3||term.Length>100)throw new ArgumentException("Busca por al menos tres letras o números en Zeus.");
        await using var zeus=await OpenAsync(company,ct);
        await using var q=zeus.CreateCommand();q.CommandTimeout=30;
        q.CommandText=$"""
            SELECT TOP(30) RTRIM(p.IDTERCERO),RTRIM(p.RAZONCIAL)
            FROM dbo.{(supplier?"PROVEEDORES":"CLIENTES")} p
            WHERE (p.IDTERCERO LIKE @Prefix OR p.RAZONCIAL LIKE @Contains)
              AND ISNULL(p.Deshabilitado,0)=0
            ORDER BY CASE WHEN p.IDTERCERO=@Exact THEN 0 ELSE 1 END,p.RAZONCIAL;
            """;
        q.Parameters.Add("@Prefix",SqlDbType.VarChar,101).Value=term+"%";
        q.Parameters.Add("@Contains",SqlDbType.NVarChar,202).Value="%"+term+"%";
        q.Parameters.Add("@Exact",SqlDbType.VarChar,100).Value=term;
        var result=new List<ZeusHistoricalParty>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))result.Add(new(r.GetString(0),r.GetString(1)));
        return result.ToArray();
    }

    public async Task<long> LinkPartyAsync(long company,string identification,bool supplier,long user,CancellationToken ct)
    {
        identification=identification?.Trim()??"";
        if(identification.Length is <1 or >10||!identification.All(char.IsAsciiLetterOrDigit))
            throw new ArgumentException("La identificación histórica debe tener máximo diez caracteres alfanuméricos.");
        await using var zeus=await OpenAsync(company,ct);
        await using var remote=zeus.CreateCommand();
        remote.CommandText=$"""
            SELECT TOP(2) RTRIM(t.IDTERCERO),RTRIM(t.NOMBRETER),RTRIM(ISNULL(t.TipoIdentificacion,''))
            FROM dbo.TERCEROS t JOIN dbo.{(supplier?"PROVEEDORES":"CLIENTES")} p ON p.IDTERCERO=t.IDTERCERO
            WHERE t.IDTERCERO=@Nit AND ISNULL(t.Deshabilitado,0)=0 AND ISNULL(p.Deshabilitado,0)=0;
            """;
        remote.Parameters.Add("@Nit",SqlDbType.VarChar,25).Value=identification;
        string name,type;
        await using(var r=await remote.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("El tercero ya no está activo en Zeus.");
            name=r.GetString(1);type=r.GetString(2);
            if(await r.ReadAsync(ct))throw new ArgumentException("El tercero está duplicado en Zeus; requiere conciliación.");
        }
        if(name.Length is <1 or >200)throw new ArgumentException("El nombre de Zeus no cabe en el maestro de Nexo.");
        type=type.ToUpperInvariant() switch{"31"=>"NIT","13"=>"CC","NIT"=>"NIT","CC"=>"CC",_=>""};
        if(type.Length==0)throw new ArgumentException("El tipo de identificación de Zeus no está homologado (se requiere NIT o CC). Revísalo en el maestro.");
        await using var local=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await local.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(local,
            "SELECT TOP(2) TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND NumeroIdentificacion=@Nit ORDER BY TerceroId",company,tx);
        ZeusRepository.Add(q,"@Nit",identification);
        long id;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(await r.ReadAsync(ct))
            {
                id=r.GetInt64(0);
                if(await r.ReadAsync(ct))throw new ArgumentException("La identificación tiene varios terceros en Nexo; requiere conciliación.");
            }
            else id=0;
        }
        ZeusRepository.Add(q,"@Id",id);ZeusRepository.Add(q,"@Name",name);ZeusRepository.Add(q,"@Type",type);
        if(id==0)
        {
            q.CommandText="INSERT ter.Tercero(EmpresaId,TipoIdentificacion,NumeroIdentificacion,RazonSocial,EsProveedor,EsCliente) OUTPUT inserted.TerceroId VALUES(@E,@Type,@Nit,@Name,@Supplier,@Client)";
            ZeusRepository.Add(q,"@Supplier",supplier);ZeusRepository.Add(q,"@Client",!supplier);
            id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));q.Parameters["@Id"].Value=id;
        }
        else
        {
            q.CommandText=supplier?"UPDATE ter.Tercero SET EsProveedor=1 WHERE EmpresaId=@E AND TerceroId=@Id":"UPDATE ter.Tercero SET EsCliente=1 WHERE EmpresaId=@E AND TerceroId=@Id";
            await q.ExecuteNonQueryAsync(ct);
        }
        if(!supplier)
        {
            q.CommandText="""
                IF NOT EXISTS(SELECT 1 FROM ven.ClientePerfil WHERE EmpresaId=@E AND TerceroId=@Id)
                    INSERT ven.ClientePerfil(EmpresaId,TerceroId,TipoPersona,ZeusEstado,ZeusMensaje)
                    VALUES(@E,@Id,@Person,'CLIENTE',N'Cliente histórico vinculado desde Zeus.');
                ELSE
                    UPDATE ven.ClientePerfil SET ZeusEstado='CLIENTE',ZeusMensaje=N'Cliente histórico verificado en Zeus.',
                        ZeusActualizadoEnUtc=SYSUTCDATETIME()
                    WHERE EmpresaId=@E AND TerceroId=@Id AND ZeusEstado IN('PENDIENTE','TERCERO','RECHAZADO');
                """;
            ZeusRepository.Add(q,"@Person",type=="NIT"?"J":"N");await q.ExecuteNonQueryAsync(ct);
        }
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,@Action,'ter.Tercero',CONVERT(varchar(30),@Id),@Audit,'ERP')";
        ZeusRepository.Add(q,"@User",user);ZeusRepository.Add(q,"@Action",supplier?"VINCULAR_PROVEEDOR_ZEUS":"VINCULAR_CLIENTE_ZEUS");
        ZeusRepository.Add(q,"@Audit",JsonSerializer.Serialize(new{identificacion=identification,nombre=name,origen="ZEUS"}));
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);return id;
    }
    private async Task<SqlConnection> OpenAsync(long company,CancellationToken ct)
    {
        var settings=(await repository.SettingsAsync(company,ct))?.Configuracion
            ??throw new ArgumentException("Configura Zeus para esta empresa.");
        var secret=await store.ResolveAsync(company,ct);
        if(string.IsNullOrWhiteSpace(secret))throw new ArgumentException("Configura la conexión privada de Zeus.");
        var builder=new SqlConnectionStringBuilder(secret){ApplicationName="NexoERP.CarteraHistorica",ConnectTimeout=15,Enlist=false};
        if(!string.Equals(builder.DataSource,settings.ServidorEsperado,StringComparison.OrdinalIgnoreCase)
            ||!string.Equals(builder.InitialCatalog,settings.BaseEsperada,StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("La conexión Zeus no coincide con la empresa seleccionada.");
        var c=new SqlConnection(builder.ConnectionString);
        try{await c.OpenAsync(ct);return c;}catch{await c.DisposeAsync();throw;}
    }

    public async Task<ZeusOpenObligation[]> ListAsync(long company,long party,bool supplier,CancellationToken ct)
    {
        await using var local=await connections.OpenAsync(company,false,ct);
        await using var lookup=ZeusRepository.Command(local,
            "SELECT NumeroIdentificacion FROM ter.Tercero WHERE EmpresaId=@E AND TerceroId=@P AND Activo=1",company);
        ZeusRepository.Add(lookup,"@P",party);
        var nit=await lookup.ExecuteScalarAsync(ct) as string
            ??throw new ArgumentException("Selecciona un tercero activo de esta empresa.");
        await using var zeus=await OpenAsync(company,ct);
        await using var q=zeus.CreateCommand();q.CommandTimeout=45;
        q.CommandText=$"""
            WITH Vigente AS (
              SELECT f.BU,f.CODICTA,f.IDUNIDAD,f.IDCLIPRV,f.TIPOFACT,f.NUMEFAC,f.VENCFAC,f.REFEFAC,
                f.SACTFAC,f.FECHFAC,p.IDTERCERO,p.RAZONCIAL,ROW_NUMBER() OVER(PARTITION BY f.BU,f.CODICTA,f.IDUNIDAD,
                f.IDCLIPRV,f.TIPOFACT,f.NUMEFAC,f.VENCFAC,f.REFEFAC ORDER BY f.ANOMESFAC DESC) Fila
              FROM dbo.{(supplier?"PROVEEDORES":"CLIENTES")} p
              JOIN dbo.FACTURAS_BU f ON f.IDCLIPRV=p.{(supplier?"IDPROVE":"IDCLIENTE")}
              WHERE f.CODICTA LIKE '{(supplier?"22":"13")}%' AND RTRIM(p.IDTERCERO)=@Nit
            )
            SELECT TOP (5001) RTRIM(f.BU),RTRIM(f.CODICTA),RTRIM(f.IDUNIDAD),RTRIM(f.IDCLIPRV),
              RTRIM(f.TIPOFACT),RTRIM(f.NUMEFAC),RTRIM(f.VENCFAC),RTRIM(f.REFEFAC),
              RTRIM(f.IDTERCERO),RTRIM(f.RAZONCIAL),CONVERT(decimal(20,2),{(supplier?"-":"")}f.SACTFAC),
              RTRIM(ISNULL(f.FECHFAC,''))
            FROM Vigente f WHERE f.Fila=1 AND {(supplier?"-":"")}f.SACTFAC>0 AND ISDATE(f.VENCFAC)=1
            ORDER BY f.VENCFAC,f.NUMEFAC,f.CODICTA,f.BU;
            """;
        q.Parameters.Add("@Nit",SqlDbType.VarChar,25).Value=nit.Trim();
        var result=new List<ZeusOpenObligation>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))
            result.Add(new(new(r.GetString(0),r.GetString(1),r.GetString(2),r.GetString(3),
                r.GetString(4),r.GetString(5),r.GetString(6),r.GetString(7)),
                r.GetString(8),r.GetString(9),r.GetDecimal(10),r.GetString(11)));
        if(result.Count>5000)throw new ArgumentException("El tercero tiene más de 5.000 cuotas abiertas en Zeus. La consulta requiere paginación.");
        // Los documentos originados en Nexo conservan su propio saldo y deben cobrarse
        // por su flujo local; no pueden aparecer una segunda vez como históricos.
        await using var owned=await connections.OpenAsync(company,false,ct);
        await using var localRows=ZeusRepository.Command(owned,supplier?"""
            SELECT d.NumeroDocumento,p.FechaVencimiento FROM cxp.DocumentoPorPagar p
            JOIN comp.DocumentoProveedor d ON d.EmpresaId=p.EmpresaId AND d.DocumentoProveedorId=p.DocumentoProveedorId
            WHERE p.EmpresaId=@E AND p.TerceroId=@P
            """:"""
            SELECT f.Numero,f.ZeusDocumento,COALESCE(c.FechaVencimiento,f.Vencimiento),
                JSON_VALUE(f.Snapshot,'$.ClienteDocumento.CuentaCliente')
            FROM ven.FacturaVenta f LEFT JOIN ven.FacturaVentaCuota c
              ON c.EmpresaId=f.EmpresaId AND c.FacturaVentaId=f.FacturaVentaId
            WHERE f.EmpresaId=@E AND f.ClienteId=@P AND f.ZeusEstado='CONTABILIZADO'
            """,company);
        ZeusRepository.Add(localRows,"@P",party);
        var localKeys=new HashSet<(string,DateOnly)>();var customerKeys=new HashSet<(string,DateOnly,string)>();
        await using(var ownReader=await localRows.ExecuteReaderAsync(ct))while(await ownReader.ReadAsync(ct))
        {
            var due=DateOnly.FromDateTime(ownReader.GetDateTime(supplier?1:2));
            if(supplier)localKeys.Add((ownReader.GetString(0).Trim(),due));
            else
            {
                var account=ownReader.IsDBNull(3)?"":ownReader.GetString(3).Trim();
                customerKeys.Add((ownReader.GetString(0).Trim(),due,account));
                if(!ownReader.IsDBNull(1))
                {
                    var document=ownReader.GetString(1).Trim();
                    customerKeys.Add((document,due,account));
                    if(document.Length==10)customerKeys.Add((document[2..],due,account));
                }
            }
        }
        return result.Where(x=>!DateOnly.TryParse(x.Clave.Vencimiento.Replace('/','-'),out var due)
            ||(supplier?!localKeys.Contains((x.Clave.Numero,due))
                :!customerKeys.Contains((x.Clave.Numero,due,x.Clave.Cuenta)))).ToArray();
    }

    public async Task<ZeusOpenObligation> VerifyAsync(long company,long party,bool supplier,
        ZeusObligationKey key,decimal amount,DateOnly accountingDate,CancellationToken ct)
    {
        if(amount<=0||key is null)throw new ArgumentException("Selecciona una obligación histórica válida.");
        var matches=(await ListAsync(company,party,supplier,ct)).Where(x=>x.Clave==key).ToArray();
        if(matches.Length!=1||matches[0].Saldo<amount)
            throw new ArgumentException("La cuota histórica ya no está abierta o su saldo cambió en Zeus. Actualiza la cartera.");
        if(key.Cuenta.Length>16||key.Tipo.Length>3||key.Numero.Length>15||key.Bu.Length>25
            ||key.ClienteProveedor.Length>10||key.Referencia.Length>25||key.Unidad.Length>3
            ||key.Vencimiento.Length!=10||!DateOnly.TryParse(key.Vencimiento.Replace('/','-'),out _))
            throw new ArgumentException("La clave de la cuota histórica no es válida.");
        if(DateOnly.TryParse(matches[0].FechaFactura.Replace('/','-'),out var invoiceDate)&&invoiceDate>accountingDate)
            throw new ArgumentException("El pago no puede anteceder la factura histórica.");
        return matches[0];
    }
}
